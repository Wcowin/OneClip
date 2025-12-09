import SwiftUI
import AppKit
import Foundation
import ApplicationServices
import Carbon
import ServiceManagement
import UserNotifications
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    private var statusBarRetryCount = 0
    private let maxStatusBarRetries = 3
    private var hotkeyManager: HotkeyManager?
    private var hasShownPermissionAlert = false
    private var isCheckingPermissions = false
    private var statusItemMonitorTimer: Timer?
    private var permissionMonitorTimer: Timer?
    private var wasAccessibilityDenied = false
    private var cancellables = Set<AnyCancellable>()
    private var windowManager: WindowManager? // 添加windowManager引用
    
    // 权限检查缓存优化
    private var lastPermissionCheck: Date = Date(timeIntervalSince1970: 0)
    private var permissionCache: Bool?
    private let permissionCacheValidDuration: TimeInterval = 1.0 // 1秒缓存
    
    var mainWindow: NSWindow?
    
    // 全局权限弹窗控制机制
    private static var isPermissionDialogShowing = false
    private static var lastPermissionDialogTime: Date = Date(timeIntervalSince1970: 0)
    private static let permissionDialogCooldown: TimeInterval = 30.0 // 30秒冷却时间
    private static var hasShownPermissionDialogThisSession = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 首先初始化设置管理器并应用主题
        let _ = SettingsManager.shared
        
        // 确保应用启动时badge状态正确
        // 只有在启用通知时才可能显示badge，否则确保badge为空
        NSApplication.shared.dockTile.badgeLabel = nil
        // 应用启动时已确保 badge 为空
        
        // 初始化通知系统
        setupNotificationSystem()
        
        // 监听设置变化
        setupSettingsObservers()
        
        // 监听应用事件
        setupApplicationObservers()
        
        // 设置应用不退出当最后一个窗口关闭时
        // 初始设置为 regular 模式，确保 dock 图标可以显示
        NSApp.setActivationPolicy(.regular)
        
        // 禁用"新建窗口"菜单项
        if let mainMenu = NSApplication.shared.mainMenu {
            for menuItem in mainMenu.items {
                if let submenu = menuItem.submenu {
                    for subItem in submenu.items {
                        if subItem.title.contains("New") || subItem.title.contains("新建") ||
                           (subItem.keyEquivalent == "n" && subItem.keyEquivalentModifierMask.contains(.command)) {
                            subItem.isEnabled = false
                            subItem.isHidden = true
                        }
                    }
                }
            }
        }
        
        // 只创建一个状态栏图标
        setupStatusBarItem()
        
        // 设置窗口关闭行为
        setupWindowCloseBehavior()
        
        // 监听剪贴板变化以更新菜单
        setupClipboardMonitoring()
        
        // 立即设置全局快捷键
        setupGlobalHotkey()
        
        // 延迟检查应用策略，初始启动时隐藏Dock图标
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let hasVisibleWindows = NSApplication.shared.windows.contains { $0.isVisible }
            
            // 启动策略检查 - 窗口可见: \(hasVisibleWindows)
            
            if !hasVisibleWindows {
                // 没有可见窗口，默认隐藏 Dock 图标
                NSApp.setActivationPolicy(.accessory)
                // 应用启动完成，默认隐藏 Dock 图标
                
                // 立即确保状态栏图标在切换到accessory模式后保持可见
                self.ensureStatusBarVisibilityAfterPolicyChange()
            } else {
                // 有可见窗口，暂时保持 regular 模式
                // 应用启动完成，有可见窗口，暂时保持 Dock 图标
            }
            
            // 切换到后台模式后，确保状态栏图标仍然可见
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.verifyAndFixStatusBarItem()
            }
            
            // 启动状态栏监控系统
            self.startStatusBarMonitoring()
            
            // 标记首次启动完成（在所有初始化完成后）
            if SettingsManager.shared.isFirstLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    SettingsManager.shared.markFirstLaunchCompleted()
                    // 首次启动流程完成
                }
            }
        }
    }
    
    // 验证并修复状态栏项目
    private func verifyAndFixStatusBarItem() {
        logDebug("🔍 开始验证状态栏项目...")
        
        if statusItem == nil {
            logWarning("⚠️ 状态栏项目为空，重新创建...")
            if statusBarRetryCount < maxStatusBarRetries {
                createStatusBarItem()
            }
            return
        }
        
        guard let statusItem = statusItem else { return }
        
        // 检查状态栏项目是否可见
        if !statusItem.isVisible {
            logWarning("⚠️ 状态栏项目不可见，设置为可见...")
            statusItem.isVisible = true
        }
        
        // 强制确保可见性（即使已经是可见状态）
        statusItem.isVisible = true
        
        // 检查按钮是否存在
        if statusItem.button == nil {
            logWarning("⚠️ 状态栏按钮为空，重新创建状态栏项目...")
            if statusBarRetryCount < maxStatusBarRetries {
                createStatusBarItem()
            }
            return
        }
        
        // 检查按钮是否有图像
        if statusItem.button?.image == nil {
            logWarning("⚠️ 状态栏按钮没有图像，重新设置...")
            setupStatusBarButtonImage()
        }
        
        // 额外的强制刷新：确保系统状态栏重新渲染
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 临时改变长度后恢复，强制系统重新渲染
            let originalLength = statusItem.length
            statusItem.length = 0
            statusItem.length = originalLength
            statusItem.isVisible = true
        }
        
        logDebug("✅ 状态栏项目验证通过")
    }
    
    // 确保状态栏图标在应用策略变更后保持可见
    private func ensureStatusBarVisibilityAfterPolicyChange() {
        logDebug("🔧 确保状态栏图标在策略变更后可见...")
        
        // 立即检查并修复状态栏项目
        guard let statusItem = statusItem else {
            logWarning("⚠️ 状态栏项目为空，立即重新创建...")
            createStatusBarItem()
            return
        }
        
        // 强制设置为可见
        statusItem.isVisible = true
        
        // 确保按钮存在且配置正确
        if let button = statusItem.button {
            button.appearsDisabled = false
            
            // 如果没有图像，重新设置
            if button.image == nil {
                setupStatusBarButtonImage()
            }
        } else {
            logWarning("⚠️ 状态栏按钮为空，重新创建状态栏项目...")
            createStatusBarItem()
            return
        }
        
        // 强制刷新状态栏显示
        DispatchQueue.main.async {
            let _ = statusItem.length
            statusItem.length = NSStatusItem.variableLength
            statusItem.isVisible = true
            
            // 再次确认可见性
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                statusItem.isVisible = true
                logDebug("✅ 状态栏图标策略变更后可见性已确保")
            }
        }
    }
    
    // 独立的状态栏按钮图像设置方法
    private func setupStatusBarButtonImage() {
        guard let statusItem = statusItem, let button = statusItem.button else {
            return
        }
        
        // 设置状态栏按钮图像
        
        // 优化的系统图标选择 - 使用最新的 SF Symbols
        var iconImage: NSImage?
        
        // 按优先级尝试更现代的 SF Symbols 图标
        let iconNames = [
            "clipboard",                    // 主要剪贴板图标
            "doc.on.clipboard",             // 文档剪贴板
            "list.clipboard",               // 列表剪贴板  
            "clipboard.fill",               // 填充剪贴板
            "square.stack.3d.up",           // 堆叠立体
            "square.stack",                 // 堆叠方块
            "tray.2",                       // 双层托盘
            "archivebox",                   // 存档盒
            "folder.badge.plus"             // 文件夹加号
        ]
        
        // 按顺序尝试图标
        for iconName in iconNames {
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "OneClip") {
                iconImage = image
                logDebug("使用系统状态栏图标: \(iconName)")
                break
            }
        }
        
        if let iconImage = iconImage {
            // 配置系统图标
            button.image = iconImage
            button.image?.isTemplate = true
            logDebug("系统图标配置完成")
        } else {
            // 使用优化的自定义图标
            logDebug("系统图标不可用，使用优化的自定义图标")
            let customIcon = createCustomIcon()
            button.image = customIcon
            button.image?.isTemplate = true
        }
        
        // 最后的备选方案 - 使用简单文本
        if button.image == nil {
            button.title = "📋"
            logDebug("使用文本图标作为最后备选方案")
        }
        
        // 确保图标大小合适
        if let image = button.image {
            image.size = NSSize(width: 16, height: 16)
        }
        
        // 确保按钮其他属性设置正确
        button.title = button.image != nil ? "" : button.title
        button.toolTip = "OneClip - 剪贴板管理器"
        button.isBordered = false
        button.appearsDisabled = false
    }
    
    // MARK: - 窗口控制
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // 防止创建新的无标题文档窗口
        // 阻止创建新的无标题窗口
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时不退出应用
        return false
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // 防止通过文件打开创建新窗口
        // 阻止通过文件打开创建新窗口
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // applicationShouldHandleReopen - hasVisibleWindows: \(flag)
        
        // 强制关闭多余的窗口，只保留一个
        let allWindows = NSApplication.shared.windows
        // 当前窗口总数: \(allWindows.count)
        
        var mainWindowFound = false
        for window in allWindows {
            if window.title == "OneClip" || window.className.contains("SwiftUI") {
                if !mainWindowFound {
                    // 第一个找到的主窗口，设为主窗口并显示
                    mainWindow = window
                    mainWindowFound = true
                    // 设置主窗口: \(window)
                } else {
                    // 多余的窗口，关闭它
                    // 关闭多余窗口: \(window)
                    window.close()
                }
            }
        }
        
        if !flag && mainWindow != nil {
            // 如果没有可见窗口但有主窗口，显示主窗口
            logDebug("通过 dock 图标重新打开应用")
            showMainWindowToFront()
            return true
        }
        return true
    }
    
    private func setupStatusBarItem() {
        // 确保在主线程上创建状态栏项目
        DispatchQueue.main.async {
            // 根据设置决定是否创建状态栏项目
            if SettingsManager.shared.showInMenuBar {
                self.ensureStatusBarItemExists()
                // 启动监控
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startStatusBarMonitoring()
                }
            }
        }
    }
    
    private func createStatusBarItem() {
        logDebug("开始创建状态栏项目...")
        
        // 重置重试计数器（仅在首次调用时）
        if statusBarRetryCount == 0 {
            statusBarRetryCount = 0
        }
        
        // 先移除现有的状态栏项目（如果有）
        if let existingItem = statusItem {
            NSStatusBar.system.removeStatusItem(existingItem)
            statusItem = nil
            logDebug("已移除现有状态栏项目")
        }
        
        // 创建新的状态栏项目，使用更合适的长度
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else {
            // 无法创建状态栏项目
            
            // 暂时禁用重试逻辑以避免编译卡死
        logWarning("⚠️ 状态栏项目创建失败")
            return
        }
        
        // 立即设置为可见
        statusItem.isVisible = true
        // 状态栏项目已创建并设置为可见
        
        if let button = statusItem.button {
            // 开始配置状态栏按钮
            
            // 使用独立的图像设置方法
            setupStatusBarButtonImage()
            
            // 设置按钮动作和属性
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            // 状态栏按钮配置完成
        } else {
            // 状态栏按钮创建失败
            
            // 暂时禁用重试逻辑以避免编译卡死
        logWarning("⚠️ 状态栏按钮创建失败")
            return
        }
        
        // 创建菜单
        setupStatusBarMenu()
        
        // 延迟再次确保状态栏项目可见，并添加额外的验证
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.statusItem?.isVisible = true
            // 状态栏图标最终可见性确认
            
            // 暂时禁用延迟验证以避免编译卡死
        // 状态栏项目创建完成
        }
    }
    
    // 创建自定义图标 - 现代化设计
    private func createCustomIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // 清除背景
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // 使用系统适配的颜色
        let primaryColor = NSColor.labelColor
        let accentColor = NSColor.controlAccentColor
        
        // 设置高质量渲染
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        
        // 绘制现代剪贴板图标设计
        drawModernClipboardIcon(size: size, primaryColor: primaryColor, accentColor: accentColor)
        
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
    
    private func drawModernClipboardIcon(size: NSSize, primaryColor: NSColor, accentColor: NSColor) {
        // 方案1：现代简约剪贴板设计
        let iconStyle = getIconStyle()
        
        switch iconStyle {
        case .modern:
            drawModernMinimalClipboard(size: size, primaryColor: primaryColor, accentColor: accentColor)
        case .classic:
            drawClassicClipboard(size: size, primaryColor: primaryColor, accentColor: accentColor)
        case .rounded:
            drawRoundedClipboard(size: size, primaryColor: primaryColor, accentColor: accentColor)
        }
    }
    
    private enum IconStyle {
        case modern, classic, rounded
    }
    
    private func getIconStyle() -> IconStyle {
        // 根据系统版本或用户偏好选择图标样式
        return .modern
    }
    
    // 现代简约风格
    private func drawModernMinimalClipboard(size: NSSize, primaryColor: NSColor, accentColor: NSColor) {
        let scale = min(size.width, size.height) / 16.0
        
        // 主剪贴板区域 - 使用更现代的比例
        let boardRect = NSRect(
            x: 2 * scale,
            y: 1 * scale, 
            width: 12 * scale,
            height: 14 * scale
        )
        
        // 绘制主板背景（轻微的背景色）
        let boardPath = NSBezierPath(roundedRect: boardRect, xRadius: 2 * scale, yRadius: 2 * scale)
        NSColor.controlBackgroundColor.withAlphaComponent(0.1).setFill()
        boardPath.fill()
        
        // 绘制边框
        primaryColor.withAlphaComponent(0.8).setStroke()
        boardPath.lineWidth = 1.2 * scale
        boardPath.stroke()
        
        // 顶部夹子设计 - 更现代的造型
        let clipRect = NSRect(
            x: 6 * scale,
            y: 13 * scale,
            width: 4 * scale,
            height: 2.5 * scale
        )
        let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 1 * scale, yRadius: 1 * scale)
        accentColor.setFill()
        clipPath.fill()
        
        // 内容线条 - 简洁的设计
        primaryColor.withAlphaComponent(0.7).setStroke()
        drawContentLines(inRect: boardRect, scale: scale, lineWidth: 0.8 * scale)
        
        // 添加现代化的角标指示器
        let indicatorRect = NSRect(x: 11 * scale, y: 11 * scale, width: 3 * scale, height: 3 * scale)
        let indicatorPath = NSBezierPath(ovalIn: indicatorRect)
        accentColor.withAlphaComponent(0.8).setFill()
        indicatorPath.fill()
    }
    
    // 经典风格
    private func drawClassicClipboard(size: NSSize, primaryColor: NSColor, accentColor: NSColor) {
        let scale = min(size.width, size.height) / 16.0
        
        // 经典剪贴板设计
        let boardRect = NSRect(x: 3 * scale, y: 2 * scale, width: 10 * scale, height: 12 * scale)
        let boardPath = NSBezierPath(roundedRect: boardRect, xRadius: 1.5 * scale, yRadius: 1.5 * scale)
        
        primaryColor.withAlphaComponent(0.8).setStroke()
        boardPath.lineWidth = 1.5 * scale
        boardPath.stroke()
        
        // 经典夹子
        let clipRect = NSRect(x: 6.5 * scale, y: 12.5 * scale, width: 3 * scale, height: 2 * scale)
        let clipPath = NSBezierPath(rect: clipRect)
        accentColor.setFill()
        clipPath.fill()
        
        // 经典内容线条
        primaryColor.withAlphaComponent(0.6).setStroke()
        drawContentLines(inRect: boardRect, scale: scale, lineWidth: 1.0 * scale)
    }
    
    // 圆润风格
    private func drawRoundedClipboard(size: NSSize, primaryColor: NSColor, accentColor: NSColor) {
        let scale = min(size.width, size.height) / 16.0
        
        // 圆润的剪贴板设计
        let boardRect = NSRect(x: 2.5 * scale, y: 1.5 * scale, width: 11 * scale, height: 13 * scale)
        let boardPath = NSBezierPath(roundedRect: boardRect, xRadius: 3 * scale, yRadius: 3 * scale)
        
        // 渐变效果
        let gradient = NSGradient(starting: primaryColor.withAlphaComponent(0.1), ending: primaryColor.withAlphaComponent(0.05))
        gradient?.draw(in: boardPath, angle: -45)
        
        primaryColor.withAlphaComponent(0.8).setStroke()
        boardPath.lineWidth = 1.2 * scale
        boardPath.stroke()
        
        // 圆润夹子
        let clipRect = NSRect(x: 6.5 * scale, y: 13 * scale, width: 3 * scale, height: 2 * scale)
        let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 1.5 * scale, yRadius: 1.5 * scale)
        accentColor.setFill()
        clipPath.fill()
        
        // 圆润内容线条
        primaryColor.withAlphaComponent(0.7).setStroke()
        drawContentLines(inRect: boardRect, scale: scale, lineWidth: 0.9 * scale, rounded: true)
    }
    
    private func drawContentLines(inRect rect: NSRect, scale: CGFloat, lineWidth: CGFloat, rounded: Bool = false) {
        let leftMargin = rect.minX + 2 * scale
        let rightMargin = rect.maxX - 2 * scale
        let lineSpacing = 2.2 * scale
        let startY = rect.maxY - 3 * scale
        
        // 绘制内容线条，长度递减营造层次感
        let lineLengths: [CGFloat] = [0.85, 0.75, 0.6, 0.45] // 相对长度
        
        for (index, relativeLength) in lineLengths.enumerated() {
            let y = startY - CGFloat(index) * lineSpacing
            if y < rect.minY + 2 * scale { break }
            
            let lineWidth = (rightMargin - leftMargin) * relativeLength
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: leftMargin, y: y))
            linePath.line(to: NSPoint(x: leftMargin + lineWidth, y: y))
            linePath.lineWidth = lineWidth
            linePath.lineCapStyle = rounded ? .round : .square
            linePath.stroke()
        }
    }
    
    private func setupStatusBarMenu() {
        // 开始设置状态栏菜单
        statusMenu = NSMenu()
        statusMenu?.autoenablesItems = false
        updateStatusBarMenu()
        // 状态栏菜单设置完成
    }
    
    private func updateStatusBarMenu() {
        guard let menu = statusMenu else {
            // 菜单为空，无法更新
            return
        }
        
        // 清空现有菜单项
        menu.removeAllItems()
        
        // 获取最近的剪贴板项目
        let clipboardItems = ClipboardManager.shared.clipboardItems.prefix(9) // 显示前9个最新项目
        
        // 更新菜单项数量: \(clipboardItems.count)
        
        // 添加剪贴板项目到菜单
        if !clipboardItems.isEmpty {
            for (index, item) in clipboardItems.enumerated() {
                // 处理菜单项 \(index): 类型=\(item.type), 内容=\(item.content.prefix(20))
                let menuItem = NSMenuItem(
                    title: menuTitle(for: item),
                    action: #selector(copyClipboardItem(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                menuItem.target = self
                menuItem.tag = index
                
                // 改进 tooltip 显示，使用哈希验证的数据
                if item.type == .image {
                    let itemHash = ClipboardManager.shared.createItemHash(item)
                    if let validImageData = getValidatedImageData(for: item, expectedHash: itemHash),
                       let nsImage = NSImage(data: validImageData) {
                        let size = nsImage.size
                        let sizeInKB = validImageData.count / 1024
                        let format = detectImageFormat(data: validImageData)
                        menuItem.toolTip = "图片：\(Int(size.width)) × \(Int(size.height)) 像素\n格式：\(format)\n大小：\(sizeInKB) KB"
                    } else {
                        menuItem.toolTip = "图片（数据验证失败）"
                    }
                } else {
                    let truncatedContent = item.content.count > 100 ? 
                        String(item.content.prefix(100)) + "..." : item.content
                    menuItem.toolTip = truncatedContent
                }
                
                // 根据类型设置图标或图片预览，使用哈希验证确保数据一致性
                if item.type == .image {
                    // 使用哈希验证获取正确的图片数据
                    let itemHash = ClipboardManager.shared.createItemHash(item)
                    if let validImageData = getValidatedImageData(for: item, expectedHash: itemHash),
                       let nsImage = NSImage(data: validImageData) {
                        // 为图片创建高质量缩略图
                        let thumbnail = createThumbnail(from: nsImage, size: NSSize(width: 24, height: 24))
                        menuItem.image = thumbnail
                        // 创建图片缩略图: \(nsImage.size), 哈希: \(itemHash.prefix(8))
                    } else if let icon = menuIcon(for: item.type) {
                        menuItem.image = icon
                        // 图片数据验证失败，使用默认图标
                    }
                } else if let icon = menuIcon(for: item.type) {
                    menuItem.image = icon
                }
                
                // 为所有9个项目添加数字键快捷键
                let keyEquivalent = "\(index + 1)"
                menuItem.keyEquivalent = keyEquivalent
                menuItem.keyEquivalentModifierMask = []
                
                // 在标题中显示快捷键提示，使用优雅的格式
                let originalTitle = menuTitle(for: item)
                let favoritePrefix = item.isFavorite ? "⭐ " : ""
                menuItem.title = "\(keyEquivalent). \(favoritePrefix)\(originalTitle)"
                
                menu.addItem(menuItem)
            }
            
            // 添加分隔线，使用自定义样式
            let separator = NSMenuItem.separator()
            menu.addItem(separator)
        } else {
            // 如果没有剪贴板项目，显示更友好的提示信息
            let emptyItem = NSMenuItem(title: "📋 暂无剪贴板历史", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            
            // 添加提示子项
            menu.addItem(emptyItem)
            
            let tipItem = NSMenuItem(title: "💡 复制内容后将出现在这里", action: nil, keyEquivalent: "")
            tipItem.isEnabled = false
            tipItem.attributedTitle = NSAttributedString(
                string: "💡 复制内容后将出现在这里",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(tipItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // === 主要功能区域 ===
        // 根据窗口状态动态设置菜单项标题
        // 确保使用现有的主窗口
        if mainWindow == nil {
            // 如果主窗口未设置，从应用中获取第一个窗口
            if let firstWindow = NSApplication.shared.windows.first(where: { $0.title == "OneClip" || $0.className.contains("SwiftUI") }) {
                mainWindow = firstWindow
            }
        }
        
        // 使用与toggleWindow相同的逻辑判断窗口状态
        let isWindowActiveAndVisible = isWindowCurrentlyActiveAndVisible()
        let toggleTitle = isWindowActiveAndVisible ? "隐藏剪贴板窗口" : "显示剪贴板窗口"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleWindow), keyEquivalent: "v")
        toggleItem.keyEquivalentModifierMask = [.command, .control]
        if let toggleIcon = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "Toggle") {
            toggleIcon.size = NSSize(width: 16, height: 16)
            toggleItem.image = toggleIcon
        }
        toggleItem.toolTip = "快捷键: ⌘⌃V"
        menu.addItem(toggleItem)
        
        // 快速粘贴功能已删除
        
        menu.addItem(NSMenuItem.separator())
        
        // === 管理功能区域 ===
        let clearItem = NSMenuItem(title: "清空历史记录", action: #selector(clearClipboardHistory), keyEquivalent: "")
        if let clearIcon = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Clear") {
            clearIcon.size = NSSize(width: 16, height: 16)
            clearItem.image = clearIcon
        }
        clearItem.toolTip = "清空所有剪贴板历史记录"
        menu.addItem(clearItem)
        
        // 添加收藏管理选项
        let favoritesItem = NSMenuItem(title: "管理收藏夹", action: #selector(showFavorites), keyEquivalent: "")
        if let favIcon = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorites") {
            favIcon.size = NSSize(width: 16, height: 16)
            favoritesItem.image = favIcon
        }
        favoritesItem.toolTip = "查看和管理收藏的剪贴板项目"
        
        // 根据收藏夹数量设置菜单项状态
        let favoriteCount = FavoriteManager.shared.favoriteCount
        favoritesItem.isEnabled = favoriteCount > 0
        if favoriteCount == 0 {
            favoritesItem.title = "管理收藏夹（无收藏项）"
        }
        
        menu.addItem(favoritesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // === 设置和信息区域 ===
        let settingsItem = NSMenuItem(title: "偏好设置", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        if let settingsIcon = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings") {
            settingsIcon.size = NSSize(width: 16, height: 16)
            settingsItem.image = settingsIcon
        }
        settingsItem.toolTip = "打开应用设置 (⌘,)"
        menu.addItem(settingsItem)
        
        // 添加权限测试菜单项（调试用）
        #if DEBUG
        menu.addItem(NSMenuItem.separator())
        let permissionTestItem = NSMenuItem(title: "🔧辅助功能授权", action: #selector(testPermissionDialog), keyEquivalent: "")
        permissionTestItem.toolTip = "调试功能：测试辅助功能权限弹窗"
        menu.addItem(permissionTestItem)
        #endif
        
        let aboutItem = NSMenuItem(title: "关于 OneClip", action: #selector(showAbout), keyEquivalent: "")
        if let aboutIcon = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "About") {
            aboutIcon.size = NSSize(width: 16, height: 16)
            aboutItem.image = aboutIcon
        }
        aboutItem.toolTip = "查看应用信息和功能介绍"
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // === 退出区域 ===
        let quitItem = NSMenuItem(title: "退出 OneClip", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        if let quitIcon = NSImage(systemSymbolName: "power.circle.fill", accessibilityDescription: "Quit") {
            quitIcon.size = NSSize(width: 16, height: 16)
            quitItem.image = quitIcon
        }
        quitItem.toolTip = "退出应用 (⌘Q)"
        menu.addItem(quitItem)
        
        // 确保菜单分配给状态栏项目
        if let statusItem = statusItem {
            statusItem.menu = menu
            // 菜单已分配给状态栏项目
        } else {
            // 状态栏项目为空，无法分配菜单
        }
    }
    
    private func menuTitle(for item: ClipboardItem) -> String {
        let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 45
        
        // 为不同类型添加更好的标识
        var description = ""
        
        switch item.type {
        case .image:
            let itemHash = ClipboardManager.shared.createItemHash(item)
            if let validImageData = getValidatedImageData(for: item, expectedHash: itemHash),
               let nsImage = NSImage(data: validImageData) {
                let size = nsImage.size
                let sizeInKB = validImageData.count / 1024
                let sizeUnit = sizeInKB > 1024 ? "\(sizeInKB / 1024) MB" : "\(sizeInKB) KB"
                
                // 检测图片格式
                let format = detectImageFormat(data: validImageData)
                description = "图片 (\(Int(size.width))x\(Int(size.height)), \(format), \(sizeUnit))"
            } else {
                description = "图片（数据无效）"
            }
        case .text:
            let lineCount = content.components(separatedBy: .newlines).count
            if lineCount > 1 {
                description = "\(lineCount)行文本"
            } else if content.count > 50 {
                description = "长文本"
            } else {
                description = content.isEmpty ? "空文本" : content
            }
        case .file:
            description = "文件"
        case .video:
            description = "视频"
        case .audio:
            description = "音频"
        case .document:
            description = "文档"
        case .code:
            description = "代码"
        case .archive:
            description = "压缩包"
        case .executable:
            description = "应用程序"
        }
        
        // 对于非文本类型，使用描述；对于文本，使用内容
        let finalText = item.type == .text ? content : description
        
        if finalText.count > maxLength {
            return String(finalText.prefix(maxLength)) + "..."
        }
        
        return finalText.isEmpty ? "空内容" : finalText
    }
    
    // 新增：检测图片格式的辅助方法
    private func detectImageFormat(data: Data) -> String {
        guard data.count > 8 else { return "未知" }
        
        let bytes = data.prefix(8)
        let header = bytes.map { String(format: "%02X", $0) }.joined()
        
        if header.hasPrefix("89504E47") {
            return "PNG"
        } else if header.hasPrefix("FFD8FF") {
            return "JPEG"
        } else if header.hasPrefix("47494638") {
            return "GIF"
        } else if header.hasPrefix("424D") {
            return "BMP"
        } else if header.hasPrefix("52494646") && data.count > 12 {
            let webpCheck = data[8...11].map { String(format: "%02X", $0) }.joined()
            if webpCheck == "57454250" {
                return "WebP"
            }
        } else if header.hasPrefix("4D4D002A") || header.hasPrefix("49492A00") {
            return "TIFF"
        }
        
        return "未知"
    }
    
    private func menuIcon(for type: ClipboardItemType) -> NSImage? {
        let iconName: String
        let iconSize = NSSize(width: 18, height: 18) // 增加图标尺寸以提高清晰度
        
        switch type {
        case .text:
            iconName = "text.alignleft"
        case .image:
            iconName = "photo.fill"
        case .file:
            iconName = "doc.fill"
        case .video:
            iconName = "video.fill"
        case .audio:
            iconName = "music.note"
        case .document:
            iconName = "doc.text.fill"
        case .code:
            iconName = "chevron.left.forwardslash.chevron.right"
        case .archive:
            iconName = "archivebox.fill"
        case .executable:
            iconName = "app.fill"
        }
        
        if let symbolImage = NSImage(systemSymbolName: iconName, accessibilityDescription: type.displayName) {
            // 创建高质量图标
            let resizedImage = NSImage(size: iconSize)
            resizedImage.lockFocus()
            
            // 设置高质量渲染
            NSGraphicsContext.current?.imageInterpolation = .high
            NSGraphicsContext.current?.shouldAntialias = true
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            
            // 使用适当的颜色和阴影效果
            let color = iconColor(for: type)
            
            // 添加轻微的阴影效果
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.shadowBlurRadius = 0.5
            shadow.set()
            
            // 绘制带颜色的图标
            let coloredImage = symbolImage.withTintColor(color)
            coloredImage.draw(in: NSRect(origin: .zero, size: iconSize))
            
            resizedImage.unlockFocus()
            
            return resizedImage
        }
        
        return nil
    }
    
    // 新增：为不同类型设置不同的图标颜色
    private func iconColor(for type: ClipboardItemType) -> NSColor {
        switch type {
        case .text:
            return NSColor.systemBlue
        case .image:
            return NSColor.systemGreen
        case .file:
            return NSColor.systemGray
        case .video:
            return NSColor.systemPurple
        case .audio:
            return NSColor.systemOrange
        case .document:
            return NSColor.systemBlue
        case .code:
            return NSColor.systemTeal
        case .archive:
            return NSColor.systemYellow
        case .executable:
            return NSColor.systemRed
        }
    }
    
    private func createThumbnail(from image: NSImage, size: NSSize) -> NSImage? {
        // 彻底解决 Dock 隐藏模式下图片预览问题
        return createThumbnailWithFallback(from: image, size: size)
    }
    
    // 新的强化版缩略图创建方法
    private func createThumbnailWithFallback(from image: NSImage, size: NSSize) -> NSImage? {
        // 计算缩略图尺寸，保持宽高比
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            // 图片尺寸无效: \(originalSize)
            return nil
        }
        
        let ratio = min(size.width / originalSize.width, size.height / originalSize.height)
        let targetSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        
        // 创建缩略图: \(originalSize) -> \(targetSize)
        
        // 方案1: 尝试使用 Core Graphics (更可靠)
        if let cgImage = createThumbnailUsingCoreGraphics(from: image, targetSize: targetSize) {
            return cgImage
        }
        
        // 方案2: 尝试强制在主线程创建 (Dock 兼容)
        if let mainThreadImage = createThumbnailOnMainThread(from: image, targetSize: targetSize) {
            return mainThreadImage
        }
        
        // 方案3: 备用简单方案
        return createSimpleThumbnail(from: image, targetSize: targetSize)
    }
    
    // Core Graphics 方案 - 最可靠，不依赖窗口状态
    private func createThumbnailUsingCoreGraphics(from image: NSImage, targetSize: NSSize) -> NSImage? {
        // 获取图像的最佳表示
        guard let imageRep = image.bestRepresentation(for: NSRect(origin: .zero, size: targetSize), 
                                                     context: nil, 
                                                     hints: nil) else {
            // 无法获取图像表示
            return nil
        }
        
        // 创建 CGImage
        guard let cgImage = imageRep.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // 无法创建 CGImage
            return nil
        }
        
        // 使用 Core Graphics 创建缩略图
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(data: nil,
                                    width: Int(targetSize.width),
                                    height: Int(targetSize.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            // 无法创建 CGContext
            return nil
        }
        
        // 高质量缩放
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        
        // 创建结果图像
        if let resultCGImage = context.makeImage() {
            let thumbnail = NSImage(cgImage: resultCGImage, size: targetSize)
            thumbnail.isTemplate = false
            // Core Graphics 缩略图创建成功
            return thumbnail
        }
        
        // Core Graphics 方案失败
        return nil
    }
    
    // 主线程方案 - 强制同步执行
    private func createThumbnailOnMainThread(from image: NSImage, targetSize: NSSize) -> NSImage? {
        var result: NSImage?
        
        // 确保在主线程执行
        if Thread.isMainThread {
            result = createThumbnailSynchronously(from: image, targetSize: targetSize)
        } else {
            DispatchQueue.main.sync {
                result = createThumbnailSynchronously(from: image, targetSize: targetSize)
            }
        }
        
        if result != nil {
            // 主线程缩略图创建成功
        } else {
            // 主线程方案失败
        }
        
        return result
    }
    
    // 同步创建缩略图
    private func createThumbnailSynchronously(from image: NSImage, targetSize: NSSize) -> NSImage? {
        let thumbnail = NSImage(size: targetSize)
        
        // 强制设置图像属性
        thumbnail.cacheMode = .never
        thumbnail.isTemplate = false
        
        // 锁定焦点进行绘制
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }
        
        // 使用高质量渲染
        if let context = NSGraphicsContext.current {
            context.imageInterpolation = .high
            context.shouldAntialias = true
            context.compositingOperation = .copy
        }
        
        // 绘制图像
        image.draw(in: NSRect(origin: .zero, size: targetSize), 
                  from: NSRect(origin: .zero, size: image.size), 
                  operation: .copy, 
                  fraction: 1.0)
        
        return thumbnail
    }
    
    // 简单备用方案
    private func createSimpleThumbnail(from image: NSImage, targetSize: NSSize) -> NSImage? {
        // 最简单的缩放方案，不使用 lockFocus
        let thumbnail = NSImage(size: targetSize)
        
        // 设置图像表示
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(targetSize.width),
                                            pixelsHigh: Int(targetSize.height),
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0)
        
        if let rep = representation {
            thumbnail.addRepresentation(rep)
        }
        
        thumbnail.isTemplate = false
        // 简单缩略图创建成功
        return thumbnail
    }
    
    // 获取经过哈希验证的图片数据
    private func getValidatedImageData(for item: ClipboardItem, expectedHash: String) -> Data? {
        // 菜单预览：开始验证图片数据，期望哈希: \(expectedHash.prefix(8))
        
        // 首先检查内存中的数据
        if let memoryData = item.data,
           NSImage(data: memoryData) != nil {
            // 菜单预览：内存中有有效的图片数据
            return memoryData
        }
        
        // 从磁盘重新加载
        if let filePath = item.filePath {
            let url = URL(fileURLWithPath: filePath)
            if let diskData = try? Data(contentsOf: url),
               NSImage(data: diskData) != nil {
                // 菜单预览：从磁盘加载了有效的图片数据
                return diskData
            }
        }
        
        // 菜单预览：无法获取有效的图片数据
        return nil
    }
    
    @objc private func copyClipboardItem(_ sender: NSMenuItem) {
        let index = sender.tag
        let clipboardItems = ClipboardManager.shared.clipboardItems
        
        if index < clipboardItems.count {
            let item = clipboardItems[index]
            ClipboardManager.shared.copyToClipboard(item: item)
            
            // 显示反馈
            showMenuFeedback("已复制: \(menuTitle(for: item))")
        }
    }
    
    @objc private func clearClipboardHistory(_ sender: AnyObject?) {
        // 显示二次确认对话框
        let alert = NSAlert()
        alert.messageText = "确认清空历史记录"
        alert.informativeText = "此操作将删除所有剪贴板历史记录（收藏项除外），且无法撤销。您确定要继续吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        
        // 设置警告图标
        alert.icon = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Warning")
        
        // 激活应用以确保对话框显示在最前面
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // 用户点击了"清空"按钮
            ClipboardManager.shared.clearAllItems()
            updateStatusBarMenu()
            showMenuFeedback("已清空历史记录")
        }
        // 如果用户点击了"取消"按钮，则不执行任何操作
    }
    
    private func showMenuFeedback(_ message: String) {
        // 移除弹窗提醒，改为静默日志记录
        // [反馈] \(message)
    }
    
    private func showQuickFeedback(_ message: String) {
        // 使用 FeedbackManager 显示反馈
        FeedbackManager.shared.showSuccess(message)
    }
    
    private func setupClipboardMonitoring() {
        // 监听剪贴板变化以更新菜单
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClipboardItemsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarMenu()
        }
        
        // 监听收藏状态变化以更新菜单
        FavoriteManager.shared.$favoriteItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: [ClipboardItem]) in
                self?.updateStatusBarMenu()
            }
            .store(in: &cancellables)
        
        // 监听ESC键或窗口隐藏请求
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HideWindowAndDock"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideWindowAndDock()
        }
        
        // 监听窗口状态变化以更新菜单
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarMenu()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarMenu()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarMenu()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarMenu()
        }
    }
    
    private func setupWindowCloseBehavior() {
        // 监听窗口关闭事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        
        // 监听窗口失去焦点事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }
    
    @objc private func statusItemClicked(_ sender: AnyObject?) {
        // 状态栏图标被点击
        
        // 确保状态栏项目有效
        verifyAndFixStatusBarItem()
        
        guard let statusItem = statusItem, let menu = statusItem.menu else {
            // 状态栏项目或菜单无效
            return
        }
        
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            // 右键显示完整菜单
            // 右键点击，显示完整菜单
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else {
            // 左键执行智能操作：如果有剪贴板历史，直接复制最新的项目；否则显示窗口
            // 左键点击，执行智能操作
            let clipboardItems = ClipboardManager.shared.clipboardItems
            
            if !clipboardItems.isEmpty {
                // 有历史记录，直接复制最新项目
                let latestItem = clipboardItems[0]
                ClipboardManager.shared.copyToClipboard(item: latestItem)
                showQuickFeedback("已复制：\(menuTitle(for: latestItem))")
                // 快速复制最新项目：\(latestItem.content.prefix(20))
            } else {
                // 没有历史记录，显示窗口
                // 无历史记录，显示主窗口
                showMainWindowToFront()
            }
        }
    }
    
    @objc private func toggleWindow(_ sender: AnyObject?) {
        // 立即激活用户活动状态，确保快捷键响应及时
        ClipboardManager.shared.updateUserActivity()
        
        // toggleWindow 被调用
        
        // 确保使用现有的主窗口
        if mainWindow == nil {
            // 如果主窗口未设置，从应用中获取第一个窗口
            if let firstWindow = NSApplication.shared.windows.first(where: { $0.title == "OneClip" || $0.className.contains("SwiftUI") }) {
                mainWindow = firstWindow
                // 找到现有窗口，设置为主窗口
            } else {
                // 未找到现有窗口
                return
            }
        }
        
        guard let window = mainWindow else {
            // 主窗口未设置
            return
        }
        
        // 窗口状态 - 可见: \(window.isVisible), 关键窗口: \(window.isKeyWindow)
        
        if window.isVisible && window.isKeyWindow {
            // 窗口已经可见且是关键窗口，隐藏窗口并隐藏Dock图标
            // 隐藏窗口并隐藏Dock图标
            window.orderOut(nil)
            
            // 延迟隐藏Dock图标，确保窗口完全隐藏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
                // 已切换到后台模式（隐藏Dock图标）
                
                // 更新菜单状态
                self.updateStatusBarMenu()
            }
        } else {
            // 窗口不可见或不是关键窗口，显示窗口并显示Dock图标
            // 显示现有窗口并显示Dock图标
            
            // 首先设置为regular模式，显示Dock图标
            NSApp.setActivationPolicy(.regular)
            // 已切换到regular模式（显示Dock图标）
            
            // 延迟显示窗口，确保应用策略切换完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 强制激活应用到最前面
                NSApp.activate(ignoringOtherApps: true)
                
                // 显示窗口并设为关键窗口
                window.orderFront(nil)
                window.makeKey()
                
                // 更精确的居中判断
                let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
                let windowFrame = window.frame
                let needsRepositioning = !window.isVisible || 
                                       windowFrame.origin.x < screenFrame.minX || 
                                       windowFrame.origin.y < screenFrame.minY ||
                                       windowFrame.maxX > screenFrame.maxX ||
                                       windowFrame.maxY > screenFrame.maxY
                
                if needsRepositioning {
                    window.center()
                }
                
                // 发送通知强制刷新图片预览状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // 延迟更久一点，确保Dock模式切换完全完成
                    let hasImageItems = ClipboardManager.shared.clipboardItems.contains { $0.type == .image }
                    if hasImageItems {
                        NotificationCenter.default.post(name: NSNotification.Name("RefreshImagePreviews"), object: nil)
                        // 已发送图片预览刷新通知
                    }
                }
                
                // 确保搜索框获得焦点
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 发送通知激活搜索框
                    NotificationCenter.default.post(name: NSNotification.Name("ActivateSearchField"), object: nil)
                    // 现有窗口已显示，Dock图标可见，搜索框已激活
                    
                    // 更新菜单状态
                    self.updateStatusBarMenu()
                }
            }
        }
    }
    
    // 隐藏窗口并隐藏Dock图标的方法
    private func hideWindowAndDock() {
        // 执行窗口隐藏和Dock隐藏
        
        let windows = NSApplication.shared.windows
        guard let window = windows.first else {
            // 没有找到窗口
            return
        }
        
        // 隐藏窗口
        window.orderOut(nil)
        
        // 延迟隐藏Dock图标，确保窗口完全隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
            // 窗口已隐藏，Dock图标已隐藏
            
            // 更新菜单状态
            self.updateStatusBarMenu()
        }
    }
    
    // MARK: - 窗口状态检查
    private func isWindowCurrentlyActiveAndVisible() -> Bool {
        guard let window = mainWindow else {
            return false
        }
        // 使用与toggleWindow相同的逻辑：窗口必须既可见又是关键窗口
        return window.isVisible && window.isKeyWindow
    }
    
    // MARK: - 搜索框激活
    private func activateSearchField(_ window: NSWindow) {
        // 通过遍历视图层次结构找到 NSTextField 并激活
        if let contentView = window.contentView {
            activateSearchFieldRecursively(in: contentView)
        }
    }
    
    private func activateSearchFieldRecursively(in view: NSView) {
        // 检查当前视图是否是 NSTextField
        for subview in view.subviews {
            if let textField = subview as? NSTextField {
                // 尝试激活第一个找到的文本字段（通常是搜索框）
                DispatchQueue.main.async {
                    textField.becomeFirstResponder()
                    // 搜索框已激活
                }
                return
            }
            // 递归搜索子视图
            activateSearchFieldRecursively(in: subview)
        }
    }
    
    // 注意：hideWindowSafely 方法已移除，现在使用智能Dock控制
    
    private func showWindowSafely(_ window: NSWindow) {
        let settingsManager = SettingsManager.shared
        
        if settingsManager.showInDock {
            // 显示 Dock 图标模式
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                // 切换到 regular 模式
            }
            
            // 温和地显示窗口，避免强制激活
            window.orderFront(nil)
            window.makeKey()
            
            // 更精确的居中判断
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let windowFrame = window.frame
            let needsRepositioning = !window.isVisible || 
                                   windowFrame.origin.x < screenFrame.minX || 
                                   windowFrame.origin.y < screenFrame.minY ||
                                   windowFrame.maxX > screenFrame.maxX ||
                                   windowFrame.maxY > screenFrame.maxY
            
            if needsRepositioning {
                window.center()
            }
            window.level = .normal
            
            // OneClip 窗口已显示（Dock 图标可见）
            
            // 更新菜单状态
            updateStatusBarMenu()
        } else {
            // 隐藏 Dock 图标模式
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
                // 切换到 accessory 模式
            }
            
            // 在后台模式下显示窗口
            window.setIsVisible(true)
            window.makeKeyAndOrderFront(nil)
            window.center()
            // 直接使用正常级别，避免不必要的级别切换
            window.level = .normal
            
            // 确保窗口能够获得焦点
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.makeKey()
                // OneClip 窗口已显示（Dock 图标隐藏）
                
                // 更新菜单状态
                self.updateStatusBarMenu()
            }
        }
    }
    
    // 新增：显示快速粘贴选择器
    private func showQuickPasteSelector() {
        let clipboardItems = ClipboardManager.shared.clipboardItems
        
        if clipboardItems.isEmpty {
            showQuickFeedback("无剪贴板历史记录")
            return
        }
        
        // 创建选择器弹窗
        let alert = NSAlert()
        alert.messageText = "选择要粘贴的内容 (共\(clipboardItems.count)条历史记录)"
        alert.informativeText = "使用 Cmd+1-9 快速选择复制项目，或点击按钮"
        alert.alertStyle = .informational
        
        // 显示最近的10个剪贴板项目（或全部，如果少于10个）
        let maxItems = min(10, clipboardItems.count)
        for i in 0..<maxItems {
            let item = clipboardItems[i]
            let title = menuTitle(for: item)
            let truncatedTitle = title.count > 50 ? String(title.prefix(50)) + "..." : title
            alert.addButton(withTitle: "[\(i+1)] \(truncatedTitle)")
        }
        
        // 如果有更多项目，添加"查看更多"选项
        if clipboardItems.count > maxItems {
            alert.addButton(withTitle: "查看更多历史 (\(clipboardItems.count - maxItems)条)")
        }
        
        alert.addButton(withTitle: "取消")
        
        // 设置窗口级别确保在最前面
        alert.window.level = .floating
        
        // 显示弹窗并处理选择
        DispatchQueue.main.async {
            let response = alert.runModal()
            
            // 处理前10个快速选择项目
            if response.rawValue >= NSApplication.ModalResponse.alertFirstButtonReturn.rawValue &&
               response.rawValue < NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + maxItems {
                
                let selectedIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                let selectedItem = clipboardItems[selectedIndex]
                
                // 复制选中的内容到剪贴板
                ClipboardManager.shared.copyToClipboard(item: selectedItem)
                
                // 显示反馈
                self.showQuickFeedback("已选择: \(self.menuTitle(for: selectedItem))")
                
                // 延迟模拟粘贴操作
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.simulatePasteOperation()
                }
            }
            // 处理"查看更多历史"选项
            else if clipboardItems.count > maxItems && 
                    response.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + maxItems {
                // 显示完整的剪贴板窗口
                self.toggleWindow(nil)
            }
        }
    }
    
    // 模拟粘贴操作
    private func simulatePasteOperation() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 创建 Cmd+V 组合键事件
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true) // Command 键按下
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)    // V 键按下
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)     // V 键释放
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)  // Command 键释放
        
        // 设置修饰键标志
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        // 发送事件序列
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        
        // 短暂延迟后释放按键
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
        }
        
        // 已执行模拟粘贴操作 (Cmd+V)
    }
    
    @objc private func showSettings(_ sender: AnyObject?) {
        // 显示窗口在最前面
        showMainWindowToFront()
        
        // 通知 ContentView 显示设置
        NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
    }
    
    @objc private func showAbout(_ sender: AnyObject?) {
        // 创建自定义关于窗口
        let aboutWindow = createAboutWindow()
        aboutWindow.makeKeyAndOrderFront(nil)
        aboutWindow.center()
        
        // 设置窗口级别
        aboutWindow.level = .floating
        
        // 激活应用以确保窗口显示在最前面
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createAboutWindow() -> NSWindow {
        let windowSize = NSSize(width: 560, height: 700)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        
        // 创建主容器视图
        let containerView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        containerView.wantsLayer = true
        
        // 创建简洁的纯色背景
        let backgroundLayer = CALayer()
        backgroundLayer.frame = containerView.bounds
        backgroundLayer.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.98).cgColor
        backgroundLayer.cornerRadius = 24
        containerView.layer?.addSublayer(backgroundLayer)
        
        // 添加现代化边框
        let borderLayer = CALayer()
        borderLayer.frame = containerView.bounds
        borderLayer.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        borderLayer.borderWidth = 1.5
        borderLayer.cornerRadius = 24
        containerView.layer?.addSublayer(borderLayer)
        
        // 添加内部高光效果
        let highlightLayer = CALayer()
        highlightLayer.frame = CGRect(x: 1, y: 1, width: windowSize.width - 2, height: windowSize.height - 2)
        highlightLayer.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        highlightLayer.borderWidth = 1
        highlightLayer.cornerRadius = 23
        containerView.layer?.addSublayer(highlightLayer)
        
        // 应用标题 - 居中显示在顶部
        let titleLabel = NSTextField(labelWithString: "OneClip")
        titleLabel.frame = NSRect(x: 20, y: 620, width: windowSize.width - 40, height: 42)
        titleLabel.font = NSFont.systemFont(ofSize: 36, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.textColor = NSColor.labelColor
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        containerView.addSubview(titleLabel)
        
        // 应用图标容器 - 简洁设计
        let iconSize: CGFloat = 96
        let iconContainer = NSView(frame: NSRect(
            x: (windowSize.width - iconSize) / 2,
            y: 510,
            width: iconSize,
            height: iconSize
        ))
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 22
        iconContainer.layer?.shadowColor = NSColor.black.cgColor
        iconContainer.layer?.shadowOpacity = 0.15
        iconContainer.layer?.shadowOffset = CGSize(width: 0, height: 4)
        iconContainer.layer?.shadowRadius = 8
        
        // 应用图标
        let iconImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        if let appIcon = NSApp.applicationIconImage {
            iconImageView.image = appIcon
        }
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 22
        iconImageView.layer?.masksToBounds = true
        
        iconContainer.addSubview(iconImageView)
        containerView.addSubview(iconContainer)
        
        // 副标题 - 简洁设计
        let subtitleLabel = NSTextField(labelWithString: "macOS 智能剪贴板管理器")
        subtitleLabel.frame = NSRect(x: 20, y: 465, width: windowSize.width - 40, height: 28)
        subtitleLabel.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.alignment = .center
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        containerView.addSubview(subtitleLabel)
        
        // 版本信息卡片 - 独立设计，更好的视觉平衡
        let versionCard = createSimpleCard(frame: NSRect(x: 60, y: 380, width: 210, height: 85))
        
        // 版本信息容器 - 居中布局
        let versionContainer = NSView(frame: NSRect(x: 20, y: 20, width: 180, height: 50))
        
        // 版本图标 - 更精美的设计
        let versionIcon = NSTextField(labelWithString: "🏷️")
        versionIcon.frame = NSRect(x: 0, y: 15, width: 30, height: 30)
        versionIcon.font = NSFont.systemFont(ofSize: 22)
        versionIcon.isBezeled = false
        versionIcon.drawsBackground = false
        versionIcon.isEditable = false
        versionIcon.isSelectable = false
        versionContainer.addSubview(versionIcon)
        
        // 版本信息垂直布局
        let versionInfoContainer = NSView(frame: NSRect(x: 40, y: 8, width: 140, height: 40))
        
        // 版本标签
        let versionLabel = NSTextField(labelWithString: "版本")
        versionLabel.frame = NSRect(x: 0, y: 24, width: 140, height: 16)
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = NSColor.secondaryLabelColor
        versionLabel.isBezeled = false
        versionLabel.drawsBackground = false
        versionLabel.isEditable = false
        versionLabel.isSelectable = false
        versionInfoContainer.addSubview(versionLabel)
        
        // 版本号
        let versionNumber = NSTextField(labelWithString: "1.1.0")
        versionNumber.frame = NSRect(x: 0, y: 4, width: 140, height: 22)
        versionNumber.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        versionNumber.textColor = NSColor.systemBlue
        versionNumber.isBezeled = false
        versionNumber.drawsBackground = false
        versionNumber.isEditable = false
        versionNumber.isSelectable = false
        versionInfoContainer.addSubview(versionNumber)
        
        versionContainer.addSubview(versionInfoContainer)
        versionCard.addSubview(versionContainer)
        containerView.addSubview(versionCard)
        
        // 作者信息卡片 - 独立设计，与版本卡片对称
        let authorCard = createSimpleCard(frame: NSRect(x: 290, y: 380, width: 210, height: 85))
        
        // 作者信息容器 - 居中布局
        let authorContainer = NSView(frame: NSRect(x: 20, y: 20, width: 180, height: 50))
        
        // 作者图标 - 更精美的设计
        let authorIcon = NSTextField(labelWithString: "👨‍💻")
        authorIcon.frame = NSRect(x: 0, y: 15, width: 30, height: 30)
        authorIcon.font = NSFont.systemFont(ofSize: 22)
        authorIcon.isBezeled = false
        authorIcon.drawsBackground = false
        authorIcon.isEditable = false
        authorIcon.isSelectable = false
        authorContainer.addSubview(authorIcon)
        
        // 作者信息垂直布局
        let authorInfoContainer = NSView(frame: NSRect(x: 40, y: 8, width: 140, height: 40))
        
        // 作者标签
        let authorTitleLabel = NSTextField(labelWithString: "作者")
        authorTitleLabel.frame = NSRect(x: 0, y: 24, width: 140, height: 16)
        authorTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        authorTitleLabel.textColor = NSColor.secondaryLabelColor
        authorTitleLabel.isBezeled = false
        authorTitleLabel.drawsBackground = false
        authorTitleLabel.isEditable = false
        authorTitleLabel.isSelectable = false
        authorInfoContainer.addSubview(authorTitleLabel)
        
        // 作者名称 - 添加点击跳转功能
        let authorName = NSButton(frame: NSRect(x: 0, y: 4, width: 140, height: 22))
        authorName.title = "Wcowin"
        authorName.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        authorName.isBordered = false
        authorName.target = self
        authorName.action = #selector(openWcowinWebsite)
        authorName.wantsLayer = true
        authorName.layer?.cornerRadius = 6
        
        let authorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.systemPurple,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        authorName.attributedTitle = NSAttributedString(string: "Wcowin", attributes: authorAttributes)
        authorInfoContainer.addSubview(authorName)
        
        authorContainer.addSubview(authorInfoContainer)
        authorCard.addSubview(authorContainer)
        containerView.addSubview(authorCard)
        
        // 联系方式信息卡片 - 重新设计，更好的视觉层次
        let contactCard = createSimpleCard(frame: NSRect(x: 60, y: 270, width: 440, height: 95))
        
        // 联系方式标题 - 居中设计，增加视觉重点
        let contactTitle = NSTextField(labelWithString: "💬 联系方式")
        contactTitle.frame = NSRect(x: 25, y: 70, width: 390, height: 22)
        contactTitle.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        contactTitle.textColor = NSColor.labelColor
        contactTitle.isBezeled = false
        contactTitle.drawsBackground = false
        contactTitle.isEditable = false
        contactTitle.isSelectable = false
        contactCard.addSubview(contactTitle)
        
        // 邮箱信息容器 - 重新布局，更好的对齐
        let emailContainer = NSView(frame: NSRect(x: 35, y: 40, width: 370, height: 25))
        
        // 邮箱图标 - 更大更清晰
        let emailIcon = NSTextField(labelWithString: "📧")
        emailIcon.frame = NSRect(x: 0, y: 4, width: 24, height: 24)
        emailIcon.font = NSFont.systemFont(ofSize: 18)
        emailIcon.isBezeled = false
        emailIcon.drawsBackground = false
        emailIcon.isEditable = false
        emailIcon.isSelectable = false
        emailContainer.addSubview(emailIcon)
        
        // 邮箱信息 - 更好的视觉效果
        let emailInfo = NSButton(frame: NSRect(x: 35, y: 2, width: 200, height: 28))
        emailInfo.title = "wcowin@qq.com"
        emailInfo.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        emailInfo.isBordered = false
        emailInfo.target = self
        emailInfo.action = #selector(openEmail)
        emailInfo.wantsLayer = true
        emailInfo.layer?.cornerRadius = 8
        emailInfo.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1).cgColor
        
        let emailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.systemBlue
        ]
        emailInfo.attributedTitle = NSAttributedString(string: "wcowin@qq.com", attributes: emailAttributes)
        emailContainer.addSubview(emailInfo)
        contactCard.addSubview(emailContainer)
        
        // GitHub信息容器 - 重新布局，与邮箱对齐
        let githubContainer = NSView(frame: NSRect(x: 35, y: 10, width: 370, height: 25))
        
        // GitHub图标 - 更大更清晰
        let githubIcon = NSTextField(labelWithString: "🌐")
        githubIcon.frame = NSRect(x: 0, y: 4, width: 24, height: 24)
        githubIcon.font = NSFont.systemFont(ofSize: 18)
        githubIcon.isBezeled = false
        githubIcon.drawsBackground = false
        githubIcon.isEditable = false
        githubIcon.isSelectable = false
        githubContainer.addSubview(githubIcon)
        
        // GitHub信息 - 更好的视觉效果
        let githubInfo = NSButton(frame: NSRect(x: 35, y: 2, width: 280, height: 28))
        githubInfo.title = "github.com/wcowin/OneClip"
        githubInfo.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        githubInfo.isBordered = false
        githubInfo.target = self
        githubInfo.action = #selector(openGitHub)
        githubInfo.wantsLayer = true
        githubInfo.layer?.cornerRadius = 8
        githubInfo.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
        
        let githubAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.systemGreen
        ]
        githubInfo.attributedTitle = NSAttributedString(string: "github.com/wcowin/OneClip", attributes: githubAttributes)
        githubContainer.addSubview(githubInfo)
        contactCard.addSubview(githubContainer)
        
        containerView.addSubview(contactCard)
        
        // 功能特性卡片 - 简洁设计，增加间距
        let featuresCard = createSimpleCard(frame: NSRect(x: 60, y: 160, width: 440, height: 95))
        
        // 功能特性标题 - 增加内边距
        let featuresTitle = NSTextField(labelWithString: "✨ 核心功能")
        featuresTitle.frame = NSRect(x: 28, y: 75, width: 400, height: 22)
        featuresTitle.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        featuresTitle.textColor = NSColor.labelColor
        featuresTitle.isBezeled = false
        featuresTitle.drawsBackground = false
        featuresTitle.isEditable = false
        featuresTitle.isSelectable = false
        featuresCard.addSubview(featuresTitle)
        
        // 功能列表 - 更好的排版
        let features = [
            "• 智能剪贴板历史记录管理",
            "• 支持文本、图片、文件等多种格式",
            "• 收藏功能，重要内容永不丢失",
            "• 实时搜索和分类筛选"
        ]
        
        for (index, feature) in features.enumerated() {
            let featureLabel = NSTextField(labelWithString: feature)
            featureLabel.frame = NSRect(x: 32, y: 50 - index * 16, width: 420, height: 16)
            featureLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            featureLabel.textColor = NSColor.secondaryLabelColor
            featureLabel.isBezeled = false
            featureLabel.drawsBackground = false
            featureLabel.isEditable = false
            featureLabel.isSelectable = false
            featuresCard.addSubview(featureLabel)
        }
        
        containerView.addSubview(featuresCard)
        
        // 快捷键卡片 - 简洁设计，增加间距
        let shortcutsCard = createSimpleCard(frame: NSRect(x: 60, y: 50, width: 440, height: 95))
        
        // 快捷键标题 - 增加内边距
        let shortcutsTitle = NSTextField(labelWithString: "⌨️ 快捷键")
        shortcutsTitle.frame = NSRect(x: 28, y: 70, width: 400, height: 22)
        shortcutsTitle.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        shortcutsTitle.textColor = NSColor.labelColor
        shortcutsTitle.isBezeled = false
        shortcutsTitle.drawsBackground = false
        shortcutsTitle.isEditable = false
        shortcutsTitle.isSelectable = false
        shortcutsCard.addSubview(shortcutsTitle)
        
        // 快捷键列表 - 现代化设计
        let shortcuts = [
            "⌘ + ^ + V - 显示/隐藏剪贴板窗口",
            "⌘ + Q - 退出应用"
        ]
        
        for (index, shortcut) in shortcuts.enumerated() {
            let shortcutLabel = NSTextField(labelWithString: shortcut)
            shortcutLabel.frame = NSRect(x: 32, y: 45 - index * 20, width: 420, height: 16)
            shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            shortcutLabel.textColor = NSColor.secondaryLabelColor
            shortcutLabel.isBezeled = false
            shortcutLabel.drawsBackground = false
            shortcutLabel.isEditable = false
            shortcutLabel.isSelectable = false
            shortcutsCard.addSubview(shortcutLabel)
        }
        
        containerView.addSubview(shortcutsCard)
        
        // 底部标语 - 简洁设计
        let sloganLabel = NSTextField(labelWithString: "🎯 让您的剪贴板更智能，工作更高效！")
        sloganLabel.frame = NSRect(x: 20, y: 20, width: windowSize.width - 40, height: 28)
        sloganLabel.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        sloganLabel.alignment = .center
        sloganLabel.textColor = NSColor.systemBlue
        sloganLabel.isBezeled = false
        sloganLabel.drawsBackground = false
        sloganLabel.isEditable = false
        sloganLabel.isSelectable = false
        
        containerView.addSubview(sloganLabel)
        
        // 确定按钮已删除 - 用户可以通过右上角关闭按钮或点击窗口外部关闭
        
        // 添加关闭按钮（右上角）- 简洁设计
        let closeButtonSize: CGFloat = 32
        let closeButtonMargin: CGFloat = 20
        let closeButton = NSButton(frame: NSRect(
            x: windowSize.width - closeButtonSize - closeButtonMargin,
            y: windowSize.height - closeButtonSize - closeButtonMargin,
            width: closeButtonSize,
            height: closeButtonSize
        ))
        closeButton.title = ""
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeAboutWindow(_:))
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
        closeButton.layer?.cornerRadius = closeButtonSize / 2
        closeButton.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
        closeButton.layer?.borderWidth = 1
        
        let trackingArea = NSTrackingArea(
            rect: closeButton.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: closeButton,
            userInfo: nil
        )
        closeButton.addTrackingArea(trackingArea)
        
        // 关闭按钮图标 - 简洁设计
        let closeIcon = NSTextField(labelWithString: "✕")
        let closeIconSize: CGFloat = 16
        closeIcon.frame = NSRect(
            x: (closeButtonSize - closeIconSize) / 2,
            y: (closeButtonSize - closeIconSize) / 2 - 1,
            width: closeIconSize,
            height: closeIconSize
        )
        closeIcon.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        closeIcon.textColor = NSColor.systemRed
        closeIcon.isBezeled = false
        closeIcon.drawsBackground = false
        closeIcon.isEditable = false
        closeIcon.isSelectable = false
        closeIcon.alignment = .center
        
        closeButton.addSubview(closeIcon)
        containerView.addSubview(closeButton)
        
        window.contentView = containerView
        return window
    }
    
    // 创建简洁卡片的辅助方法
    private func createSimpleCard(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        
        // 简洁的纯色背景
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        card.layer?.cornerRadius = 12
        
        // 简单的边框
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        card.layer?.borderWidth = 1
        
        // 轻微的阴影
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.08
        card.layer?.shadowOffset = CGSize(width: 0, height: 2)
        card.layer?.shadowRadius = 4
        
        return card
    }
    
    // 创建现代化卡片的辅助方法
    private func createModernCard(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        
        // 主背景
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        card.layer?.cornerRadius = 16
        
        // 添加渐变边框
        let gradientBorder = CAGradientLayer()
        gradientBorder.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        gradientBorder.colors = [
            NSColor.systemBlue.withAlphaComponent(0.15).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.1).cgColor
        ]
        gradientBorder.cornerRadius = 16
        gradientBorder.borderWidth = 1.5
        gradientBorder.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        card.layer?.addSublayer(gradientBorder)
        
        // 添加内部高光
        let highlight = CALayer()
        highlight.frame = CGRect(x: 1, y: 1, width: frame.width - 2, height: frame.height - 2)
        highlight.cornerRadius = 15
        highlight.borderWidth = 1
        highlight.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        card.layer?.addSublayer(highlight)
        
        // 添加轻微阴影
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.1
        card.layer?.shadowOffset = CGSize(width: 0, height: 2)
        card.layer?.shadowRadius = 8
        
        return card
    }
    
    // 创建精美卡片的辅助方法
    private func createPremiumCard(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        
        // 主背景 - 更精美的渐变
        let backgroundGradient = CAGradientLayer()
        backgroundGradient.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        backgroundGradient.colors = [
            NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor,
            NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        ]
        backgroundGradient.startPoint = CGPoint(x: 0, y: 0)
        backgroundGradient.endPoint = CGPoint(x: 0, y: 1)
        backgroundGradient.cornerRadius = 18
        card.layer?.addSublayer(backgroundGradient)
        
        // 添加精美的边框渐变
        let borderGradient = CAGradientLayer()
        borderGradient.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        borderGradient.colors = [
            NSColor.systemBlue.withAlphaComponent(0.2).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.15).cgColor,
            NSColor.systemTeal.withAlphaComponent(0.1).cgColor
        ]
        borderGradient.cornerRadius = 18
        borderGradient.borderWidth = 2
        borderGradient.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        card.layer?.addSublayer(borderGradient)
        
        // 添加内部高光效果
        let innerHighlight = CALayer()
        innerHighlight.frame = CGRect(x: 2, y: 2, width: frame.width - 4, height: frame.height - 4)
        innerHighlight.cornerRadius = 16
        innerHighlight.borderWidth = 1
        innerHighlight.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        card.layer?.addSublayer(innerHighlight)
        
        // 添加精美的阴影
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.15
        card.layer?.shadowOffset = CGSize(width: 0, height: 4)
        card.layer?.shadowRadius = 12
        
        // 添加微妙的内阴影效果
        let innerShadow = CALayer()
        innerShadow.frame = CGRect(x: 1, y: 1, width: frame.width - 2, height: frame.height - 2)
        innerShadow.cornerRadius = 17
        innerShadow.shadowColor = NSColor.black.cgColor
        innerShadow.shadowOpacity = 0.05
        innerShadow.shadowOffset = CGSize(width: 0, height: -1)
        innerShadow.shadowRadius = 2
        card.layer?.addSublayer(innerShadow)
        
        return card
    }
    
    @objc private func openEmail() {
        if let url = URL(string: "mailto:wcowin@qq.com") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/wcowin/OneClip") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openWcowinWebsite() {
        if let url = URL(string: "https://wcowin.work/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func closeAboutWindow(_ sender: NSButton) {
        sender.window?.close()
    }
    
    
    // 注意：toggleDock 方法已移除，现在使用智能Dock控制
    // 通过 toggleWindow 和 hideWindowAndDock 方法来控制Dock显示状态
    
    @objc private func quitApp(_ sender: AnyObject?) {
        // 首先激活应用窗口到最前面
        // 准备退出应用，激活窗口到最前面
        
        // 确保应用策略正确，但避免强制激活
        NSApp.setActivationPolicy(.regular)
        
        // 关闭可能打开的设置面板，避免挡住确认弹窗
        closeSettingsPanel()
        
        // 确保有可见的窗口来显示确认弹窗
        var targetWindow: NSWindow?
        
        // 首先尝试使用现有的主窗口
        if let window = mainWindow ?? NSApplication.shared.windows.first {
            // 只在窗口不可见时才激活
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                // 窗口已可见，只需确保在前台
                window.orderFront(nil)
            }
            targetWindow = window
            // 使用现有窗口显示确认弹窗
        } else {
            // 如果没有窗口，先显示主窗口
            // 没有可见窗口，先显示主窗口
            showMainWindowToFront()
            
            // 等待窗口显示完成后获取窗口引用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                targetWindow = self.mainWindow ?? NSApplication.shared.windows.first
                self.showQuitConfirmationDialog(with: targetWindow)
                return
            }
            return
        }
        
        // 显示二次确认弹窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showQuitConfirmationDialog(with: targetWindow)
        }
    }
    
    // 显示退出确认对话框
    private func showQuitConfirmationDialog(with parentWindow: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "确认退出 OneClip？"
        alert.informativeText = "退出后将停止剪贴板监控，您确定要退出应用吗？"
        alert.alertStyle = .warning
        
        // 添加按钮
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        
        // 设置默认按钮为取消
        alert.buttons[1].keyEquivalent = "\r" // Enter键对应取消
        alert.buttons[0].keyEquivalent = "" // 退出按钮不设置快捷键
        
        // 设置弹窗图标
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        if let window = parentWindow {
            // 使用 beginSheetModal 异步显示弹窗
            // 使用工作表模式显示确认弹窗
            alert.beginSheetModal(for: window) { [weak self] response in
                DispatchQueue.main.async {
                    if response == .alertFirstButtonReturn {
                        // 用户选择退出
                        // 用户确认退出应用
                        self?.performActualQuit()
                    } else {
                        // 用户选择取消
                        // 用户取消退出操作
                    }
                }
            }
        } else {
            // 如果没有父窗口，使用独立弹窗模式
            // 没有找到父窗口，使用独立弹窗模式
            
            // 确保弹窗在最前面并且可见
            alert.window.level = .modalPanel
            
            // 只在必要时居中弹窗
            let alertWindow = alert.window
            if alertWindow.frame.origin.x < 0 || alertWindow.frame.origin.y < 0 {
                alertWindow.center()
            }
            
            // 使用异步方式显示独立弹窗
            DispatchQueue.main.async {
                let response = alert.runModal()
                
                if response == .alertFirstButtonReturn {
                    // 用户选择退出
                    // 用户确认退出应用
                    self.performActualQuit()
                } else {
                    // 用户选择取消
                    // 用户取消退出操作
                }
            }
        }
    }
    
    // 关闭设置面板
    private func closeSettingsPanel() {
        // 检查并关闭设置面板
        
        // 发送通知来关闭设置面板
        NotificationCenter.default.post(name: NSNotification.Name("CloseSettingsPanel"), object: nil)
        
        // 关闭所有工作表（sheet）
        for window in NSApplication.shared.windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
                // 关闭了工作表窗口
            }
        }
    }
    
    // 执行实际的退出操作
    private func performActualQuit() {
        // 执行应用退出流程
        
        // 注销全局快捷键
        hotkeyManager = nil
        
        // 停止权限监控
        stopPermissionMonitoring()
        
        // 停止状态栏监控
        stopStatusBarMonitoring()
        
        // 终止应用
        NSApp.terminate(nil)
    }
    
    // MARK: - 调试和测试方法
    
    @objc private func testPermissionDialog() {
        print("🔧 [TEST] 用户点击了权限测试菜单")
        // 强制激活应用到最前面
        NSApp.activate(ignoringOtherApps: true)
        
        // 临时清除权限缓存，模拟首次启动或权限丢失的情况
        permissionCache = false
        lastPermissionCheck = Date.distantPast
        forceShowPermissionDialog()
    }
    
    // MARK: - 应用激活处理
    func applicationDidBecomeActive(_ notification: Notification) {
        // 应用重新激活，清除 badge 数量
        
        // 清除未读计数和 badge 数量
        ClipboardManager.shared.clearUnreadCount()
        
        // 确保状态栏图标可见
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.verifyAndFixStatusBarItem()
        }
    }
    
    // MARK: - 快速操作功能
    
    private func performQuickPaste() {
        // 立即激活用户活动状态，确保快速粘贴响应及时
        ClipboardManager.shared.updateUserActivity()
        
        let clipboardItems = ClipboardManager.shared.clipboardItems
        
        if !clipboardItems.isEmpty {
            let latestItem = clipboardItems[0]
            ClipboardManager.shared.copyToClipboard(item: latestItem)
            showQuickFeedback("快速粘贴: \(menuTitle(for: latestItem))")
            // 快速粘贴最新项目
        } else {
            showQuickFeedback("无历史记录可粘贴")
            // 快速粘贴失败：无历史记录
        }
    }
    

    
    // performQuickPasteAction方法已删除，因为快速粘贴功能已移除
    
    @objc private func showFavorites(_ sender: AnyObject?) {
        // 强制激活应用到最前面
        NSApp.activate(ignoringOtherApps: true)
        
        // 显示窗口在最前面
        showMainWindowToFront()
        
        // 通知 ContentView 显示收藏夹标签页
        NotificationCenter.default.post(name: NSNotification.Name("ShowFavorites"), object: nil)
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        // 当主窗口关闭时，保持 dock 图标显示，不立即切换到后台模式
        _ = notification.object as? NSWindow // 移除未使用变量警告
        
        // 窗口正在关闭，保持 dock 图标显示
        
        // 不再自动切换到 accessory 模式，让用户通过菜单栏控制
    }
    
    @objc private func windowDidResignKey(_ notification: Notification) {
        // 当窗口失去焦点时，保持 dock 图标显示
        _ = notification.object as? NSWindow // 移除未使用变量警告
        
        // 窗口失去焦点，保持 dock 图标显示
        
        // 不再因为失去焦点就隐藏 dock 图标
    }
    
    // MARK: - 窗口管理优化
    
    // 注意：handleDockToggle 方法已移除，现在使用智能Dock控制
    // 通过 toggleWindow 和 hideWindowAndDock 方法来控制Dock显示状态
    
    func showMainWindow() {
        showMainWindowToFront()
    }
    
    private func showMainWindowToFront() {
        // 显示主窗口到最前面
        
        // 始终显示Dock图标当窗口被显示时
        NSApp.setActivationPolicy(.regular)
        
        // 确保使用现有的主窗口
        if mainWindow == nil {
            if let firstWindow = NSApplication.shared.windows.first(where: { $0.title == "OneClip" || $0.className.contains("SwiftUI") }) {
                mainWindow = firstWindow
                // 找到现有窗口，设置为主窗口
            }
        }
        
        if let window = mainWindow {
            // 延迟激活窗口，确保应用策略切换完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 只在窗口不可见或位置异常时才居中
                if !window.isVisible || window.frame.origin.x < 0 || window.frame.origin.y < 0 {
                    window.center()
                }
                
                // 温和地显示窗口，避免强制激活
                window.orderFront(nil)
                window.makeKey()
                window.level = .normal
                
                // 显示现有主窗口，Dock图标已显示
                
                // 更新菜单状态
                self.updateStatusBarMenu()
            }
        } else {
            // 无法找到主窗口
        }
    }
    
    // MARK: - Carbon 事件处理
    
    func handleCarbonEvent(event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        
        var eventHotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            OSType(kEventParamDirectObject),
            OSType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )
        
        if result == noErr {
            // 检查是否是我们的热键ID
            if eventHotKeyID.signature == fourCharCodeFrom("MACP") && eventHotKeyID.id == 1001 {
                // Carbon热键触发: Cmd+Shift+V
                DispatchQueue.main.async { [weak self] in
                    self?.toggleWindow(nil)
                }
                return noErr
            }
        }
        
        return OSStatus(eventNotHandledErr)
    }
    
    private func fourCharCodeFrom(_ string: String) -> OSType {
        let chars = Array(string.utf8)
        return OSType(chars[0]) << 24 |
               OSType(chars[1]) << 16 |
               OSType(chars[2]) << 8 |
               OSType(chars[3])
    }
    
    // MARK: - 全局快捷键管理
    
    /// 优化的权限检查方法，减少延迟
    private func checkPermissionOptimized() -> Bool {
        // 使用缓存减少重复检查
        let now = Date()
        if let cached = permissionCache,
           now.timeIntervalSince(lastPermissionCheck) < permissionCacheValidDuration {
            return cached
        }
        
        let permission = AXIsProcessTrusted()
        permissionCache = permission
        lastPermissionCheck = now
        return permission
    }
    
    /// 异步权限检查，避免阻塞主线程
    private func checkPermissionAsync(completion: @escaping (Bool) -> Void) {
        // 先检查缓存
        let now = Date()
        if let cached = permissionCache,
           now.timeIntervalSince(lastPermissionCheck) < permissionCacheValidDuration {
            completion(cached)
            return
        }
        
        // 在后台线程检查权限
        DispatchQueue.global(qos: .utility).async {
            let permission = AXIsProcessTrusted()
            
            DispatchQueue.main.async {
                self.permissionCache = permission
                self.lastPermissionCheck = Date()
                completion(permission)
            }
        }
    }
    
    private func setupGlobalHotkey() {
        print("🔍 [DEBUG] setupGlobalHotkey 开始执行")
        
        // 确保在主线程上执行
        DispatchQueue.main.async {
            print("🔍 [DEBUG] 在主线程中创建 HotkeyManager 实例")
            // 创建 HotkeyManager 实例
            self.hotkeyManager = HotkeyManager()
            
            // 使用优化的权限检查
            print("🔍 [DEBUG] 开始异步权限检查")
            self.checkPermissionAsync { [weak self] hasPermission in
                guard let self = self else { return }
                
                print("🔍 [DEBUG] setupGlobalHotkey 权限检查结果: \(hasPermission)")
                
                // 设置全局快捷键，传递必要的依赖项
                print("🔍 [DEBUG] 设置全局快捷键")
                self.hotkeyManager?.setupGlobalHotkeys(
                    onToggleWindow: { [weak self] in
                        guard let self = self else { return }
                        // 热键触发 - 显示/隐藏主窗口 (Cmd+Ctrl+V)
                        DispatchQueue.main.async {
                            self.toggleWindow(nil)
                        }
                    },
                    clipboardManager: ClipboardManager.shared,
                    windowManager: nil // WindowManager 将在需要时传递
                )
                
                print("✅ [DEBUG] 全局热键设置完成: Cmd+Ctrl+V")
                
                // 如果没有权限，请求权限（集中处理）
                if !hasPermission {
                    print("🔍 [DEBUG] 权限不足，调用 requestAccessibilityPermissions")
                    self.requestAccessibilityPermissions()
                } else {
                    print("✅ [DEBUG] 权限已获得，无需请求权限")
                }
                
                // 延迟验证快捷键注册状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    print("🔍 [DEBUG] 开始验证快捷键注册状态")
                    self?.verifyHotkeyRegistration()
                }
            }
        }
    }
    
    // MARK: - 快捷键验证
    
    private func verifyHotkeyRegistration() {
        // 验证快捷键注册状态...
        
        self.checkPermissionAsync { hasPermission in
            let _ = self.hotkeyManager != nil
            
            // HotkeyManager 实例状态检查
            // 辅助功能权限状态检查
            
            if !hasPermission {
                // 快捷键将仅在当前应用中工作，需要权限才能在所有应用中使用
            }
            
            // 测试提示: 请尝试按 Cmd+Ctrl+V 显示主窗口
        }
    }
    
    private func requestAccessibilityPermissions() {
        print("🔍 [DEBUG] requestAccessibilityPermissions 开始执行")
        
        // 防止重复检查权限
        if isCheckingPermissions {
            print("⚠️ [DEBUG] 权限检查正在进行中，跳过重复检查")
            return
        }
        
        // 检查用户是否选择了不再提示（这是唯一应该阻止弹窗的条件）
        let disablePrompt = UserDefaults.standard.bool(forKey: "DisableAccessibilityPrompt")
        print("🔍 [DEBUG] DisableAccessibilityPrompt 设置: \(disablePrompt)")
        if disablePrompt {
            print("⚠️ [DEBUG] 用户已选择不再提示辅助功能权限，退出")
            return
        }
        
        print("🔍 [DEBUG] 开始权限检查流程")
        isCheckingPermissions = true
        defer { 
            isCheckingPermissions = false
            print("🔍 [DEBUG] 权限检查流程结束")
        }
        
        // 使用优化的权限检查
        checkPermissionAsync { accessEnabled in
            print("🔍 [DEBUG] 权限检查结果: \(accessEnabled)")
            if !accessEnabled {
                print("🔍 [DEBUG] 需要辅助功能权限，准备显示弹窗")
                // 需要辅助功能权限
                self.hasShownPermissionAlert = true
                self.wasAccessibilityDenied = true
                
                // 获取设置管理器
                let settingsManager = SettingsManager.shared
                print("🔍 [DEBUG] isFirstLaunch: \(settingsManager.isFirstLaunch)")
                
                // 确保状态栏图标在权限检查期间保持可见
                DispatchQueue.main.async {
                    self.verifyAndFixStatusBarItem()
                }
                
                // 启动权限监控
                self.startPermissionMonitoring()
                
                // 延迟显示权限提示，避免影响状态栏显示
                let delay = settingsManager.isFirstLaunch ? 2.0 : 0.5 // 减少延迟时间
                print("🔍 [DEBUG] 将在 \(delay) 秒后显示权限弹窗")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    print("🔍 [DEBUG] 延迟时间到，开始最终权限检查")
                    // 简化权限弹窗条件检查
                    self.checkPermissionAsync { hasPermission in
                        print("🔍 [DEBUG] 最终权限检查结果: \(hasPermission)")
                        if !hasPermission {
                            print("🔍 [DEBUG] 准备显示权限弹窗，isFirstLaunch: \(settingsManager.isFirstLaunch)")
                            // 直接显示权限弹窗，不进行过多的状态检查
                            self.showPermissionAlert(isFirstLaunch: settingsManager.isFirstLaunch)
                        } else {
                            print("🔍 [DEBUG] 权限已获得，不显示弹窗")
                        }
                        
                        // 权限弹窗后再次确保状态栏图标可见
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.verifyAndFixStatusBarItem()
                        }
                    }
                }
            } else {
                // 辅助功能权限已获得
                print("✅ [DEBUG] 辅助功能权限已获得，不需要显示弹窗")
                self.hasShownPermissionAlert = false
                self.wasAccessibilityDenied = false
                
                // 如果权限已获得，清除"不再提示"设置，以便将来权限丢失时能再次提醒
                UserDefaults.standard.removeObject(forKey: "DisableAccessibilityPrompt")
                
                // 停止权限监控
                self.stopPermissionMonitoring()
            }
        }
    }
    
    private func showPermissionAlert(isFirstLaunch: Bool = false) {
        print("🔍 [DEBUG] showPermissionAlert 开始执行，isFirstLaunch: \(isFirstLaunch)")
        
        // 全局弹窗状态检查
        if AppDelegate.isPermissionDialogShowing {
            print("⚠️ [DEBUG] 权限弹窗正在显示中，跳过重复弹窗")
            return
        }
        
        // 冷却时间检查
        let currentTime = Date()
        let timeSinceLastDialog = currentTime.timeIntervalSince(AppDelegate.lastPermissionDialogTime)
        if timeSinceLastDialog < AppDelegate.permissionDialogCooldown {
            print("⚠️ [DEBUG] 权限弹窗冷却时间未到（剩余\(Int(AppDelegate.permissionDialogCooldown - timeSinceLastDialog))秒），跳过弹窗")
            return
        }
        
        // 确保在主线程执行
        DispatchQueue.main.async {
            print("🔍 [DEBUG] 在主线程中执行权限弹窗显示")
            
            // 再次检查全局弹窗状态（防止竞态条件）
            if AppDelegate.isPermissionDialogShowing {
                print("⚠️ [DEBUG] 权限弹窗正在显示中（二次检查），跳过重复弹窗")
                return
            }
            
            // 基本权限检查：如果已有权限则不显示弹窗
            let currentPermission = AXIsProcessTrusted()
            print("🔍 [DEBUG] 当前权限状态: \(currentPermission)")
            guard !currentPermission else {
                print("⚠️ [DEBUG] 权限已获得，取消弹窗显示")
                return
            }
            
            // 检查用户是否选择了不再提示
            let disablePrompt = UserDefaults.standard.bool(forKey: "DisableAccessibilityPrompt")
            print("🔍 [DEBUG] 不再提示设置: \(disablePrompt), isFirstLaunch: \(isFirstLaunch)")
            if !isFirstLaunch && disablePrompt {
                print("⚠️ [DEBUG] 用户已选择不再提示，取消弹窗")
                return
            }
            
            // 简化检查：只检查是否有其他模态窗口
            let hasModalWindow = NSApp.modalWindow != nil
            print("🔍 [DEBUG] 是否有模态窗口: \(hasModalWindow)")
            if hasModalWindow {
                print("⚠️ [DEBUG] 有其他模态窗口，延迟1秒后重试")
                // 有其他模态窗口，延迟显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showPermissionAlert(isFirstLaunch: isFirstLaunch)
                }
                return
            }
            
            // 设置全局弹窗状态
            AppDelegate.isPermissionDialogShowing = true
            AppDelegate.lastPermissionDialogTime = Date()
            
            print("✅ [DEBUG] 开始创建权限弹窗")
            // 暂时停止全局点击监听，避免弹窗期间的误操作
            NotificationCenter.default.post(name: NSNotification.Name("PreventAutoHide"), object: true)
            
            let alert = NSAlert()
            
            if isFirstLaunch {
                // 首次启动的友好提示
                alert.messageText = "欢迎使用 OneClip！"
                alert.informativeText = """
                🎉 感谢您选择 OneClip 剪贴板管理器！
                
                为了让您体验完整功能，我们需要申请辅助功能权限：
                
                ✅ 基本功能：菜单栏图标和剪贴板管理已可正常使用
                🚀 增强功能：全局快捷键 (Cmd+Ctrl+V) 需要此权限
                
                权限用途：仅用于注册全局快捷键，不会访问任何敏感信息
                授权步骤：系统设置 → 隐私与安全性 → 辅助功能 → 添加 OneClip
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "立即授权")
                alert.addButton(withTitle: "稍后设置")
                alert.addButton(withTitle: "跳过（不使用快捷键）")
            } else {
                // 非首次启动的标准提示
                alert.messageText = "全局快捷键功能需要权限"
                alert.informativeText = """
                OneClip 需要辅助功能权限才能使用全局快捷键 (Cmd+Ctrl+V)。
                
                • 基本功能正常：菜单栏图标和剪贴板管理不受影响
                • 如需使用全局快捷键，请点击"授权"打开系统设置
                
                授权步骤：系统设置 → 隐私与安全性 → 辅助功能 → 添加 OneClip
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "授权")
                alert.addButton(withTitle: "稍后")
                alert.addButton(withTitle: "不再提示")
            }
            
            print("🔍 [DEBUG] 权限弹窗已创建，等待用户响应")
            let response = alert.runModal()
            print("🔍 [DEBUG] 用户响应: \(response.rawValue)")
            
            // 恢复全局点击监听
            // 延迟恢复，确保弹窗完全关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: NSNotification.Name("PreventAutoHide"), object: false)
            }
            
            // 重置全局弹窗状态
            AppDelegate.isPermissionDialogShowing = false
            
            // 弹窗处理完成
            print("🔍 [DEBUG] 开始处理用户选择")
            switch response {
            case .alertFirstButtonReturn:
                // 授权按钮 - 启动权限监控等待用户授权
                // 用户点击授权按钮，启动权限监控
                self.wasAccessibilityDenied = true
                self.startPermissionMonitoring()
                self.openAccessibilitySettings()
            case .alertThirdButtonReturn:
                if isFirstLaunch {
                    // 首次启动：跳过按钮，用更温和的方式处理
                    // 用户选择跳过快捷键功能（首次启动）
                    // 不设置"不再提示"，让用户以后可以在设置中重新启用
                } else {
                    // 非首次启动：不再提示按钮
                    UserDefaults.standard.set(true, forKey: "DisableAccessibilityPrompt")
                    // 用户选择不再提示辅助功能权限
                }
            default:
                // 稍后按钮或关闭
                // 用户选择稍后设置辅助功能权限
                break
            }
        }
    }
    
    private func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preferences.security.privacy.accessibility"
        ]
        
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                // 已打开辅助功能设置
                return
            }
        }
        
        // 备用：打开系统设置
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - 调试和测试方法
    
    /// 强制触发权限检查（用于调试）
    func forcePermissionCheck() {
        print("🔍 强制触发权限检查...")
        
        // 重置相关标志
        isCheckingPermissions = false
        hasShownPermissionAlert = false
        
        // 清除"不再提示"设置（仅用于调试）
        UserDefaults.standard.removeObject(forKey: "DisableAccessibilityPrompt")
        
        // 立即检查权限
        checkPermissionAsync { hasPermission in
            print("🔍 当前权限状态: \(hasPermission)")
            if !hasPermission {
                print("🔍 权限不足，显示权限弹窗")
                let settingsManager = SettingsManager.shared
                self.showPermissionAlert(isFirstLaunch: settingsManager.isFirstLaunch)
            } else {
                print("✅ 权限已获得")
            }
        }
    }
    
    /// 强制显示权限弹窗（用于调试，无论当前权限状态）
    func forceShowPermissionDialog() {
        print("🔍 [DEBUG] 强制显示权限弹窗（调试模式）")
        
        // 清除所有阻止弹窗的设置
        UserDefaults.standard.removeObject(forKey: "DisableAccessibilityPrompt")
        isCheckingPermissions = false
        hasShownPermissionAlert = false
        
        // 重置全局弹窗状态（调试模式下强制重置）
        AppDelegate.isPermissionDialogShowing = false
        AppDelegate.lastPermissionDialogTime = Date(timeIntervalSince1970: 0)
        
        // 直接显示权限弹窗
        let settingsManager = SettingsManager.shared
        DispatchQueue.main.async {
            self.showPermissionAlert(isFirstLaunch: settingsManager.isFirstLaunch)
        }
    }
    
    // MARK: - 权限监控机制
    
    private func startPermissionMonitoring() {
        // 启动辅助功能权限监控...
        
        // 停止现有的监控
        stopPermissionMonitoring()
        
        // 优化监控间隔：减少到2秒，减少延迟
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermissionStatus()
        }
    }
    
    private func stopPermissionMonitoring() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
        // 停止辅助功能权限监控
    }
    
    private func checkPermissionStatus() {
        // 使用优化的权限检查
        checkPermissionAsync { currentAccessEnabled in
            // 如果之前没有权限，现在有了权限
            if self.wasAccessibilityDenied && currentAccessEnabled {
                // 检测到辅助功能权限已授权!
                
                // 重置状态
                self.wasAccessibilityDenied = false
                self.hasShownPermissionAlert = false
                
                // 停止监控
                self.stopPermissionMonitoring()
                
                // 显示授权成功提示
                self.showPermissionGrantedAlert()
                
                // 清除"不再提示"设置
                UserDefaults.standard.removeObject(forKey: "DisableAccessibilityPrompt")
                
                // 重新注册全局快捷键
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.setupGlobalHotkey()
                }
            }
        }
    }
    
    private func showPermissionGrantedAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "辅助功能权限授权成功！"
            alert.informativeText = """
            🎉 太棒了！现在您可以使用全局快捷键功能了：
            
            • Cmd+Ctrl+V：显示/隐藏 OneClip 窗口
            
            全局快捷键已激活，请尝试使用吧！
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            
            // 直接设置窗口级别
            alert.window.level = .floating
            
            let _ = alert.runModal()
            
            // 已显示权限授权成功提示
        }
    }
    
    // MARK: - 状态栏监控系统
    
    private func startStatusBarMonitoring() {
        // 停止现有的监控
        stopStatusBarMonitoring()
        
        // 只在需要显示菜单栏图标时启动监控
        guard SettingsManager.shared.showInMenuBar else {
            return
        }
        
        // 启动状态栏监控系统
        logDebug("启动状态栏监控系统")
        
        // 每15秒检查一次状态栏项目状态 (提高频率)
        statusItemMonitorTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.checkStatusBarItem()
        }
    }
    
    private func stopStatusBarMonitoring() {
        statusItemMonitorTimer?.invalidate()
        statusItemMonitorTimer = nil
        logDebug("停止状态栏监控系统")
    }
    
    private func checkStatusBarItem() {
        // 如果设置为不显示菜单栏，停止监控
        guard SettingsManager.shared.showInMenuBar else {
            stopStatusBarMonitoring()
            return
        }
        
        guard let statusItem = statusItem else {
            logDebug("状态栏监控：状态栏项目为空，重新创建")
            ensureStatusBarItemExists()
            return
        }
        
        // 检查可见性
        if !statusItem.isVisible {
            logDebug("状态栏监控：图标不可见，修复中...")
            statusItem.isVisible = true
        }
        
        // 检查按钮和图像
        if statusItem.button == nil || (statusItem.button?.image == nil && (statusItem.button?.title.isEmpty != false)) {
            logDebug("状态栏监控：按钮或图像缺失，执行修复...")
            verifyAndFixStatusBarItem()
        }
        
        // 输出状态日志
        let visibilityStatus = statusItem.isVisible ? "可见" : "不可见"
        let buttonStatus = statusItem.button != nil ? "有按钮" : "无按钮"
        let imageStatus = statusItem.button?.image != nil ? "有图像" : (statusItem.button?.title.isEmpty == false ? "有文本" : "无图像/文本")
        logDebug("状态栏状态检查: \(visibilityStatus), \(buttonStatus), \(imageStatus)")
    }
    
    // MARK: - 通知系统设置
    private func setupNotificationSystem() {
        // 初始化通知系统...
        
        // 检查是否有有效的bundle（避免调试模式下的bundle问题）
        guard Bundle.main.bundleIdentifier != nil else {
            print("⚠️ 检测到调试模式，跳过通知系统初始化")
            return
        }
        
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = self
        
        // 初始化 NotificationManager 以确保通知权限被请求
        // 初始化通知中心
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // 通知系统初始化完成
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 应用前台时收到通知，强制显示
        // 即使应用在前台也显示通知
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 用户点击了通知
        // 用户点击通知时的处理
        completionHandler()
    }
    
    // MARK: - 设置监听器
    private func setupSettingsObservers() {
        let settings = SettingsManager.shared
        
        // 直接监听设置变化而不使用FeatureManager
        setupLaunchAtLoginListener()
        
        // 监听菜单栏显示设置变化
        settings.$showInMenuBar
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showInMenuBar in
                // 确保在主线程执行状态栏操作
                if showInMenuBar {
                    self?.ensureStatusBarItemExists()
                } else {
                    self?.removeStatusBarItem()
                }
            }
            .store(in: &cancellables)
        
        // 初始状态检查 - 延迟执行以确保设置已加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if settings.showInMenuBar {
                self.ensureStatusBarItemExists()
            }
        }
    }
    
    // MARK: - 应用事件监听器
    private func setupApplicationObservers() {
        // 监听应用激活事件
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        }
        
        // 应用事件监听器已设置
    }
    
    private func setupLaunchAtLoginListener() {
        let settings = SettingsManager.shared
        
        // 监听开机启动设置变化
        settings.$autoStartOnLogin
            .sink { autoStartOnLogin in
                self.setLaunchAtLogin(autoStartOnLogin)
            }
            .store(in: &cancellables)
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.yourcompany.OneClip"
        
        if #available(macOS 13.0, *) {
            // 使用新的API
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    // 开机启动已启用
                } else {
                    try SMAppService.mainApp.unregister()
                    // 开机启动已禁用
                }
            } catch {
                // 设置开机启动失败
            }
        } else {
            // 使用旧的API (macOS 12及以下)
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
            if success {
                // 开机启动设置完成 (旧版API)
            } else {
                // 设置开机启动失败 (旧版本API)
            }
        }
    }
    
    private func removeStatusBarItem() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            logDebug("状态栏项目已移除")
        }
    }
    
    // MARK: - 状态栏项目管理增强
    
    private func ensureStatusBarItemExists() {
        // 如果已经存在且正常，直接返回
        if let statusItem = statusItem, 
           statusItem.isVisible, 
           statusItem.button != nil,
           statusItem.button?.image != nil {
            return
        }
        
        // 否则创建或修复状态栏项目（使用统一的重试机制）
        if statusBarRetryCount < maxStatusBarRetries {
            createStatusBarItem()
        }
    }
    
    private func createStatusBarItemWithRetry(retryCount: Int = 0) {
        guard retryCount < 3 else {
            logDebug("状态栏项目创建失败，已达到最大重试次数")
            return
        }
        
        // 使用统一的重试机制，避免递归调用
        if statusBarRetryCount < maxStatusBarRetries {
            createStatusBarItem()
        }
    }
}

// MARK: - NSImage Extensions
extension NSImage {
    func withTintColor(_ color: NSColor) -> NSImage {
        guard let image = self.copy() as? NSImage else { return self }
        image.lockFocus()
        
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        
        image.unlockFocus()
        return image
    }
}

@main
struct OneClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager()
    @StateObject private var clipboardStore = ClipboardStore(getCleanupDays: { 7 })
    
    var body: some Scene {
        Window("OneClip", id: "main") {
            ContentView()
                .environmentObject(SettingsManager.shared)
                .environmentObject(ClipboardManager.shared)
                .environmentObject(clipboardStore)
                .environmentObject(windowManager)
                .onAppear {
                    // 设置窗口管理器
                    windowManager.setupWindow()
                    
                    // 设置窗口属性并确保在最前面
                    let windows = NSApplication.shared.windows
                    if let window = windows.first {
                        appDelegate.mainWindow = window
                        // 确保窗口可以成为关键窗口
                        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
                        window.titlebarAppearsTransparent = true
                        window.titleVisibility = .hidden
                        window.title = "OneClip"
                        window.styleMask.remove(.resizable)
                        
                        // 设置窗口按钮在内容区域内显示（类似访达风格）
                        window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = false
                        window.standardWindowButton(.miniaturizeButton)?.superview?.superview?.isHidden = false
                        window.standardWindowButton(.zoomButton)?.superview?.superview?.isHidden = false
                        window.minSize = NSSize(width: 600, height: 600)
                        window.maxSize = NSSize(width: 600, height: 600)
                        
                        // 设置窗口级别
                        window.level = .normal
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                        
                        // 首次启动时温和地显示窗口
                        DispatchQueue.main.async {
                            // 温和地显示窗口，避免强制激活
                            window.orderFront(nil)
                            window.makeKey()
                            
                            // 更精确的居中判断
                            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
                            let windowFrame = window.frame
                            let needsRepositioning = !window.isVisible || 
                                                   windowFrame.origin.x < screenFrame.minX || 
                                                   windowFrame.origin.y < screenFrame.minY ||
                                                   windowFrame.maxX > screenFrame.maxX ||
                                                   windowFrame.maxY > screenFrame.maxY
                            
                            if needsRepositioning {
                                window.center()
                            }
                            
                            // 首次启动窗口已温和显示
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
                    // 处理设置显示通知
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 600)
        .windowResizability(.contentSize)
    }
}
