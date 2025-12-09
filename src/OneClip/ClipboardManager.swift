import Foundation
import AppKit
import Combine
import CoreGraphics
import PDFKit
import UserNotifications

// 确保能访问 ClipboardItemType 和 ClipboardItem

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var unreadCount: Int = 0
    private var lastChangeCount: Int = 0
    private var clipboardObserver: NSObjectProtocol?
    private var monitoringTimer: Timer?
    private let settingsManager = SettingsManager.shared
    private let logger = Logger.shared
    
    // 延迟初始化 store，以便传入 settingsManager
    internal lazy var store = ClipboardStore(getCleanupDays: { [weak self] in
        return self?.settingsManager.autoCleanupDays ?? 30
    })
    private let cacheDirectory: URL
    
    // 性能优化：内存管理
    private let maxItems: Int = 100
    private let maxImageSize: Int = 10 * 1024 * 1024 // 10MB
    private var imageCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        cache.countLimit = 20
        return cache
    }()
    
    // 图片验证缓存 - 避免重复验证相同数据
    private var imageValidationCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 100
        return cache
    }()
    
    // 防止重复监控的机制
    private var isPerformingCopyOperation = false
    private var copyOperationTimestamp: TimeInterval = 0
    private var lastChangeTimestamp: TimeInterval = 0
    
    // 应用状态和监控管理
    private var isAppActive: Bool = true
    private var lastActiveTime: Date = Date()
    
    // 智能休眠相关属性
    private var currentMonitoringInterval: TimeInterval = 0.6
    private let activeMonitoringInterval: TimeInterval = 0.6  // 活跃时的监控间隔
    private let inactiveMonitoringInterval: TimeInterval = 2.0  // 不活跃时的监控间隔
    private let sleepMonitoringInterval: TimeInterval = 5.0   // 深度休眠时的监控间隔
    private var activityMonitor: UserActivityMonitor = UserActivityMonitor.shared
    private var currentActivityState: UserActivityState = .active
    
    // 去重机制优化
    private var recentHashes: Set<String> = []
    private var lastHashCleanup: Date = Date()
    
    // 缓存清理管理
    private var cacheCleanupTimer: Timer?
    private let cacheCleanupInterval: TimeInterval = 600 // 10分钟清理一次
    
    // 针对浏览器复制优化的去重机制
    private var lastContentHash: String = ""
    private var lastContentTime: Date = Date.distantPast
    private let duplicateTimeWindow: TimeInterval = 0.5 // 减少到0.5秒，允许快速复制不同内容
    
    // 搜索优化
    @Published var searchText: String = "" {
        didSet {
            updateFilteredItems()
        }
    }
    @Published var filteredItems: [ClipboardItem] = []
    
    private init() {
        // 创建缓存目录
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesURL.appendingPathComponent("OneClip", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
            logger.info("缓存目录创建成功: \(cacheDirectory.path)")
        } catch {
            logger.error("创建缓存目录失败: \(error.localizedDescription)")
        }
        
        // 设置内存压力监听
        setupMemoryPressureMonitoring()
        
        // 启动智能缓存清理
        setupSmartCacheCleanup()
        
        // 设置用户活动监控
        setupUserActivityMonitoring()
        
        loadClipboardItems()
        updateFilteredItems()
    }
    
    func startMonitoring() {
        // 检查权限状态
        do {
            try checkPermissions()
            setupClipboardObserver()
            
            // 启动用户活动监控
            activityMonitor.startMonitoring()
            
            logger.info("剪贴板监控已启动")
        } catch {
            logger.error("启动剪贴板监控失败: \(error.localizedDescription)")
        }
    }
    
    private func setupClipboardObserver() {
        // 移除现有观察者
        if let observer = clipboardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // 使用 DistributedNotificationCenter 监听剪贴板变化（主要监控机制）
        clipboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.pasteboard.changed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkClipboardChange()
            }
        }
        
        // 使用动态监控间隔，根据用户活动状态调整
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: currentMonitoringInterval, repeats: true) { [weak self] _ in
            self?.checkClipboardChange()
        }
        
        // 立即执行一次检查
        checkClipboardChange()
        
        // 添加应用状态监听器
        setupApplicationStateObservers()
        
        logger.info("🔄 剪贴板监控已设置，初始检查频率: \(currentMonitoringInterval * 1000)ms (智能调节模式)")
    }
    
    // 设置应用状态监听器
    private func setupApplicationStateObservers() {
        // 监听应用激活事件
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationDidBecomeActive()
        }
        
        // 监听应用进入后台事件
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationWillResignActive()
        }
        
        // 监听系统休眠/唤醒事件
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("💤 系统即将休眠")
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("🌅 系统从休眠中唤醒")
            // 强制检查剪贴板状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkClipboardChange()
            }
        }
        
        logger.debug("🔧 应用状态监听器已设置")
    }
    
    // 应用状态处理方法
    private func handleApplicationDidBecomeActive() {
        logger.info("📱 应用重新获得焦点（从后台返回或重新激活）")
        isAppActive = true
        lastActiveTime = Date()
        
        // 清除未读计数
        clearUnreadCount()
        
        // 强制检查剪贴板变化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.checkClipboardChange()
        }
    }
    
    // MARK: - 未读计数管理
    func clearUnreadCount() {
        logger.info("🔄 清除未读计数: \(unreadCount) -> 0")
        unreadCount = 0
        // 只有在启用通知时才清除dock栏角标
        if SettingsManager.shared.enableNotifications {
            let app = NSApplication.shared.dockTile
            app.badgeLabel = nil
        }
    }
    
    func markAsRead() {
        clearUnreadCount()
    }
    
    // MARK: - 用户活动管理
    /// 更新用户活动状态，用于智能休眠功能
    public func updateUserActivity() {
        activityMonitor.updateActivity()
    }
    
    private func handleApplicationWillResignActive() {
        logger.info("📱 应用失去焦点（进入后台或失去活跃状态）")
        isAppActive = false
    }
    
    private func checkPermissions() throws {
        // 检查剪贴板访问权限
        let pasteboard = NSPasteboard.general
        
        // 尝试访问剪贴板以检查权限
        guard pasteboard.types != nil else {
            logger.error("❌ 剪贴板访问被拒绝 - 可能需要在系统偏好设置中授予权限")
            
            // 显示用户友好的错误提示
            DispatchQueue.main.async {
                self.showPermissionAlert()
            }
            
            throw ClipboardError.accessDenied
        }
        
        // 检查辅助功能权限 - 静默检查，不弹出提示
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
            logger.warning("辅助功能权限未授予，但不阻止基本功能")
            // 不抛出错误，允许基本功能继续工作
        }
        
        logger.info("权限检查完成")
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要剪贴板访问权限"
        alert.informativeText = """
        OneClip 需要访问剪贴板以监控复制的内容。
        
        请按照以下步骤授予权限：
        1. 打开系统偏好设置 > 安全性与隐私 > 隐私
        2. 在左侧列表中找到"辅助功能"或"自动化"
        3. 确保 OneClip 已添加并勾选
        4. 重启 OneClip 应用
        
        如果问题仍然存在，请尝试重新授权或联系技术支持。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统偏好设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 适配不同版本 macOS 的系统设置打开方式
            let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion
            if macOSVersion.majorVersion >= 13 { // macOS Ventura 及以后
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(settingsURL)
                }
            } else {
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        }
    }
    
    private func retryClipboardAccess() {
        logger.info("🔄 尝试重新访问剪贴板...")
        
        let pasteboard = NSPasteboard.general
        
        // 尝试重新获取类型信息
        if let types = pasteboard.types, !types.isEmpty {
            logger.info("✅ 剪贴板访问恢复，重新处理内容")
            // 重新处理剪贴板内容
            handleClipboardChange()
        } else {
            logger.warning("⚠️ 剪贴板仍然无法访问，可能需要用户手动授权")
            
            // 检查是否需要显示权限提示
            DispatchQueue.main.async {
                self.showPermissionAlert()
            }
        }
    }
    
    func stopMonitoring() {
        if let observer = clipboardObserver {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            clipboardObserver = nil
        }
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // 停止缓存清理定时器
        cacheCleanupTimer?.invalidate()
        cacheCleanupTimer = nil
        
        // 停止用户活动监控
        activityMonitor.stopMonitoring()
        
        logger.info("剪贴板监控已停止")
    }
    
    // MARK: - 用户活动监控和智能休眠
    
    private func setupUserActivityMonitoring() {
        // 监听用户活动状态变化
        NotificationCenter.default.addObserver(
            forName: .userBecameActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleUserBecameActive()
        }
        
        NotificationCenter.default.addObserver(
            forName: .userBecameInactive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleUserBecameInactive()
        }
        
        // 初始化当前监控间隔
        currentMonitoringInterval = activeMonitoringInterval
        
        logger.info("🔍 用户活动监控已设置")
    }
    
    private func handleUserBecameActive() {
        logger.info("🟢 用户重新活跃，切换到活跃监控模式")
        currentActivityState = .active
        updateMonitoringInterval(to: activeMonitoringInterval)
    }
    
    private func handleUserBecameInactive() {
        logger.info("🟡 用户进入不活跃状态，切换到节能监控模式")
        currentActivityState = .inactive
        
        // 根据不活跃时间决定监控间隔
        let inactivityDuration = activityMonitor.getInactivityDuration()
        if inactivityDuration > 300 { // 5分钟以上进入深度休眠
            currentActivityState = .sleeping
            updateMonitoringInterval(to: sleepMonitoringInterval)
            logger.info("😴 进入深度休眠模式")
        } else {
            updateMonitoringInterval(to: inactiveMonitoringInterval)
        }
    }
    
    private func updateMonitoringInterval(to newInterval: TimeInterval) {
        guard newInterval != currentMonitoringInterval else { return }
        
        currentMonitoringInterval = newInterval
        
        // 重新设置定时器
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
            self?.checkClipboardChange()
        }
        
        logger.info("⏱️ 监控间隔已调整为: \(newInterval)秒 (状态: \(currentActivityState.description))")
    }
    
    private func checkClipboardChange() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            logger.debug("📋 检测到剪贴板变化: \(lastChangeCount) -> \(currentChangeCount)")
            
            // 检查是否是我们自己的复制操作触发的
            let now = Date().timeIntervalSince1970
            if isPerformingCopyOperation && (now - copyOperationTimestamp) < 2.0 {
                logger.debug("跳过自己的复制操作触发的剪贴板变化")
                lastChangeCount = currentChangeCount
                return
            }
            
            // 防抖处理，减少频繁检查
            let timeSinceLastChange = now - lastChangeTimestamp
            if timeSinceLastChange < 0.2 { // 提高到200ms防抖
                logger.debug("跳过过于频繁的剪贴板变化 (间隔: \(timeSinceLastChange * 1000)ms)")
                lastChangeCount = currentChangeCount
                return
            }
            
            lastChangeCount = currentChangeCount
            lastChangeTimestamp = now
            
            // 处理剪贴板变化
            logger.info("🚀 处理剪贴板变化")
            handleClipboardChange()
        }
    }
    
    private func handleClipboardChange() {
        // 立即激活用户活动状态，确保响应及时
        activityMonitor.updateActivity()
        
        let pasteboard = NSPasteboard.general
        
        // 详细的剪贴板状态检查
        logger.debug("📋 剪贴板变化检测开始")
        logger.debug("📋 剪贴板变化计数: \(pasteboard.changeCount)")
        
        let types = pasteboard.types
        logger.debug("📋 剪贴板可用类型: \(types?.map { $0.rawValue } ?? ["nil"])")
        
        // 如果 types 为空，尝试权限检查和重试
        if types == nil || types?.isEmpty == true {
            logger.error("❌ 剪贴板类型为空，可能是权限问题或系统限制")
            
            // 尝试重新获取权限并重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.retryClipboardAccess()
            }
            return
        }
        
        // 快速去重检查：避免浏览器复制等场景的重复内容
        let currentHash = calculateQuickContentHash(pasteboard)
        let currentTime = Date()
        
        if currentHash == lastContentHash && 
           currentTime.timeIntervalSince(lastContentTime) < duplicateTimeWindow {
            logger.debug("检测到重复内容，跳过处理（哈希: \(String(currentHash.prefix(8)))）")
            return
        }
        
        // 更新去重信息
        lastContentHash = currentHash
        lastContentTime = currentTime
        
        // 重新设计的检测逻辑：智能区分访达文件复制和直接图片复制
        
        // 1. 首先检查是否有本地文件URL（访达复制文件的情况）
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !fileURLs.isEmpty {
            logger.info("📁 发现URL: \(fileURLs.map { $0.absoluteString })")
            
            // 过滤出真正的本地文件URL（file:// 协议且文件存在）
            let localFileURLs = fileURLs.filter { url in
                return url.isFileURL && FileManager.default.fileExists(atPath: url.path)
            }
            
            if !localFileURLs.isEmpty {
                logger.info("📁 确认本地文件URL: \(localFileURLs.map { $0.path })")
                
                // 检查是否为图片文件
                let imageFileURLs = localFileURLs.filter { url in
                    let pathExtension = url.pathExtension.lowercased()
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg", "ico", "icns"]
                    return imageExtensions.contains(pathExtension)
                }
                
                if !imageFileURLs.isEmpty {
                    logger.info("检测到本地图片文件，加载原始图片: \(imageFileURLs.map { $0.path })")
                    handleImageFileContent(imageFileURLs)
                    return
                } else {
                    logger.info("处理非图片本地文件")
                    handleFileContent(localFileURLs)
                    return
                }
            } else {
                logger.debug("发现网络URL或不存在的文件路径，继续检查图片内容")
                // 继续下面的图片内容检查逻辑
            }
        }
        
        // 2. 检查直接的图片内容（浏览器复制图片等）
        let hasImage = hasImageContent(pasteboard)
        logger.debug("图片内容检测结果: \(hasImage)")
        
        if hasImage {
            logger.info("检测到直接图片内容（非文件复制）")
            handleImageContentSync(pasteboard)
            return
        }
        
        // 3. 检查富文本内容（带格式的文本）
        if let rtfData = pasteboard.data(forType: .rtf),
           let rtfString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let plainText = rtfString.string
            if !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !isDuplicateContent(plainText, type: ClipboardItemType.text) {
                    addClipboardItem(content: plainText, type: ClipboardItemType.text, data: rtfData)
                    logger.info("富文本内容已添加: \(plainText.prefix(30))")
                } else {
                    logger.debug("跳过重复富文本内容")
                }
                return
            }
        }
        
        // 4. 检查 HTML 内容（可能包含图片链接）
        if let htmlData = pasteboard.data(forType: .html),
           let htmlString = String(data: htmlData, encoding: .utf8) {
            if !htmlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 尝试从 HTML 中提取纯文本
                let plainText = extractPlainTextFromHTML(htmlString)
                if !plainText.isEmpty && !isDuplicateContent(plainText, type: .text) {
                    addClipboardItem(content: plainText, type: .text, data: htmlData)
                    logger.info("HTML 内容已添加: \(plainText.prefix(30))")
                } else {
                    logger.debug("HTML 内容为空或重复")
                }
                return
            }
        }
        
        // 5. 最后检查纯文本内容
        if let text = pasteboard.string(forType: .string), 
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !isDuplicateContent(text, type: .text) {
                addClipboardItem(content: text, type: .text)
                logger.info("纯文本内容已添加: \(text.prefix(30))")
            } else {
                logger.debug("跳过重复纯文本内容")
            }
            return
        }
        
        // 6. 特殊检查：可能存在的其他数据类型
        if let types = pasteboard.types {
            for type in types {
                let typeString = type.rawValue.lowercased()
                // 检查是否有我们可能错过的图片类型
                if typeString.contains("image") && !typeString.contains("url") && !typeString.contains("path") {
                    if let data = pasteboard.data(forType: type), data.count > 50 {
                        logger.debug("发现可能的图片类型: \(type.rawValue)")
                        // 重新尝试图片处理
                        handleImageContentSync(pasteboard)
                        return
                    }
                }
            }
        }
        
        logger.warning("未识别的剪贴板内容类型，可用类型: \(pasteboard.types?.map { $0.rawValue } ?? [])")
    }
    
    // 从 HTML 中提取纯文本
    private func extractPlainTextFromHTML(_ html: String) -> String {
        // 简单的 HTML 标签移除
        var text = html
        
        // 移除常见的 HTML 标签
        let htmlTags = [
            "<[^>]+>", // 所有 HTML 标签
            "&nbsp;", "&amp;", "&lt;", "&gt;", "&quot;", "&#39;", // HTML 实体
        ]
        
        for pattern in htmlTags {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        
        // 清理多余的空白字符
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    // MARK: - Enhanced File Type Support
    
    private struct FileTypeClassifier {
        static let imageExtensions = [
            // Common formats
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "svg",
            // Apple formats
            "heic", "heif",
            // Adobe formats  
            "psd", "ai", "eps",
            // Raw formats
            "raw", "cr2", "nef", "arw", "dng",
            // Other formats
            "ico", "icns", "jp2", "j2k"
        ]
        
        static let videoExtensions = [
            // Common video formats
            "mp4", "avi", "mkv", "mov", "wmv", "flv", "webm", "m4v", "3gp",
            // Apple formats
            "m4v", "mov",
            // Professional formats
            "prores", "dnxhd", "avchd"
        ]
        
        static let audioExtensions = [
            // Common audio formats
            "mp3", "wav", "flac", "aac", "ogg", "wma", "m4a", "opus",
            // Apple formats
            "aiff", "caf",
            // Professional formats
            "alac", "dsd"
        ]
        
        static let documentExtensions = [
            // Microsoft Office
            "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            // Adobe
            "pdf",
            // Apple
            "pages", "numbers", "keynote",
            // Text formats
            "txt", "rtf", "md", "tex",
            // Other office formats
            "odt", "ods", "odp"
        ]
        
        static let codeExtensions = [
            // Programming languages
            "swift", "py", "js", "ts", "html", "css", "java", "cpp", "c", "h",
            "go", "rs", "php", "rb", "kt", "scala", "cs", "vb",
            // Config and data
            "json", "xml", "yaml", "yml", "toml", "ini", "cfg",
            // Scripts
            "sh", "bat", "ps1", "zsh", "fish",
            // Web
            "vue", "jsx", "tsx", "scss", "less", "sass"
        ]
        
        static let archiveExtensions = [
            // Common archives
            "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
            // Apple formats
            "dmg", "pkg", "app",
            // Disk images
            "iso", "img"
        ]
        
        static let executableExtensions = [
            // macOS
            "app", "pkg", "dmg",
            // Cross-platform
            "exe", "msi", "deb", "rpm", "appimage"
        ]
        
        static func classifyFileType(fileExtension: String) -> (category: String, icon: String, description: String, itemType: ClipboardItemType) {
            let ext = fileExtension.lowercased()
            
            if imageExtensions.contains(ext) {
                return ("图片", "photo", getImageTypeDescription(ext), .image)
            } else if videoExtensions.contains(ext) {
                return ("视频", "video", getVideoTypeDescription(ext), .video)
            } else if audioExtensions.contains(ext) {
                return ("音频", "music.note", getAudioTypeDescription(ext), .audio)
            } else if documentExtensions.contains(ext) {
                return ("文档", "doc.text", getDocumentTypeDescription(ext), .document)
            } else if codeExtensions.contains(ext) {
                return ("代码", "chevron.left.forwardslash.chevron.right", getCodeTypeDescription(ext), .code)
            } else if archiveExtensions.contains(ext) {
                return ("压缩包", "archivebox", getArchiveTypeDescription(ext), .archive)
            } else if executableExtensions.contains(ext) {
                return ("应用程序", "app", getExecutableTypeDescription(ext), .executable)
            } else {
                return ("文件", "doc", "未知类型文件", .file)
            }
        }
        
        private static func getImageTypeDescription(_ ext: String) -> String {
            switch ext {
            case "jpg", "jpeg": return "JPEG 图片"
            case "png": return "PNG 图片"
            case "gif": return "GIF 动画"
            case "svg": return "SVG 矢量图"
            case "heic", "heif": return "HEIF 图片"
            case "psd": return "Photoshop 文档"
            case "ai": return "Illustrator 文件"
            case "raw", "cr2", "nef", "arw", "dng": return "RAW 原片"
            default: return "图片文件"
            }
        }
        
        private static func getVideoTypeDescription(_ ext: String) -> String {
            switch ext {
            case "mp4": return "MP4 视频"
            case "mov": return "QuickTime 视频"
            case "avi": return "AVI 视频"
            case "mkv": return "MKV 视频"
            default: return "视频文件"
            }
        }
        
        private static func getAudioTypeDescription(_ ext: String) -> String {
            switch ext {
            case "mp3": return "MP3 音频"
            case "wav": return "WAV 音频"
            case "flac": return "FLAC 无损音频"
            case "m4a": return "AAC 音频"
            default: return "音频文件"
            }
        }
        
        private static func getDocumentTypeDescription(_ ext: String) -> String {
            switch ext {
            case "pdf": return "PDF 文档"
            case "doc", "docx": return "Word 文档"
            case "xls", "xlsx": return "Excel 表格"
            case "ppt", "pptx": return "PowerPoint 演示"
            case "pages": return "Pages 文档"
            case "numbers": return "Numbers 表格"
            case "keynote": return "Keynote 演示"
            case "txt": return "文本文件"
            case "md": return "Markdown 文档"
            default: return "文档文件"
            }
        }
        
        private static func getCodeTypeDescription(_ ext: String) -> String {
            switch ext {
            case "swift": return "Swift 代码"
            case "py": return "Python 代码"
            case "js": return "JavaScript 代码"
            case "ts": return "TypeScript 代码"
            case "html": return "HTML 文件"
            case "css": return "CSS 样式"
            case "json": return "JSON 数据"
            case "xml": return "XML 文件"
            default: return "代码文件"
            }
        }
        
        private static func getArchiveTypeDescription(_ ext: String) -> String {
            switch ext {
            case "zip": return "ZIP 压缩包"
            case "rar": return "RAR 压缩包"
            case "7z": return "7-Zip 压缩包"
            case "dmg": return "磁盘映像"
            case "pkg": return "macOS 安装包"
            default: return "压缩文件"
            }
        }
        
        private static func getExecutableTypeDescription(_ ext: String) -> String {
            switch ext {
            case "app": return "macOS 应用"
            case "pkg": return "macOS 安装包"
            case "dmg": return "磁盘映像"
            case "exe": return "Windows 程序"
            default: return "可执行文件"
            }
        }
    }
    
    private func hasImageContent(_ pasteboard: NSPasteboard) -> Bool {
        // 先检查是否有真实的图片格式（非图标）
        let realImageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.bmp"),
            NSPasteboard.PasteboardType("public.gif"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("public.webp"),
            NSPasteboard.PasteboardType("public.avif")
        ]
        
        // 检查是否有真实图片数据
        let hasRealImageData = realImageTypes.contains { type in
            pasteboard.data(forType: type) != nil
        }
        
        if hasRealImageData {
            logger.debug("�️ 检测到真实图片数据")
            return true
        }
        
        // 如果同时存在文件URL和ICNS但没有真实图片数据，可能只是文件图标
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !fileURLs.isEmpty,
           pasteboard.data(forType: NSPasteboard.PasteboardType("com.apple.icns")) != nil {
            logger.debug("🔍 只有文件URL和ICNS图标，无真实图片数据，不认为是图片内容")
            return false
        }
        
        // 扩展的图片格式检测 - 支持更多常见和特殊格式
        let imageTypes: [NSPasteboard.PasteboardType] = [
            // 系统标准格式（排除可能的文件图标格式）
            .tiff, .png,
            
            // 通用图片格式
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.bmp"),
            NSPasteboard.PasteboardType("public.gif"),
            
            // 现代格式
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("public.webp"),
            NSPasteboard.PasteboardType("public.avif"),
            
            // 矢量和特殊格式
            NSPasteboard.PasteboardType("public.svg-image"),
            NSPasteboard.PasteboardType("com.adobe.photoshop-image"),
            
            // 浏览器特殊格式
            NSPasteboard.PasteboardType("image/png"),
            NSPasteboard.PasteboardType("image/jpeg"),
            NSPasteboard.PasteboardType("image/gif"),
            NSPasteboard.PasteboardType("image/webp"),
            NSPasteboard.PasteboardType("image/svg+xml"),
            
            // 其他可能的图片格式
            NSPasteboard.PasteboardType("public.jpeg-2000"),
            NSPasteboard.PasteboardType("public.camera-raw-image"),
            NSPasteboard.PasteboardType("org.webmproject.webp")
        ]
        
        logger.debug("🔍 检查剪贴板中的图片内容，可用类型: \(pasteboard.types ?? [])")
        
        // 检查是否有任何图片类型的数据
        for type in imageTypes {
            if pasteboard.data(forType: type) != nil {
                logger.debug("✅ 检测到图片类型: \(type.rawValue)")
                return true
            }
        }
        
        logger.debug("❌ 未检测到图片内容")
        return false
    }
    
    private func handleImageContentSync(_ pasteboard: NSPasteboard) {
        logger.info("🖼️ 开始处理图片内容")
        
        // 简化的图片格式检测，重点解决预览问题
        var imageData: Data?
        var detectedFormat = ""
        
        // 按照兼容性优先级尝试不同格式
        let formats: [(NSPasteboard.PasteboardType, String)] = [
            // 标准格式 - 最高兼容性
            (.png, "PNG"),
            (.tiff, "TIFF"),
            (NSPasteboard.PasteboardType("public.png"), "PNG"),
            (NSPasteboard.PasteboardType("public.jpeg"), "JPEG"),
            (NSPasteboard.PasteboardType("image/png"), "PNG"),
            (NSPasteboard.PasteboardType("image/jpeg"), "JPEG"),
            
            // 现代格式
            (NSPasteboard.PasteboardType("public.heic"), "HEIC"),
            (NSPasteboard.PasteboardType("public.heif"), "HEIF"),
            (NSPasteboard.PasteboardType("public.webp"), "WebP"),
            
            // 其他格式
            (NSPasteboard.PasteboardType("public.gif"), "GIF"),
            (NSPasteboard.PasteboardType("image/gif"), "GIF"),
            (NSPasteboard.PasteboardType("public.svg-image"), "SVG"),
            (.pdf, "PDF"),
            (NSPasteboard.PasteboardType("public.image"), "通用图片")
        ]
        
        // 尝试获取图片数据
        for (pasteboardType, formatName) in formats {
            if let data = pasteboard.data(forType: pasteboardType), data.count > 20 {
                imageData = data
                detectedFormat = formatName
                logger.info("🖼️ 成功获取 \(formatName) 格式图片: \(data.count) 字节")
                
                // 输出数据头部用于调试
                let headerBytes = data.prefix(16)
                let hexString = headerBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.debug("� 数据头部: \(hexString)")
                break
            }
        }
        
        // 如果标准格式都没找到，扫描所有包含 "image" 的类型
        if imageData == nil, let types = pasteboard.types {
            logger.debug("🔍 扫描自定义图片格式...")
            for type in types {
                let typeString = type.rawValue.lowercased()
                if (typeString.contains("image") || typeString.contains("photo")) &&
                   !typeString.contains("url") && !typeString.contains("path") {
                    if let data = pasteboard.data(forType: type), data.count > 20 {
                        imageData = data
                        detectedFormat = "自定义(\(type.rawValue))"
                        logger.info("🖼️ 找到自定义图片格式: \(type.rawValue), 大小: \(data.count) 字节")
                        break
                    }
                }
            }
        }
        
        guard let data = imageData else {
            logger.warning("❌ 无法获取任何格式的图片数据")
            return
        }
        
        // 生成图片描述 - 包含更多识别信息
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        let dataHash = String(data.hashValue)  // 添加数据哈希作为唯一标识
        let imageInfo = "图片 (\(detectedFormat), \(fileSize)) [\(dataHash.prefix(8))]"
        
        // 使用数据哈希进行更准确的重复检测
        let uniqueKey = "img_\(detectedFormat)_\(data.count)_\(dataHash)"
        if isDuplicateContent(uniqueKey, type: ClipboardItemType.image) {
            logger.debug("⏭️ 跳过重复图片内容（数据哈希匹配）")
            return
        }
        
        // 直接保存原始数据，让 ImagePreviewView 处理解码
        addClipboardItemWithData(content: imageInfo, type: ClipboardItemType.image, data: data)
        logger.info("✅ 图片数据已添加: \(imageInfo)")
        
        // 立即通知UI更新
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardItemsChanged"), object: nil)
        }
    }
    
    // 处理 SVG 图片
    private func handleSVGImage(data: Data, format: String) {
        let imageInfo = "SVG 矢量图 (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        if !isDuplicateContent(imageInfo, type: .image) {
            addClipboardItemWithData(content: imageInfo, type: .image, data: data)
            logger.info("✅ SVG 图片已添加: \(imageInfo)")
        } else {
            logger.debug("⏭️ 跳过重复 SVG 内容")
        }
    }
    
    // 处理 PDF 图片
    private func handlePDFImage(data: Data, format: String) {
        // 尝试将 PDF 转换为图片预览
        if let pdfDocument = PDFDocument(data: data),
           let firstPage = pdfDocument.page(at: 0) {
            let pageRect = firstPage.bounds(for: .mediaBox)
            
            // 创建图像表示
            let image = NSImage(size: pageRect.size)
            image.lockFocus()
            
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.translateBy(x: 0, y: pageRect.size.height)
                context.scaleBy(x: 1.0, y: -1.0)
                firstPage.draw(with: .mediaBox, to: context)
                context.restoreGState()
            }
            
            image.unlockFocus()
            
            if let imageData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: imageData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                let imageInfo = "PDF 图片 (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
                if !isDuplicateContent(imageInfo, type: .image) {
                    addClipboardItemWithData(content: imageInfo, type: .image, data: pngData)
                    logger.info("✅ PDF 图片已添加: \(imageInfo)")
                } else {
                    logger.debug("⏭️ 跳过重复 PDF 内容")
                }
                return
            }
        }
        
        // 如果无法处理，作为文档处理
        let imageInfo = "PDF 文档 (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        if !isDuplicateContent(imageInfo, type: .document) {
            addClipboardItemWithData(content: imageInfo, type: .document, data: data)
            logger.info("✅ PDF 文档已添加: \(imageInfo)")
        }
    }
    
    // 处理位图格式图片
    private func handleBitmapImage(data: Data, format: String, originalType: NSPasteboard.PasteboardType?) {
        logger.info("🖼️ 处理位图图片: \(format), 数据大小: \(data.count) 字节")
        
        // 使用缓存验证避免重复处理
        if !isValidImageDataCached(data) {
            logger.warning("图片数据验证失败，跳过处理")
            return
        }
        
        // 放宽图片验证，先尝试直接创建 NSImage
        var nsImage: NSImage?
        var processedData = data
        
        // 首先尝试直接解析
        nsImage = NSImage(data: data)
        logger.debug("🖼️ 直接解析结果: \(nsImage != nil ? "成功" : "失败")")
        
        // 如果直接解析失败，尝试数据修复
        if nsImage == nil {
            logger.debug("🔧 尝试修复图片数据...")
            if let repairedData = attemptDataRepair(data, format: format) {
                nsImage = NSImage(data: repairedData)
                if nsImage != nil {
                    processedData = repairedData
                    logger.info("🔧 数据修复成功")
                } else {
                    logger.warning("🔧 数据修复后仍无法解析")
                }
            }
        }
        
        // 如果还是失败，尝试不同的解码方式
        if nsImage == nil {
            logger.debug("🔧 尝试其他解码方式...")
            
            // 尝试 CGImage 方式
            if let cgImageSource = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) {
                nsImage = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
                logger.info("🔧 CGImage 解码成功")
            }
        }
        
        // 如果仍然失败，但数据看起来像图片，就保存原始数据并提供详细信息
        if nsImage == nil {
            if isValidImageDataHeader(data.prefix(16), format: format) {
                logger.warning("⚠️ 无法解析图片但数据头部有效，保存原始数据")
                
                // 生成详细的调试信息
                let headerBytes = data.prefix(16)
                let hexString = headerBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.debug("📊 数据头部: \(hexString)")
                
                // 检测可能的格式
                let detectedFormat = detectImageFormatFromHeader(data)
                logger.info("🔍 检测到的格式: \(detectedFormat)")
                
                let imageInfo = "图片数据 (\(detectedFormat), \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
                if !isDuplicateContent(imageInfo, type: .image) {
                    addClipboardItemWithData(content: imageInfo, type: .image, data: data)
                    logger.info("✅ 原始图片数据已添加: \(imageInfo)")
                }
                return
            } else {
                logger.error("❌ 无法解析图片数据且数据头部无效")
                
                // 即使无法解析，也要提供调试信息
                let headerBytes = data.prefix(16)
                let hexString = headerBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.debug("📊 无效数据头部: \(hexString)")
                
                // 作为未知数据保存，让用户知道有内容但无法预览
                let imageInfo = "无法识别的图片数据 (\(format), \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
                if !isDuplicateContent(imageInfo, type: .image) {
                    addClipboardItemWithData(content: imageInfo, type: .image, data: data)
                    logger.info("⚠️ 无法识别的图片数据已添加: \(imageInfo)")
                }
                return
            }
        }
        
        // 验证图片尺寸
        guard let imageSize = nsImage?.size,
              imageSize.width > 0 && imageSize.height > 0 else {
            logger.warning("❌ 图片尺寸无效: \(nsImage?.size ?? CGSize.zero)")
            return
        }
        
        // 生成详细的图片描述
        let pixelSize = "\(Int(imageSize.width))×\(Int(imageSize.height))"
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(processedData.count), countStyle: .file)
        let imageInfo = "图片 (\(pixelSize), \(format), \(fileSize))"
        
        if !isDuplicateContent(imageInfo, type: .image) {
            // 预处理图片数据，确保稳定性
            let stableImageData = preprocessImageData(processedData, format: format)
            
            // 最终验证
            if NSImage(data: stableImageData) != nil {
                addClipboardItemWithData(content: imageInfo, type: .image, data: stableImageData)
                logger.info("✅ 位图图片已添加: \(imageInfo)")
            } else {
                // 如果预处理失败，使用原始数据
                addClipboardItemWithData(content: imageInfo, type: .image, data: processedData)
                logger.info("✅ 原始位图数据已添加: \(imageInfo)")
            }
        } else {
            logger.debug("⏭️ 跳过重复图片内容")
        }
    }
    
    // 从数据头部检测图片格式
    private func detectImageFormatFromHeader(_ data: Data) -> String {
        guard data.count >= 4 else { return "未知格式" }
        
        let bytes = Array(data.prefix(16))
        
        // PNG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "PNG"
        }
        
        // JPEG
        if bytes.starts(with: [0xFF, 0xD8]) {
            return "JPEG"
        }
        
        // GIF
        if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return "GIF"
        }
        
        // BMP
        if bytes.starts(with: [0x42, 0x4D]) {
            return "BMP"
        }
        
        // TIFF
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || 
           bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "TIFF"
        }
        
        // WebP
        if data.count >= 12 &&
           bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) &&
           bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return "WebP"
        }
        
        // PDF
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return "PDF"
        }
        
        // HEIF/HEIC
        if data.count >= 12 &&
           bytes[4...7] == [0x66, 0x74, 0x79, 0x70] {
            if let typeString = String(data: data.subdata(in: 8..<12), encoding: .ascii) {
                if typeString.contains("heic") || typeString.contains("heix") {
                    return "HEIC"
                } else if typeString.contains("heif") || typeString.contains("mif1") {
                    return "HEIF"
                } else if typeString.contains("avif") {
                    return "AVIF"
                }
            }
            return "HEIF系列"
        }
        
        // SVG
        if let headerString = String(data: data.prefix(100), encoding: .utf8) {
            if headerString.contains("<svg") || headerString.contains("<?xml") {
                return "SVG"
            }
        }
        
        return "未知格式"
    }
    
    // 验证图片数据头部 - 更宽松的验证
    private func isValidImageDataHeader(_ header: Data, format: String) -> Bool {
        guard header.count >= 4 else { return false }
        
        let bytes = Array(header)
        let formatUpper = format.uppercased()
        
        switch formatUpper {
        case "PNG":
            return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47])
        case "JPEG", "JPG":
            return bytes.starts(with: [0xFF, 0xD8, 0xFF]) || bytes.starts(with: [0xFF, 0xD8])
        case "GIF":
            return bytes.starts(with: [0x47, 0x49, 0x46]) || 
                   String(data: header.prefix(6), encoding: .ascii)?.hasPrefix("GIF") == true
        case "TIFF", "TIF":
            return bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || // Little endian
                   bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A])   // Big endian
        case "BMP":
            return bytes.starts(with: [0x42, 0x4D])
        case "WEBP":
            return header.count >= 12 && 
                   bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) &&
                   bytes[8...11] == [0x57, 0x45, 0x42, 0x50]
        case "HEIC", "HEIF":
            // HEIF/HEIC 有复杂的头部结构，进行基本检查
            return header.count >= 12 &&
                   (bytes[4...7] == [0x66, 0x74, 0x79, 0x70] || // "ftyp"
                    String(data: header.subdata(in: 4..<8), encoding: .ascii) == "ftyp")
        case "PDF":
            return bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) || // "%PDF"
                   String(data: header.prefix(4), encoding: .ascii) == "%PDF"
        case "SVG":
            let headerString = String(data: header, encoding: .utf8) ?? ""
            return headerString.contains("<svg") || headerString.contains("<?xml")
        case "AVIF":
            return header.count >= 12 &&
                   bytes[4...7] == [0x66, 0x74, 0x79, 0x70] && // "ftyp"
                   bytes[8...11] == [0x61, 0x76, 0x69, 0x66] // "avif"
        case "通用图片", "自定义图片格式":
            // 对于通用或自定义格式，尝试多种常见头部
            return isCommonImageFormat(bytes)
        default:
            // 对于未知格式，进行通用检查
            return isCommonImageFormat(bytes)
        }
    }
    
    // 检查是否为常见图片格式
    private func isCommonImageFormat(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }
        
        // PNG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        
        // JPEG
        if bytes.starts(with: [0xFF, 0xD8]) { return true }
        
        // GIF
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return true }
        
        // BMP
        if bytes.starts(with: [0x42, 0x4D]) { return true }
        
        // TIFF
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || 
           bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return true }
        
        // WebP
        if bytes.count >= 12 &&
           bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) &&
           bytes[8...11] == [0x57, 0x45, 0x42, 0x50] { return true }
        
        // PDF
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return true }
        
        // ICO
        if bytes.starts(with: [0x00, 0x00, 0x01, 0x00]) { return true }
        
        return false
    }
    
    // 尝试修复损坏的图片数据 - 增强版
    private func attemptDataRepair(_ data: Data, format: String) -> Data? {
        let formatUpper = format.uppercased()
        let bytes = Array(data)
        
        // 对于 JPEG，尝试修复头部
        if formatUpper.contains("JPEG") || formatUpper.contains("JPG") {
            // 如果不是以 FF D8 开头，尝试找到正确的开始位置
            if !bytes.starts(with: [0xFF, 0xD8]) {
                if let startIndex = findJPEGStart(in: bytes) {
                    let repairedData = Data(bytes.dropFirst(startIndex))
                    logger.info("🔧 修复了 JPEG 数据开头，移除了 \(startIndex) 字节")
                    return repairedData
                }
            }
            
            // 尝试添加标准 JPEG 头部（如果数据看起来像是丢失了头部）
            if bytes.count > 100 && bytes.contains(0xFF) {
                let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
                var repairedBytes = jpegHeader
                repairedBytes.append(contentsOf: bytes)
                logger.info("🔧 尝试为 JPEG 添加标准头部")
                return Data(repairedBytes)
            }
        }
        
        // 对于 PNG，尝试修复头部
        if formatUpper == "PNG" {
            if !bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                if let startIndex = findPNGStart(in: bytes) {
                    let repairedData = Data(bytes.dropFirst(startIndex))
                    logger.info("🔧 修复了 PNG 数据开头，移除了 \(startIndex) 字节")
                    return repairedData
                }
            }
        }
        
        // 对于 GIF，尝试修复头部
        if formatUpper == "GIF" {
            if !bytes.starts(with: [0x47, 0x49, 0x46]) {
                if let startIndex = findGIFStart(in: bytes) {
                    let repairedData = Data(bytes.dropFirst(startIndex))
                    logger.info("🔧 修复了 GIF 数据开头，移除了 \(startIndex) 字节")
                    return repairedData
                }
            }
        }
        
        // 通用修复：尝试移除前面的无效字节
        if bytes.count > 20 {
            for i in 1..<min(100, bytes.count - 10) {
                let testData = Data(bytes.dropFirst(i))
                if NSImage(data: testData) != nil {
                    logger.info("🔧 通用修复成功，移除了 \(i) 字节")
                    return testData
                }
            }
        }
        
        return nil
    }
    
    // 查找 JPEG 开始位置
    private func findJPEGStart(in bytes: [UInt8]) -> Int? {
        for i in 0..<min(bytes.count - 1, 1000) {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xD8 {
                return i
            }
        }
        return nil
    }
    
    // 查找 PNG 开始位置
    private func findPNGStart(in bytes: [UInt8]) -> Int? {
        for i in 0..<min(bytes.count - 3, 1000) {
            if bytes[i] == 0x89 && bytes[i + 1] == 0x50 && 
               bytes[i + 2] == 0x4E && bytes[i + 3] == 0x47 {
                return i
            }
        }
        return nil
    }
    
    // 查找 GIF 开始位置
    private func findGIFStart(in bytes: [UInt8]) -> Int? {
        for i in 0..<min(bytes.count - 2, 1000) {
            if bytes[i] == 0x47 && bytes[i + 1] == 0x49 && bytes[i + 2] == 0x46 {
                return i
            }
        }
        return nil
    }
    
    // 预处理图片数据，确保数据稳定性
    private func preprocessImageData(_ data: Data, format: String) -> Data {
        // 对于常见的位图格式，确保数据完整性
        guard format != "SVG" else { return data }
        
        // 验证图片数据的完整性
        guard let nsImage = NSImage(data: data),
              nsImage.isValid,
              nsImage.size.width > 0,
              nsImage.size.height > 0 else {
            #if DEBUG
            logger.warning("图片数据验证失败，返回原始数据")
            #endif
            return data
        }
        
        // 对于 TIFF 格式，转换为更稳定的 PNG 格式
        if format == "TIFF" {
            if let tiffData = nsImage.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                #if DEBUG
                logger.info("TIFF 已转换为 PNG 格式")
                #endif
                return pngData
            }
        }
        
        // 对于过大的图片，进行适度压缩但保持质量
        if data.count > 5 * 1024 * 1024 { // 5MB
            if let optimizedData = optimizeImageForStability(nsImage, originalData: data) {
                #if DEBUG
                logger.info("大图片已优化处理")
                #endif
                return optimizedData
            }
        }
        
        return data
    }
    
    // 专门用于稳定性的图片优化
    private func optimizeImageForStability(_ image: NSImage, originalData: Data) -> Data? {
        // 计算合适的尺寸，不要过度压缩
        let maxDimension: CGFloat = 1200 // 适中的尺寸限制
        let currentSize = image.size
        
        // 如果图片已经很小，直接返回原数据
        if currentSize.width <= maxDimension && currentSize.height <= maxDimension {
            return originalData
        }
        
        // 计算新尺寸，保持宽高比
        let scale = min(maxDimension / currentSize.width, maxDimension / currentSize.height)
        let newSize = NSSize(width: currentSize.width * scale, height: currentSize.height * scale)
        
        // 创建新的图片
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), 
                  from: NSRect(origin: .zero, size: currentSize), 
                  operation: .copy, 
                  fraction: 1.0)
        newImage.unlockFocus()
        
        // 转换为 PNG 格式，确保质量和兼容性
        if let tiffData = newImage.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            return pngData
        }
        
        return originalData
    }
    
    private func handleImageFileContent(_ fileURLs: [URL]) {
        logger.info("🖼️ 处理图片文件内容: \(fileURLs.count) 个图片文件")
        
        // 验证图片文件是否存在
        let validImageFiles = fileURLs.filter { url in
            let exists = FileManager.default.fileExists(atPath: url.path)
            if !exists {
                logger.warning("⚠️ 图片文件不存在: \(url.path)")
            }
            return exists
        }
        
        guard !validImageFiles.isEmpty else {
            logger.error("❌ 没有有效的图片文件")
            return
        }
        
        // 处理第一个图片文件（通常只有一个）
        let imageFile = validImageFiles.first!
        logger.info("📁 加载图片文件: \(imageFile.path)")
        
        do {
            // 读取原始图片文件数据
            let imageData = try Data(contentsOf: imageFile)
            logger.info("✅ 成功读取图片文件，大小: \(imageData.count) 字节")
            
            // 验证是否为有效图片
            if NSImage(data: imageData) != nil {
                logger.info("✅ 图片文件验证成功，添加到剪贴板历史")
                
                // 生成合适的预览文本
                let fileName = imageFile.lastPathComponent
                let fileSize = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)
                let previewText = "图片文件: \(fileName) (\(fileSize))"
                
                // 创建图片项目，使用原始图片数据
                if !isDuplicateContent(previewText, type: .image) {
                    addClipboardItem(content: previewText, type: .image, data: imageData)
                    logger.info("✅ 图片文件已添加到剪贴板历史")
                } else {
                    logger.debug("⏭️ 跳过重复的图片文件")
                }
            } else {
                logger.error("❌ 图片文件格式无效或损坏: \(imageFile.path)")
                // 仍然作为文件处理
                handleFileContent(validImageFiles)
            }
        } catch {
            logger.error("❌ 读取图片文件失败: \(error.localizedDescription)")
            // 降级为文件处理
            handleFileContent(validImageFiles)
        }
    }
    
    private func handleFileContent(_ fileURLs: [URL]) {
        logger.info("🗂️ 处理文件内容: \(fileURLs.count) 个文件")
        
        // 验证所有文件是否存在
        let validFiles = fileURLs.filter { url in
            let exists = FileManager.default.fileExists(atPath: url.path)
            if !exists {
                #if DEBUG
                logger.warning("文件不存在: \(url.path)")
                #endif
            }
            return exists
        }
        
        guard !validFiles.isEmpty else {
            logger.warning("没有有效的文件")
            return
        }
        
        // 使用新的文件类型分类器对文件进行分类
        var categorizedFiles: [String: [URL]] = [:]
        var fileInfos: [[String: Any]] = []
        
        for url in validFiles {
            let pathExtension = url.pathExtension.lowercased()
            let fileClassification = FileTypeClassifier.classifyFileType(fileExtension: pathExtension)
            let category = fileClassification.category
            
            // 按类别分组
            if categorizedFiles[category] == nil {
                categorizedFiles[category] = []
            }
            categorizedFiles[category]?.append(url)
            
            // 创建详细的文件信息
            var fileInfo: [String: Any] = [
                "name": url.lastPathComponent,
                "path": url.path,
                "type": url.pathExtension,
                "url": url.absoluteString,
                "category": category,
                "icon": fileClassification.icon,
                "description": fileClassification.description,
                "itemType": fileClassification.itemType.rawValue
            ]
            
            // 获取文件大小
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int64 {
                fileInfo["size"] = fileSize
                fileInfo["sizeFormatted"] = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
            
            // 获取文件创建和修改时间
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                if let creationDate = attributes[.creationDate] as? Date {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    fileInfo["creationDate"] = formatter.string(from: creationDate)
                }
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    fileInfo["modificationDate"] = formatter.string(from: modificationDate)
                }
            }
            
            fileInfos.append(fileInfo)
        }
        
        // 生成描述性内容
        let totalFiles = validFiles.count
        
        if totalFiles == 1 {
            // 单个文件，使用该文件的具体类型
            let singleFile = validFiles.first!
            let classification = FileTypeClassifier.classifyFileType(fileExtension: singleFile.pathExtension.lowercased())
            let contentTitle = "\(classification.category): \(singleFile.lastPathComponent)"
            
            if !isDuplicateContent(contentTitle, type: classification.itemType) {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: fileInfos, options: .prettyPrinted)
                    addClipboardItem(content: contentTitle, type: classification.itemType, data: jsonData)
                    logger.info("文件内容已添加: \(contentTitle)")
                } catch {
                    let pathsText = validFiles.map { $0.path }.joined(separator: "\n")
                    addClipboardItem(content: contentTitle, type: classification.itemType, data: pathsText.data(using: .utf8))
                    logger.info("文件内容已添加（简化版）: \(contentTitle)")
                }
            } else {
                logger.debug("跳过重复文件内容")
            }
        } else {
            // 多个文件，检查是否为同一类型
            let fileTypes = Set(validFiles.map { url in
                FileTypeClassifier.classifyFileType(fileExtension: url.pathExtension.lowercased()).itemType
            })
            
            var contentComponents: [String] = []
            
            // 按类别统计并添加到描述中
            let sortedCategories = categorizedFiles.keys.sorted()
            for category in sortedCategories {
                guard let filesInCategory = categorizedFiles[category] else { continue }
                let count = filesInCategory.count
                let fileNames = filesInCategory.prefix(3).map { $0.lastPathComponent }.joined(separator: ", ")
                
                if count <= 3 {
                    contentComponents.append("\(category): \(fileNames)")
                } else {
                    contentComponents.append("\(category): \(fileNames) 等\(count)个")
                }
            }
            
            let fileDescription = contentComponents.joined(separator: "; ")
            let contentTitle = "文件 (\(totalFiles)个): \(fileDescription)"
            
            // 如果所有文件都是同一类型，使用该类型；否则使用通用的 .file 类型
            let itemType: ClipboardItemType = fileTypes.count == 1 ? fileTypes.first! : .file
            
            if !isDuplicateContent(contentTitle, type: itemType) {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: fileInfos, options: .prettyPrinted)
                    addClipboardItem(content: contentTitle, type: itemType, data: jsonData)
                    logger.info("文件内容已添加: \(contentTitle)")
                } catch {
                    logger.warning("JSON序列化失败，使用简化版本: \(error.localizedDescription)")
                    let simplifiedFileInfos = fileInfos.map { info -> [String: String] in
                        return [
                            "name": info["name"] as? String ?? "",
                            "path": info["path"] as? String ?? "",
                            "category": info["category"] as? String ?? "文件"
                        ]
                    }
                    
                    if let simpleJsonData = try? JSONSerialization.data(withJSONObject: simplifiedFileInfos, options: []) {
                        addClipboardItem(content: contentTitle, type: itemType, data: simpleJsonData)
                    } else {
                        // 最后的备用方案
                        let pathsText = validFiles.map { $0.path }.joined(separator: "\n")
                        addClipboardItem(content: contentTitle, type: itemType, data: pathsText.data(using: .utf8))
                    }
                    logger.info("文件内容已添加（简化版）: \(contentTitle)")
                }
            } else {
                logger.debug("跳过重复文件内容")
            }
        }
    }
    
    // MARK: - 图片验证优化
    
    private func isValidImageDataCached(_ data: Data) -> Bool {
        let dataHash = String(data.hashValue)
        let cacheKey = NSString(string: dataHash)
        
        // 检查缓存
        if let cachedResult = imageValidationCache.object(forKey: cacheKey) {
            return cachedResult.boolValue
        }
        
        // 快速头部验证
        let isValid = isValidImageDataQuick(data)
        
        // 缓存结果
        imageValidationCache.setObject(NSNumber(value: isValid), forKey: cacheKey)
        
        return isValid
    }
    
    private func isValidImageDataQuick(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        
        let bytes = Array(data.prefix(16))
        
        // 快速检查常见格式
        return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) || // PNG
               bytes.starts(with: [0xFF, 0xD8]) || // JPEG
               bytes.starts(with: [0x47, 0x49, 0x46]) || // GIF
               bytes.starts(with: [0x42, 0x4D]) || // BMP
               (bytes.count >= 12 && bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && 
                bytes[8...11] == [0x57, 0x45, 0x42, 0x50]) // WebP
    }
    
    // MARK: - 智能去重和内容过滤
    
    private func isDuplicateContent(_ content: String, type: ClipboardItemType) -> Bool {
        // 检查内容是否过短或无效
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.count < 1 {
            return true
        }
        
        // 检查是否为最近添加的重复内容（避免连续重复）
        if let lastItem = clipboardItems.first {
            if lastItem.content == content && lastItem.type == type {
                logger.debug("跳过重复内容（最新项匹配）")
                return true
            }
        }
        
        // 检查前5个项目是否有重复（更全面的重复检测）
        let recentItems = Array(clipboardItems.prefix(5))
        for item in recentItems {
            if item.content == content && item.type == type {
                logger.debug("跳过重复内容（历史项匹配）")
                return true
            }
        }
        
        // 检查是否为系统内容
        let systemPrefixes = ["com.apple.", "system:", "internal:"]
        if systemPrefixes.contains(where: content.lowercased().hasPrefix) {
            logger.debug("跳过系统内容")
            return true
        }
        
        return false
    }
    
    // MARK: - 图片优化处理
    
    private func optimizeImageData(_ image: NSImage, originalData: Data) -> Data {
        let targetSize = CGFloat(settingsManager.maxImageSize)
        let compressionQuality = settingsManager.compressionQuality
        
        // 如果原始图片已经合适，直接返回
        if image.size.width <= targetSize && image.size.height <= targetSize {
            return originalData
        }
        
        // 计算新尺寸
        let aspectRatio = image.size.width / image.size.height
        var newSize: NSSize
        
        if aspectRatio > 1 {
            newSize = NSSize(width: targetSize, height: targetSize / aspectRatio)
        } else {
            newSize = NSSize(width: targetSize * aspectRatio, height: targetSize)
        }
        
        // 创建压缩后的图片
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resizedImage.unlockFocus()
        
        // 转换为 JPEG 格式以减小文件大小
        if let tiffData = resizedImage.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]) {
            
            let originalSize = ByteCountFormatter.string(fromByteCount: Int64(originalData.count), countStyle: .file)
            let newSize = ByteCountFormatter.string(fromByteCount: Int64(jpegData.count), countStyle: .file)
            logger.info("图片已优化: \(originalSize) -> \(newSize)")
            
            return jpegData
        }
        
        return originalData
    }
    
    // MARK: - 添加剪贴板项目的方法
    
    private func addClipboardItemWithData(content: String, type: ClipboardItemType, data: Data) {
        addClipboardItem(content: content, type: type, data: data)
    }
    
    private func handleFileContentSync(_ pasteboard: NSPasteboard) -> Bool {
        guard let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty else {
            return false
        }
        
        // 验证文件存在性
        let validFiles = fileURLs.filter { url in
            FileManager.default.fileExists(atPath: url.path)
        }
        
        guard !validFiles.isEmpty else {
            return false
        }
        
        // 使用新的文件类型分类器
        var categorizedFiles: [String: [URL]] = [:]
        var fileInfos: [[String: Any]] = []
        
        for url in validFiles {
            let pathExtension = url.pathExtension.lowercased()
            let fileClassification = FileTypeClassifier.classifyFileType(fileExtension: pathExtension)
            let category = fileClassification.category
            
            // 按类别分组
            if categorizedFiles[category] == nil {
                categorizedFiles[category] = []
            }
            categorizedFiles[category]?.append(url)
            
            // 创建文件信息
            let fileInfo: [String: Any] = [
                "name": url.lastPathComponent,
                "path": url.path,
                "category": category,
                "icon": fileClassification.icon,
                "description": fileClassification.description,
                "itemType": fileClassification.itemType.rawValue
            ]
            fileInfos.append(fileInfo)
        }
        
        // 生成描述
        let totalFiles = validFiles.count
        let contentTitle: String
        let itemType: ClipboardItemType
        
        if totalFiles == 1 {
            let singleFile = validFiles.first!
            let classification = FileTypeClassifier.classifyFileType(fileExtension: singleFile.pathExtension.lowercased())
            contentTitle = "\(classification.category): \(singleFile.lastPathComponent)"
            itemType = classification.itemType
        } else {
            let fileTypes = Set(validFiles.map { url in
                FileTypeClassifier.classifyFileType(fileExtension: url.pathExtension.lowercased()).itemType
            })
            
            let categories = categorizedFiles.keys.sorted()
            let categoryDescriptions: [String] = categories.compactMap { category in
                guard let files = categorizedFiles[category] else { return nil }
                let count = files.count
                return "\(category)(\(count))"
            }
            contentTitle = "文件 (\(totalFiles)个): \(categoryDescriptions.joined(separator: ", "))"
            
            // 如果所有文件都是同一类型，使用该类型；否则使用通用的 .file 类型
            itemType = fileTypes.count == 1 ? (fileTypes.first ?? .file) : .file
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: fileInfos)
            addClipboardItem(content: contentTitle, type: itemType, data: jsonData)
            print("✅ 文件内容已立即添加: \(contentTitle)")
            return true
        } catch {
            // 备用方案：只保存文件路径
            let filePaths = validFiles.map { $0.path }.joined(separator: "\n")
            addClipboardItem(content: contentTitle, type: itemType, data: filePaths.data(using: .utf8))
            print("✅ 文件内容已添加（简化版）: \(contentTitle)")
            return true
        }
    }
    
    @MainActor
    private func handleImageContent(_ pasteboard: NSPasteboard) async {
        var imageData: Data?
        var hasImage = false
        
        // 按优先级检查图片格式
        let imageTypes: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "PNG"),
            (.tiff, "TIFF"),
            (NSPasteboard.PasteboardType("public.jpeg"), "JPEG")
        ]
        
        for (type, format) in imageTypes {
            if let data = pasteboard.data(forType: type) {
                imageData = data
                hasImage = true
                print("检测到 \(format) 格式图片，大小: \(data.count / 1024)KB")
                break
            }
        }
        
        if hasImage, let imageData = imageData {
            // 快速检查图片是否过大
            let maxSizeBytes = 50 * 1024 * 1024 // 50MB
            guard imageData.count < maxSizeBytes else {
                print("图片过大 (\(imageData.count / 1024 / 1024)MB)，已跳过")
                return
            }
            
            do {
                let optimizedData = try await optimizeImageDataAsync(imageData)
                addClipboardItem(content: "Image", type: .image, data: optimizedData)
            } catch {
                print("图片处理失败: \(error.localizedDescription)")
                // 使用原始数据作为备用
                addClipboardItem(content: "Image", type: .image, data: imageData)
            }
        }
    }
    
    private func addClipboardItem(content: String, type: ClipboardItemType, data: Data? = nil) {
        // 验证输入数据
        guard !content.isEmpty else {
            logger.debug("尝试添加空内容，已忽略")
            return
        }
        
        // 限制内容长度以防止内存问题
        let maxContentLength = 10000
        let truncatedContent = content.count > maxContentLength ? String(content.prefix(maxContentLength)) + "..." : content
        
        // 对于图片类型，使用数据哈希进行重复检测
        if type == .image, let imageData = data {
            let newDataHash = String(imageData.hashValue)
            
            // 检查是否存在相同的图片数据
            if let existingIndex = clipboardItems.firstIndex(where: { item in
                guard item.type == .image, let existingData = item.data else { return false }
                return String(existingData.hashValue) == newDataHash
            }) {
                let existingItem = clipboardItems[existingIndex]
                let timeSinceCreation = Date().timeIntervalSince(existingItem.timestamp)
                
                if timeSinceCreation < 30 { // 30秒内相同图片数据不重复添加
                    logger.debug("⏭️ 跳过重复图片数据（\(timeSinceCreation)秒内已存在，Hash: \(newDataHash)）")
                    return
                }
                
                // 移除旧的图片项目
                clipboardItems.remove(at: existingIndex)
                logger.debug("🔄 更新现有图片项目 (Hash: \(newDataHash))")
            }
        } else {
            // 对于非图片类型，使用内容文本进行重复检测
            if let existingIndex = clipboardItems.firstIndex(where: { 
                $0.content == truncatedContent && $0.type == type 
            }) {
                let existingItem = clipboardItems[existingIndex]
                let timeSinceCreation = Date().timeIntervalSince(existingItem.timestamp)
                
                if timeSinceCreation < 300 { // 5分钟内相同内容不重复添加
                    logger.debug("⏭️ 跳过重复内容（\(timeSinceCreation)秒内已存在）")
                    return
                }
                
                // 移除旧的项目
                clipboardItems.remove(at: existingIndex)
            }
        }
        
        // 创建新项目
        let newItem = ClipboardItem(
            id: UUID(),
            content: truncatedContent,
            type: type,
            timestamp: Date(),
            data: data
        )
        
        // 检查该项目是否已经在收藏列表中，并设置正确的收藏状态
        let isFavorite = FavoriteManager.shared.isFavorite(newItem)
        let item = ClipboardItem(
            id: newItem.id,
            content: newItem.content,
            type: newItem.type,
            timestamp: newItem.timestamp,
            data: newItem.data,
            filePath: newItem.filePath,
            isFavorite: isFavorite
        )
        
        // 添加到顶部
        clipboardItems.insert(item, at: 0)
        
        // 生成日志信息
        if type == .image, let imageData = data {
            let dataHash = String(imageData.hashValue)
            print("✅ 添加新图片项目: \(type.displayName), 数据大小: \(imageData.count) 字节, Hash: \(dataHash)")
        } else {
            print("✅ 添加新项目: \(type.displayName)")
        }
        
        // 限制历史记录数量（使用设置管理器），但保护收藏项目
        if clipboardItems.count > settingsManager.maxItems {
            // 分离收藏和非收藏项目
            let favoriteItems = clipboardItems.filter { FavoriteManager.shared.isFavorite($0) }
            let nonFavoriteItems = clipboardItems.filter { !FavoriteManager.shared.isFavorite($0) }
            
            // 计算需要保留的非收藏项目数量
            let maxNonFavoriteItems = max(0, settingsManager.maxItems - favoriteItems.count)
            
            if nonFavoriteItems.count > maxNonFavoriteItems {
                let removedCount = nonFavoriteItems.count - maxNonFavoriteItems
                let itemsToKeep = Array(nonFavoriteItems.prefix(maxNonFavoriteItems))
                
                // 重新组合列表：收藏项目 + 保留的非收藏项目
                clipboardItems = favoriteItems + itemsToKeep
                print("已清理 \(removedCount) 个旧项目，保留 \(favoriteItems.count) 个收藏项目")
            }
        }
        
        // 异步保存到持久化存储，避免阻塞UI
        Task.detached(priority: .background) { [weak self] in
            guard let self = self, let item = self.clipboardItems.first else { return }
            self.store.saveItem(item)
        }
        
        // 立即发送剪贴板变化通知，确保UI即时更新
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardItemsChanged"), object: nil)
        }
        
        // 发送用户通知
        if let firstItem = clipboardItems.first {
            logger.info("📢 准备发送通知，内容: \(String(firstItem.content.prefix(20)))...")
            
            // 检查通知设置
            if SettingsManager.shared.enableNotifications {
                logger.info("✅ 通知已启用，发送通知")
                
                // 增加未读计数
                unreadCount += 1
                
                // 更新 badge 数量
                NotificationManager.shared.setBadgeCount(unreadCount)
                
                // 直接调用 NotificationManager 发送通知
                NotificationManager.shared.showClipboardNotification(content: firstItem.content)
            } else {
                logger.info("❌ 通知已禁用，跳过发送和计数")
                // 通知禁用时不增加未读计数，也不显示badge
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        logger.info("🔄 准备复制项目到剪贴板: \(item.type.displayName)")
        
        // 设置标志位防止重复监控
        isPerformingCopyOperation = true
        copyOperationTimestamp = Date().timeIntervalSince1970
        
        let pasteboard = NSPasteboard.general
        
        pasteboard.clearContents()
        
        // 延迟重置标志位
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isPerformingCopyOperation = false
        }
        
        do {
            switch item.type {
            case .text:
                try copyTextToClipboard(item, pasteboard: pasteboard)
                
            case .image:
                try copyImageToClipboard(item, pasteboard: pasteboard)
                
            case .file, .video, .audio, .document, .code, .archive, .executable:
                // 所有文件类型都使用文件复制逻辑
                try copyFileToClipboard(item, pasteboard: pasteboard)
            }
        } catch {
            logger.error("复制失败: \(error.localizedDescription)")
            FeedbackManager.shared.showError("复制失败: \(error.localizedDescription)")
        }
    }
    
    private func copyTextToClipboard(_ item: ClipboardItem, pasteboard: NSPasteboard) throws {
        // 验证文本内容
        guard !item.content.isEmpty else {
            throw ClipboardError.dataCorrupted
        }
        pasteboard.setString(item.content, forType: .string)
        logger.info("文本已复制到剪贴板")
    }
    
    private func copyImageToClipboard(_ item: ClipboardItem, pasteboard: NSPasteboard) throws {
        // 优先使用内存中的数据，如果没有则从磁盘加载
        var imageData = item.data
        
        // 如果内存中没有数据，尝试从磁盘加载
        if imageData == nil || (imageData?.isEmpty == true) {
            logger.info("🔄 图片数据为空，尝试从磁盘加载: \(item.filePath ?? "无路径")")
            
            if let filePath = item.filePath {
                let url = URL(fileURLWithPath: filePath)
                do {
                    imageData = try Data(contentsOf: url)
                    logger.info("✅ 成功从磁盘加载图片数据，大小: \(imageData?.count ?? 0) 字节")
                } catch {
                    logger.error("❌ 从磁盘加载图片失败: \(error.localizedDescription)")
                    throw ClipboardError.dataCorrupted
                }
            } else {
                logger.error("❌ 图片文件路径为空")
                throw ClipboardError.dataCorrupted
            }
        }
        
        guard let data = imageData, !data.isEmpty else {
            logger.error("❌ 图片数据无效或为空")
            throw ClipboardError.dataCorrupted
        }
        
        guard let nsImage = NSImage(data: data) else {
            logger.error("❌ 无法从数据创建NSImage")
            throw ClipboardError.imageProcessingFailed
        }
        
        // 支持多种图片格式，确保兼容性
        let tiffData = nsImage.tiffRepresentation ?? data
        let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) ?? data
        
        // 设置多种格式以提高兼容性
        pasteboard.setData(tiffData, forType: .tiff)
        pasteboard.setData(pngData, forType: .png)
        
        // 尝试JPEG格式
        if let jpegData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            pasteboard.setData(jpegData, forType: NSPasteboard.PasteboardType("public.jpeg"))
        }
        
        logger.info("图片已复制到剪贴板")
    }
    
    private func copyFileToClipboard(_ item: ClipboardItem, pasteboard: NSPasteboard) throws {
        logger.info("🗂️ 开始复制文件类型内容: \(item.content)")
        logger.debug("📋 项目类型: \(item.type)")
        logger.debug("📋 数据大小: \(item.data?.count ?? 0) 字节")
        
        var fileURLs: [URL] = []
        
        // 方案1: 从JSON数据中解析文件URL
        if let jsonData = item.data {
            logger.debug("🔍 尝试解析JSON数据...")
            
            do {
                if let fileInfos = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    logger.debug("✅ 成功解析JSON，包含 \(fileInfos.count) 个文件信息")
                    
                    fileURLs = fileInfos.compactMap { info -> URL? in
                        guard let path = info["path"] as? String else { 
                            logger.warning("⚠️ 无效的文件路径: \(info)")
                            return nil 
                        }
                        
                        logger.debug("🔍 处理文件路径: \(path)")
                        
                        let url = URL(fileURLWithPath: path)
                        let exists = FileManager.default.fileExists(atPath: url.path)
                        
                        if !exists {
                            logger.warning("⚠️ 文件不存在: \(path)")
                            return nil
                        }
                        
                        logger.debug("✅ 文件存在: \(url.lastPathComponent)")
                        return url
                    }
                    
                    logger.info("🔍 从JSON解析到 \(fileURLs.count) 个有效文件")
                } else {
                    logger.warning("⚠️ JSON数据格式不正确")
                }
            } catch {
                logger.error("❌ JSON解析失败: \(error)")
            }
        }
        
        // 方案2: 如果JSON解析失败，尝试从content中提取文件名并搜索
        if fileURLs.isEmpty {
            logger.debug("🔍 尝试从content中提取文件名: \(item.content)")
            
            // 从类似 "文档: 高等学校毕业生档案转递单 - (附件3) .docx" 中提取文件名
            var fileName: String?
            
            // 查找冒号后的内容
            if let colonIndex = item.content.firstIndex(of: ":") {
                let afterColon = String(item.content[item.content.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                fileName = afterColon
            } else {
                fileName = item.content
            }
            
            if let searchFileName = fileName, !searchFileName.isEmpty {
                logger.debug("🔍 搜索文件名: \(searchFileName)")
                
                // 在常用位置搜索文件
                let searchPaths = [
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
                ]
                
                for searchPath in searchPaths {
                    let potentialFile = searchPath.appendingPathComponent(searchFileName)
                    if FileManager.default.fileExists(atPath: potentialFile.path) {
                        fileURLs.append(potentialFile)
                        logger.info("✅ 找到文件: \(potentialFile.path)")
                        break
                    }
                }
                
                // 如果还没找到，进行递归搜索
                if fileURLs.isEmpty {
                    logger.debug("🔍 进行递归搜索...")
                    if let foundURL = searchFileRecursively(fileName: searchFileName) {
                        fileURLs.append(foundURL)
                        logger.info("✅ 递归搜索找到文件: \(foundURL.path)")
                    }
                }
            }
        }
        
        // 方案3: 执行文件复制
        if !fileURLs.isEmpty {
            logger.info("🔄 准备复制 \(fileURLs.count) 个文件到剪贴板")
            
            pasteboard.clearContents()
            
            // 使用最可靠的方法：writeObjects
            let nsURLs = fileURLs.map { $0 as NSURL }
            let success = pasteboard.writeObjects(nsURLs)
            
            if success {
                logger.info("✅ 文件已成功复制到剪贴板: \(fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
                return
            } else {
                logger.warning("⚠️ writeObjects失败，尝试备用方案")
                
                // 备用方案：使用文件路径列表
                pasteboard.clearContents()
                let filePaths = fileURLs.map { $0.path }
                
                if pasteboard.setPropertyList(filePaths, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) {
                    logger.info("✅ 文件已成功复制到剪贴板 (NSFilenamesPboardType)")
                    return
                } else {
                    logger.error("❌ 所有文件复制方法都失败了")
                    throw ClipboardError.fileOperationFailed
                }
            }
        } else {
            logger.error("❌ 没有找到有效的文件路径")
            // 最后的备用方案：将内容作为文本复制
            pasteboard.clearContents()
            if pasteboard.setString(item.content, forType: .string) {
                logger.warning("⚠️ 已将内容作为文本复制")
            } else {
                throw ClipboardError.fileOperationFailed
            }
        }
    }
    
    // MARK: - 异步文件搜索优化
    
    private func searchFileRecursively(fileName: String) -> URL? {
        // 对于主线程调用，使用快速搜索
        return searchFileQuickly(fileName: fileName)
    }
    
    private func searchFileQuickly(fileName: String) -> URL? {
        // 只搜索最常用的目录，避免深度递归
        let commonPaths = getCommonSearchPaths()
        
        for basePath in commonPaths {
            let fileURL = basePath.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                logger.info("✅ 快速搜索找到文件: \(fileURL.path)")
                return fileURL
            }
        }
        
        // 如果快速搜索失败，启动异步深度搜索
        searchFileAsynchronously(fileName: fileName) { [weak self] foundURL in
            guard let self = self, let url = foundURL else { return }
            
            DispatchQueue.main.async {
                // 如果找到文件，可以选择性地通知UI或缓存结果
                self.logger.info("✅ 异步搜索找到文件: \(url.path)")
            }
        }
        
        return nil
    }
    
    private func searchFileAsynchronously(fileName: String, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            
            guard let enumerator = FileManager.default.enumerator(
                at: homeDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                completion(nil)
                return
            }
            
            // 限制搜索时间，避免长时间阻塞
            let startTime = Date()
            let maxSearchTime: TimeInterval = 5.0 // 最多搜索5秒
            
            for case let fileURL as URL in enumerator {
                // 检查是否超时
                if Date().timeIntervalSince(startTime) > maxSearchTime {
                    self.logger.warning("文件搜索超时，停止搜索: \(fileName)")
                    break
                }
                
                if fileURL.lastPathComponent == fileName {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            completion(fileURL)
                            return
                        }
                    } catch {
                        continue
                    }
                }
            }
            
            completion(nil)
        }
    }
    
    private func getFileSize(url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            logger.warning("⚠️ 无法获取文件大小: \(url.path)")
        }
        return "未知大小"
    }
    
    func deleteItem(_ item: ClipboardItem) {
        // 检查是否为收藏项目，如果是则不允许删除
        if FavoriteManager.shared.isFavorite(item) {
            logger.info("收藏项目不能删除: \(item.content.prefix(30))")
            return
        }
        
        if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
            let itemToDelete = clipboardItems[index]
            
            // 如果是图片类型，从缓存中移除
            if itemToDelete.type == .image {
                ImageCacheManager.shared.removeImage(forKey: itemToDelete.id.uuidString)
            }
            
            clipboardItems.remove(at: index)
            store.deleteItem(itemToDelete)
            logger.info("项目已删除: \(itemToDelete.content.prefix(30))")
            updateFilteredItems()
            
            // 发送剪贴板变化通知，确保菜单栏立即更新
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("ClipboardItemsChanged"), object: nil)
            }
        }
    }
    
    func clearAllItems() {
        // 1. 获取所有收藏项目（从FavoriteManager获取，确保数据一致性）
        let favoriteItems = FavoriteManager.shared.getAllFavorites()
        
        // 2. 清理非收藏项目的图片缓存
        for item in clipboardItems {
            if !FavoriteManager.shared.isFavorite(item) && item.type == .image {
                ImageCacheManager.shared.removeImage(forKey: item.id.uuidString)
            }
        }
        
        // 3. 清空存储
        store.clearAllItems()
        
        // 4. 重新保存收藏项目到存储
        for item in favoriteItems {
            store.saveItem(item)
        }
        
        // 5. 更新ClipboardManager的内存列表，包含所有收藏项目
        clipboardItems = favoriteItems
        
        // 6. 确保收藏项目在ClipboardManager中的状态正确
        for i in 0..<clipboardItems.count {
            clipboardItems[i].isFavorite = true
        }
        
        logger.info("非收藏项目已清空，收藏项目已保留(\(favoriteItems.count)个)")
        updateFilteredItems()
        
        // 7. 通知界面更新
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardItemsChanged"), object: nil)
        }
    }
    
    private func clearCache() {
        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in cacheFiles {
                try FileManager.default.removeItem(at: file)
            }
            print("缓存已清理")
        } catch {
            print("Error occurred")
        }
    }
    
    private func loadClipboardItems() {
        clipboardItems = store.loadItems()
        
        // 重启后重建去重哈希集合，防止重复预览
        recentHashes.removeAll()
        var uniqueItems: [ClipboardItem] = []
        var seenHashes = Set<String>()
        
        for item in clipboardItems {
            let hash = createItemHash(item)
            if !seenHashes.contains(hash) {
                seenHashes.insert(hash)
                recentHashes.insert(hash)
                uniqueItems.append(item)
            } else {
                logger.info("重启加载时发现重复项目，已跳过: \(item.content.prefix(30))")
            }
        }
        
        // 更新去重后的项目列表
        if uniqueItems.count != clipboardItems.count {
            logger.info("重启后去重：原\(clipboardItems.count)项，去重后\(uniqueItems.count)项")
            clipboardItems = uniqueItems
            // 不直接调用私有方法，而是通过清空并重新保存来更新存储
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.store.clearAllItems()
                for item in uniqueItems {
                    self?.store.saveItem(item)
                }
            }
        }
        
        logger.info("重启后加载了\(clipboardItems.count)个剪贴板项目")
        
        // 同步收藏状态，确保数据一致性
        // 延迟执行以确保FavoriteManager已完全初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            FavoriteManager.shared.syncWithClipboardStore()
            
            // 确保收藏项目在重启后能正确显示
            let favoriteItems = FavoriteManager.shared.getAllFavorites()
            if !favoriteItems.isEmpty {
                // 将收藏项目合并到ClipboardManager中（如果不存在的话）
                var updatedItems = self.clipboardItems
                for favoriteItem in favoriteItems {
                    if !updatedItems.contains(where: { $0.id == favoriteItem.id }) {
                        updatedItems.append(favoriteItem)
                    }
                }
                
                if updatedItems.count != self.clipboardItems.count {
                    self.clipboardItems = updatedItems.sorted { $0.timestamp > $1.timestamp }
                    self.logger.info("重启后恢复了\(favoriteItems.count)个收藏项目")
                }
            }
        }
        
        // 启动预加载缓存机制
        preloadRecentImages()
    }
    
    private func optimizeImageDataAsync(_ data: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { 
                    continuation.resume(returning: data)
                    return
                }
                
                do {
                    // 快速检查图片大小，避免不必要的处理
                    let fileSizeKB = data.count / 1024
                    if fileSizeKB < 100 { // 小于100KB的图片直接返回
                        continuation.resume(returning: data)
                        return
                    }
                    
                    guard let image = NSImage(data: data) else {
                        throw ClipboardError.imageProcessingFailed
                    }
                    
                    // 调整图片大小（使用设置管理器）
                    let targetSize = self.calculateTargetSize(image.size, maxSize: CGFloat(self.maxImageSize))
                    
                    // 如果图片已经很小，直接返回原数据
                    if targetSize.width >= image.size.width && targetSize.height >= image.size.height {
                        continuation.resume(returning: data)
                        return
                    }
                    
                    // 创建优化的图片
                    guard let resizedImage = self.resizeImage(image, to: targetSize) else {
                        continuation.resume(returning: data)
                        return
                    }
                    
                    // 生成优化的图片数据（使用设置管理器）
                    guard let tiffData = resizedImage.tiffRepresentation,
                          let bitmapRep = NSBitmapImageRep(data: tiffData),
                          let pngData = bitmapRep.representation(using: .png, properties: [.compressionFactor: self.settingsManager.compressionQuality]) else {
                        continuation.resume(returning: data)
                        return
                    }
                    
                    // 只在优化后有显著大小改善时才使用优化后的数据
                    if pngData.count < Int(Double(data.count) * 0.8) {
                        await self.cacheImageData(pngData)
                        continuation.resume(returning: pngData)
                    } else {
                        continuation.resume(returning: data)
                    }
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func cacheImageData(_ data: Data) async {
        let cacheFileName = "\(UUID().uuidString).png"
        let cacheURL = cacheDirectory.appendingPathComponent(cacheFileName)
        
        do {
            try data.write(to: cacheURL)
            print("图片已缓存: \(cacheFileName)")
        } catch {
            print("Error occurred")
        }
    }
    
    private func calculateTargetSize(_ originalSize: NSSize, maxSize: CGFloat) -> NSSize {
        if originalSize.width <= maxSize && originalSize.height <= maxSize {
            return originalSize
        }
        
        let ratio = min(maxSize / originalSize.width, maxSize / originalSize.height)
        return NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
    }
    
    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage? {
        // 如果目标尺寸与原图相同，直接返回原图
        if size.width == image.size.width && size.height == image.size.height {
            return image
        }
        
        // 使用更高效的图片处理方式
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        
        guard let bitmapRep = rep else {
            logger.error("无法创建 bitmap representation")
            return nil
        }
        
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            logger.error("无法创建图形上下文")
            return nil
        }
        
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        
        // 使用自动释放池处理图片绘制
        autoreleasepool {
            image.draw(in: NSRect(origin: .zero, size: size), 
                      from: NSRect(origin: .zero, size: image.size), 
                      operation: .copy, 
                      fraction: 1.0)
        }
        
        let newImage = NSImage(size: size)
        newImage.addRepresentation(bitmapRep)
        
        return newImage
    }
    
    // MARK: - 文件处理辅助方法
    
    private func extractFileURLsFromContent(_ content: String) -> [URL]? {
        print("🔍 从内容中提取文件URL: \(content.prefix(50))")
        
        // 方法1：从文件内容格式中提取
        if content.hasPrefix("Files: ") {
            let filesPart = String(content.dropFirst(7))
            return extractURLsFromFilesString(filesPart)
        }
        
        // 方法2：从分类格式中提取
        if content.contains("文件 (") && content.contains("个): ") {
            let components = content.components(separatedBy: ": ")
            if components.count > 1 {
                let filesPart = components[1]
                return extractURLsFromFilesString(filesPart)
            }
        }
        
        // 方法3：从单个文件格式中提取
        let patterns = [
            #"(图片|视频|音频|文档|代码|压缩包|应用程序|文件): (.+)"#,
            #"[^/\\]+\.(\w+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range(at: 2), in: content) {
                        let fileName = String(content[range])
                        if let urls = findFileByName(fileName) {
                            return urls
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractURLsFromFilesString(_ filesString: String) -> [URL]? {
        print("🔍 解析文件字符串: \(filesString)")
        
        var fileNames: [String] = []
        
        // 处理多个文件的情况，如 "file1.txt, file2.pdf 等3个"
        if filesString.contains(" 等") && filesString.contains("个") {
            let mainPart = filesString.components(separatedBy: " 等").first ?? filesString
            fileNames = mainPart.components(separatedBy: ", ").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        } else {
            // 处理简单逗号分隔的文件列表
            fileNames = filesString.components(separatedBy: ", ").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        }
        
        // 清理文件名（移除编号前缀等）
        fileNames = fileNames.compactMap { fileName in
            // 移除可能的编号前缀，如 "1. filename.txt"
            let cleaned = fileName.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
            return cleaned.isEmpty ? fileName : cleaned
        }
        
        print("🔍 提取的文件名: \(fileNames)")
        
        var validURLs: [URL] = []
        
        for fileName in fileNames {
            if let urls = findFileByName(fileName) {
                validURLs.append(contentsOf: urls)
            }
        }
        
        return validURLs.isEmpty ? nil : validURLs
    }
    
    private func findFileByName(_ fileName: String) -> [URL]? {
        guard !fileName.isEmpty else { return nil }
        
        print("🔍 查找文件: \(fileName)")
        
        // 验证文件名安全性
        guard isValidFileName(fileName) else {
            print("⚠️ 文件名包含非法字符: \(fileName)")
            return nil
        }
        
        var foundURLs: [URL] = []
        
        // 优先搜索路径
        let searchPaths = getCommonSearchPaths()
        
        for basePath in searchPaths {
            let fullPath = basePath.appendingPathComponent(fileName).path
            let url = URL(fileURLWithPath: fullPath)
            
            if FileManager.default.fileExists(atPath: url.path) {
                foundURLs.append(url)
                print("✅ 找到文件: \(fullPath)")
            }
        }
        
        // 如果在常见路径找不到，尝试用户主目录搜索
        if foundURLs.isEmpty {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            
            if let enumerator = FileManager.default.enumerator(at: homeURL, includingPropertiesForKeys: [.nameKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
                
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.lastPathComponent == fileName {
                        foundURLs.append(fileURL)
                        logger.info("✅ 在主目录找到文件: \(fileURL.path)")
                        
                        // 限制搜索结果数量
                        if foundURLs.count >= 3 {
                            break
                        }
                    }
                }
            } else {
                logger.warning("⚠️ 无法创建主目录枚举器")
            }
        }
        
        return foundURLs.isEmpty ? nil : foundURLs
    }
    
    private func parseFileURLsFromContent(_ content: String) -> [URL]? {
        // 使用新的提取方法
        return extractFileURLsFromContent(content)
    }
    
    // MARK: - 文件路径验证和安全检查
    
    private func isValidFilePath(_ path: String) -> Bool {
        // 基本路径验证
        guard !path.isEmpty && !path.contains("..") else {
            return false
        }
        
        // 检查路径是否以 /Users/ 开头（用户目录）或是绝对路径
        let isUserPath = path.hasPrefix("/Users/")
        let isValidAbsolutePath = path.hasPrefix("/") && FileManager.default.fileExists(atPath: path)
        
        return isUserPath || isValidAbsolutePath
    }
    
    private func isValidFileName(_ fileName: String) -> Bool {
        // 检查文件名是否包含危险字符
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return fileName.rangeOfCharacter(from: invalidCharacters) == nil
    }
    
    private func getCommonSearchPaths() -> [URL] {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        return [
            homeURL.appendingPathComponent("Downloads"),
            homeURL.appendingPathComponent("Desktop"),
            homeURL.appendingPathComponent("Documents"),
            URL(fileURLWithPath: "/tmp")
        ]
    }
    
    // MARK: - 智能缓存管理
    
    private func setupSmartCacheCleanup() {
        // 使用更长的清理间隔，减少CPU消耗
        let adaptiveCleanupInterval = cacheCleanupInterval * 2 // 从10分钟调整为20分钟
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: adaptiveCleanupInterval, repeats: true) { [weak self] _ in
            self?.performAdaptiveCacheCleanup()
        }
        
        logger.info("智能缓存清理已启动，间隔: \(adaptiveCleanupInterval)秒（自适应模式）")
    }
    
    private func performAdaptiveCacheCleanup() {
        // 根据用户活动状态决定是否执行清理
        let inactivityDuration = activityMonitor.getInactivityDuration()
        
        // 如果用户长时间不活跃，减少清理频率
        if inactivityDuration > 1800 { // 30分钟不活跃
            logger.debug("用户长时间不活跃，跳过缓存清理")
            return
        }
        
        performSmartCacheCleanup()
    }
    
    private func performSmartCacheCleanup() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            var cleanedCount = 0
            
            // 清理过期的哈希记录
            if now.timeIntervalSince(self.lastHashCleanup) > 7200 { // 2小时清理一次
                let oldHashCount = self.recentHashes.count
                self.recentHashes.removeAll()
                self.lastHashCleanup = now
                cleanedCount += oldHashCount
            }
            
            // 智能清理图片缓存
            self.cleanupImageCaches()
            
            // 清理验证缓存
            self.cleanupValidationCache()
            
            #if DEBUG
            if cleanedCount > 0 {
                DispatchQueue.main.async {
                    self.logger.debug("智能缓存清理完成，清理了 \(cleanedCount) 项")
                }
            }
            #endif
        }
    }
    
    private func cleanupImageCaches() {
        // 检查当前缓存使用情况
        let currentCacheCount = imageCache.countLimit
        let maxMemoryLimit = imageCache.totalCostLimit
        
        // 获取系统内存压力指示
        let memoryPressure = ProcessInfo.processInfo.thermalState
        
        // 根据系统状态调整清理策略
        switch memoryPressure {
        case .critical, .serious:
            // 内存压力大时，清空所有缓存
            imageCache.removeAllObjects()
            imageValidationCache.removeAllObjects()
            logger.warning("检测到内存压力，清空所有图片缓存")
        case .fair:
            // 中等压力时，减少缓存限制
            imageCache.countLimit = max(currentCacheCount / 2, 5)
            imageCache.totalCostLimit = max(maxMemoryLimit / 2, 10 * 1024 * 1024)
        default:
            // 正常情况下保持当前设置
            break
        }
    }
    
    private func cleanupValidationCache() {
        // 定期清空验证缓存，避免无限增长
        if imageValidationCache.countLimit > 200 {
            // 只清理一半，保留最近使用的缓存
            imageValidationCache.countLimit = 100
        }
    }
    
    // MARK: - 性能优化方法
    
    private func setupMemoryPressureMonitoring() {
        // macOS 使用不同的内存压力监听方式
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global())
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.handleMemoryWarning()
            }
        }
        source.resume()
    }
    
    private func handleMemoryWarning() {
        logger.warning("收到内存警告，开始清理缓存")
        
        // 立即执行智能缓存清理
        performSmartCacheCleanup()
        
        // 限制剪贴板项目数量，但保护收藏项目
        if clipboardItems.count > maxItems {
            // 分离收藏和非收藏项目
            let favoriteItems = clipboardItems.filter { FavoriteManager.shared.isFavorite($0) }
            let nonFavoriteItems = clipboardItems.filter { !FavoriteManager.shared.isFavorite($0) }
            
            // 计算需要保留的非收藏项目数量
            let maxNonFavoriteItems = max(0, maxItems - favoriteItems.count)
            
            if nonFavoriteItems.count > maxNonFavoriteItems {
                let itemsToKeep = Array(nonFavoriteItems.prefix(maxNonFavoriteItems))
                clipboardItems = favoriteItems + itemsToKeep
                logger.info("内存警告清理：保留 \(favoriteItems.count) 个收藏项目")
            }
            
            updateFilteredItems()
        }
        
        logger.info("内存清理完成")
    }
    
    // 快速计算内容哈希用于去重
    private func calculateQuickContentHash(_ pasteboard: NSPasteboard) -> String {
        var components: [String] = []
        
        // 添加类型信息
        if let types = pasteboard.types {
            components.append(types.map { $0.rawValue }.sorted().joined(separator: ","))
        }
        
        // 添加文本内容的前200个字符
        if let text = pasteboard.string(forType: .string) {
            components.append(String(text.prefix(200)))
        }
        
        // 为图片添加更详细的哈希（包含数据大小和部分内容）
        var hasImageData = false
        for imageType in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff] {
            if let imageData = pasteboard.data(forType: imageType) {
                // 使用大小和前64字节的哈希作为图片指纹
                let prefix = imageData.prefix(64)
                let prefixHash = prefix.hashValue
                components.append("img_\(imageType.rawValue):\(imageData.count)_\(prefixHash)")
                hasImageData = true
                break
            }
        }
        
        // 如果没有找到标准图片格式，检查其他图片类型
        if !hasImageData, let types = pasteboard.types {
            for type in types {
                let typeString = type.rawValue.lowercased()
                if typeString.contains("image") || typeString.contains("png") || typeString.contains("jpg") {
                    if let data = pasteboard.data(forType: type) {
                        let prefix = data.prefix(64)
                        let prefixHash = prefix.hashValue
                        components.append("img_\(type.rawValue):\(data.count)_\(prefixHash)")
                        break
                    }
                }
            }
        }
        
        // 为文件URL添加路径信息
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let paths = fileURLs.map { $0.path }.sorted().joined(separator: ",")
            components.append("files:\(paths)")
        }
        
        return components.joined(separator: "|").hash.description
    }
    
    // 为已存储的ClipboardItem创建哈希用于去重
    func createItemHash(_ item: ClipboardItem) -> String {
        var components: [String] = []
        
        // 添加类型信息
        components.append("type:\(item.type.rawValue)")
        
        // 根据类型添加内容哈希
        switch item.type {
        case .image:
            // 对于图片，使用数据大小和内容的前64字节作为指纹
            if let data = item.data, data.count > 0 {
                let prefix = data.prefix(64)
                let prefixHash = prefix.hashValue
                components.append("img_data:\(data.count)_\(prefixHash)")
            } else {
                // 如果没有数据，使用内容字符串和时间戳
                components.append("img_content:\(item.content.prefix(100))")
                components.append("timestamp:\(Int(item.timestamp.timeIntervalSince1970))")
            }
        case .text:
            // 对于文本，使用内容的前500个字符进行精确匹配
            let textContent = item.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            components.append("text:\(textContent.prefix(500))")
            // 添加字符数作为额外验证
            components.append("length:\(textContent.count)")
        case .video:
            // 对于视频，使用数据哈希和文件信息
            if let data = item.data, data.count > 0 {
                let prefix = data.prefix(128)
                let prefixHash = prefix.hashValue
                components.append("video_data:\(data.count)_\(prefixHash)")
            } else {
                components.append("video_content:\(item.content.prefix(200))")
            }
        case .audio:
            // 对于音频，使用数据哈希和文件信息
            if let data = item.data, data.count > 0 {
                let prefix = data.prefix(128)
                let prefixHash = prefix.hashValue
                components.append("audio_data:\(data.count)_\(prefixHash)")
            } else {
                components.append("audio_content:\(item.content.prefix(200))")
            }
        case .file, .document, .code, .archive, .executable:
            // 对于文件，结合数据和路径信息
            if let data = item.data, data.count > 0 {
                let prefix = data.prefix(64)
                let prefixHash = prefix.hashValue
                components.append("file_data:\(data.count)_\(prefixHash)")
            }
            components.append("file_content:\(item.content.prefix(300))")
        }
        
        return components.joined(separator: "|").hash.description
    }
    
    private func updateFilteredItems() {
        if searchText.isEmpty {
            filteredItems = clipboardItems
        } else {
            filteredItems = clipboardItems.filter { item in
                // 支持模糊搜索
                let searchComponents = searchText.lowercased().components(separatedBy: " ")
                let itemContent = item.content.lowercased()
                
                return searchComponents.allSatisfy { component in
                    itemContent.contains(component)
                }
            }
        }
    }
    
    // 新增：将项目恢复到系统剪贴板
    func restoreToClipboard(_ item: ClipboardItem) {
        // 设置标志避免自己触发的变化被重复检测
        isPerformingCopyOperation = true
        copyOperationTimestamp = Date().timeIntervalSince1970
        
        // 直接将项目内容恢复到系统剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        var success = false
        switch item.type {
        case .text:
            success = pasteboard.setString(item.content, forType: .string)
        case .image:
            if let imageData = item.data {
                success = pasteboard.setData(imageData, forType: .png)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let imageData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(imageData, forType: .png)
            }
        case .file:
            if let fileData = item.data {
                success = pasteboard.setData(fileData, forType: .fileContents)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(fileData, forType: .fileContents)
            }
        case .video:
            if let videoData = item.data {
                success = pasteboard.setData(videoData, forType: .fileContents)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let videoData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(videoData, forType: .fileContents)
            }
        case .audio:
            if let audioData = item.data {
                success = pasteboard.setData(audioData, forType: .fileContents)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let audioData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(audioData, forType: .fileContents)
            }
        case .document:
            if let documentData = item.data {
                success = pasteboard.setData(documentData, forType: .fileContents)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let documentData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(documentData, forType: .fileContents)
            }
        case .code:
            // 代码类型作为文本处理
            success = pasteboard.setString(item.content, forType: .string)
        case .archive:
            if let archiveData = item.data {
                success = pasteboard.setData(archiveData, forType: .fileContents)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let archiveData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(archiveData, forType: .fileContents)
            }
        case .executable:
            if let executableData = item.data {
                success = pasteboard.setData(executableData, forType: .fileContents)
            } else if let filePath = item.filePath, !filePath.isEmpty,
                      let executableData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                success = pasteboard.setData(executableData, forType: .fileContents)
            }
        }
        
        if success {
            logger.info("✅ 已恢复到系统剪贴板: \(item.content.prefix(30))")
            
            // 更新剪贴板计数以同步状态
            lastChangeCount = NSPasteboard.general.changeCount
        } else {
            logger.error("❌ 恢复到剪贴板失败: \(item.content.prefix(30))")
        }
        
        // 延迟恢复监控状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isPerformingCopyOperation = false
        }
    }
    
    // 新增：获取存储信息
    func getStorageInfo() -> ClipboardStore.StorageInfo {
        return store.getStorageInfo()
    }
    
    // 新增：手动清理存储
    func performManualCleanup() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.logger.info("🧹 开始手动清理存储...")
            self?.store.performManualCleanup()
            
            // 重新加载剪贴板项目
            DispatchQueue.main.async {
                self?.clipboardItems = []
                self?.loadClipboardItems()
            }
            
            self?.logger.info("✅ 手动清理完成")
        }
    }
    
    // MARK: - 增强的搜索功能
    
    func searchItems(with query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return clipboardItems }
        
        let lowercaseQuery = query.lowercased()
        
        return clipboardItems.filter { item in
            // 1. 精确匹配
            if item.content.lowercased().contains(lowercaseQuery) {
                return true
            }
            
            // 2. 模糊匹配（支持拼音首字母等）
            let words = item.content.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            return words.contains { word in
                word.lowercased().hasPrefix(lowercaseQuery)
            }
        }.sorted { item1, item2 in
            // 按相关性排序
            let score1 = calculateRelevanceScore(item: item1, query: lowercaseQuery)
            let score2 = calculateRelevanceScore(item: item2, query: lowercaseQuery)
            return score1 > score2
        }
    }
    
    private func calculateRelevanceScore(item: ClipboardItem, query: String) -> Int {
        let content = item.content.lowercased()
        var score = 0
        
        // 开头匹配得分更高
        if content.hasPrefix(query) {
            score += 100
        }
        
        // 包含完整查询的得分
        if content.contains(query) {
            score += 50
        }
        
        // 时间越新得分越高
        let timeScore = max(0, 10 - Int(Date().timeIntervalSince(item.timestamp) / 3600))
        score += timeScore
        
        return score
    }
    
    // MARK: - 图片优化处理
    
    private func optimizeImage(_ data: Data) -> Data? {
        guard data.count > maxImageSize else { return data }
        
        guard let image = NSImage(data: data) else { return nil }
        
        // 计算压缩比例
        let compressionRatio = Double(maxImageSize) / Double(data.count)
        let targetSize = NSSize(
            width: image.size.width * sqrt(compressionRatio),
            height: image.size.height * sqrt(compressionRatio)
        )
        
        return resizeImageToData(image, to: targetSize)
    }
    
    private func resizeImageToData(_ image: NSImage, to targetSize: NSSize) -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        
        guard let bitmapRep = rep else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        
        NSGraphicsContext.restoreGraphicsState()
        
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
    
    // MARK: - 智能内容分类
    
    private func categorizeContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // URL检测
        if let url = URL(string: trimmed), url.scheme != nil {
            return "🌐 链接"
        }
        
        // 邮箱检测
        if trimmed.contains("@") && trimmed.contains(".") {
            let emailRegex = try? NSRegularExpression(pattern: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#)
            if emailRegex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.count)) != nil {
                return "📧 邮箱"
            }
        }
        
        // 电话号码检测
        let phoneRegex = try? NSRegularExpression(pattern: #"^[+]?[\d\s\-\(\)]{8,}$"#)
        if phoneRegex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.count)) != nil {
            return "📞 电话"
        }
        
        // 代码检测
        if trimmed.contains("{") && trimmed.contains("}") ||
           trimmed.contains("function") || trimmed.contains("class") ||
           trimmed.contains("import") || trimmed.contains("from") {
            return "💻 代码"
        }
        
        return "📝 文本"
    }
    
    // MARK: - 预加载缓存机制
    
    /// 预加载最近的图片到缓存中，提升启动体验
    private func preloadRecentImages() {
        let maxPreloadCount = 5 // 预加载最近5张图片
        
        // 在后台线程执行预加载，避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            let recentImageItems = self.clipboardItems
                .filter { $0.type == ClipboardItemType.image }
                .prefix(maxPreloadCount)
            
            self.logger.info("🚀 开始预加载 \(recentImageItems.count) 张最近的图片")
            
            for item in recentImageItems {
                // 检查是否已在缓存中
                if ImageCacheManager.shared.getImage(forKey: item.id.uuidString) != nil {
                    continue // 已缓存，跳过
                }
                
                // 使用队列管理器进行预加载
                ImageLoadingQueueManager.shared.enqueueImageLoad(
                    itemId: item.id.uuidString,
                    priority: .background
                ) {
                    await self.performPreloadImage(item: item)
                }
            }
        }
    }
    
    /// 执行单个图片的预加载
    @MainActor
    private func performPreloadImage(item: ClipboardItem) async {
        // 从文件路径或内存加载图片数据
        let imageData: Data?
        if let filePath = item.filePath, !filePath.isEmpty {
            imageData = try? Data(contentsOf: URL(fileURLWithPath: filePath))
        } else {
            imageData = item.data
        }
        
        guard let imageData = imageData, imageData.count > 0 else {
            logger.debug("预加载失败：无法获取图片数据 - \(item.id)")
            return
        }
        
        // 在后台线程解码图片
        let image = await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                let nsImage = NSImage(data: imageData)
                continuation.resume(returning: nsImage)
            }
        }
        
        if let image = image {
            ImageCacheManager.shared.setImage(image, forKey: item.id.uuidString)
            logger.debug("✅ 预加载完成：\(item.id)")
        } else {
            logger.debug("❌ 预加载失败：无法解码图片 - \(item.id)")
        }
    }
    
    deinit {
        // 停止所有监控
        stopMonitoring()
        
        // 移除所有通知观察者
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        
        // 停止所有定时器
        cacheCleanupTimer?.invalidate()
        cacheCleanupTimer = nil
        
        logger.info("ClipboardManager 已释放，所有资源已清理")
    }
}

class ImageCacheManager {
    static let shared = ImageCacheManager()

    // NSCache 是线程安全的，并且会在系统内存不足时自动释放对象
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        // 配置缓存限制，避免占用过多内存
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        cache.countLimit = 100 // 最多100张图片
    }

    /// 将图片存入缓存
    /// - Parameters:
    ///   - image: 要缓存的 NSImage 对象
    ///   - key: 唯一的缓存键 (通常是 item.id.uuidString)
    func setImage(_ image: NSImage, forKey key: String) {
        // 计算图片的近似内存占用
        let cost = Int(image.size.width * image.size.height * 4) // 假设每个像素4字节
        cache.setObject(image, forKey: key as NSString, cost: min(cost, 10 * 1024 * 1024)) // 单张图片不超过10MB
    }

    /// 从缓存中获取图片
    /// - Parameter key: 唯一的缓存键
    /// - Returns: 缓存的 NSImage 对象，如果不存在则返回 nil
    func getImage(forKey key: String) -> NSImage? {
        if let image = cache.object(forKey: key as NSString) {
            return image
        } else {
            return nil
        }
    }

    /// 从缓存中移除指定的图片
    /// - Parameter key: 唯一的缓存键
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// 清空整个缓存
    func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - 图片加载队列管理器
class ImageLoadingQueueManager: @unchecked Sendable {
    static let shared = ImageLoadingQueueManager()
    
    private let maxConcurrentLoads = 3 // 最大同时加载数量
    private let loadingQueue = DispatchQueue(label: "image.loading.queue", qos: .userInitiated, attributes: .concurrent)
    private let semaphore: DispatchSemaphore
    private var activeLoads = Set<String>()
    private let activeLoadsLock = DispatchQueue(label: "activeLoads.lock", qos: .userInitiated, attributes: .concurrent)
    
    private init() {
        self.semaphore = DispatchSemaphore(value: maxConcurrentLoads)
    }
    
    /// 添加图片加载任务到队列
    /// - Parameters:
    ///   - itemId: 图片项目ID
    ///   - priority: 加载优先级
    ///   - loadTask: 加载任务闭包
    func enqueueImageLoad(itemId: String, priority: TaskPriority = .userInitiated, loadTask: @escaping () async -> Void) {
        // 检查是否已经在加载中
        let isAlreadyLoading = activeLoadsLock.sync {
            let isLoading = activeLoads.contains(itemId)
            if !isLoading {
                activeLoads.insert(itemId)
            }
            return isLoading
        }
        
        guard !isAlreadyLoading else {
            return
        }
        
        Task(priority: priority) {
            // 使用合适的QoS等待信号量，避免优先级倒置
            let qosClass: DispatchQoS.QoSClass = {
                switch priority {
                case .userInteractive:
                    return .userInteractive
                case .userInitiated:
                    return .userInitiated
                default:
                    return .utility
                }
            }()
            
            // 等待信号量，使用匹配的QoS避免优先级倒置
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: qosClass).async {
                    self.semaphore.wait()
                    continuation.resume()
                }
            }
            
            // 执行实际的加载任务
            await loadTask()
            
            // 完成后释放资源，使用匹配的QoS
            activeLoadsLock.async(qos: DispatchQoS(qosClass: qosClass, relativePriority: 0), flags: .barrier) { [self] in
                activeLoads.remove(itemId)
            }
            
            semaphore.signal()
        }
    }
    
    /// 取消指定图片的加载
    /// - Parameter itemId: 图片项目ID
    func cancelImageLoad(itemId: String) {
        activeLoadsLock.async(qos: .userInitiated, flags: .barrier) { [self] in
            activeLoads.remove(itemId)
        }
    }
    
    /// 获取当前活跃的加载数量
    var activeLoadCount: Int {
        return activeLoadsLock.sync {
            return activeLoads.count
        }
    }
}
