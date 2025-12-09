import SwiftUI
import AppKit

// 扩展 NSNotification.Name 以包含 dockToggle 通知
extension NSNotification.Name {
    static let dockToggle = NSNotification.Name("dockToggle")
    static let WindowOnTopChanged = NSNotification.Name("WindowOnTopChanged")
}

class WindowManager: ObservableObject {
    @Published var isWindowVisible = false
    private var window: NSWindow?
    private let logger = Logger.shared
    private var globalClickMonitor: Any?
    private var windowStateObserver: NSObjectProtocol?
    private var dockStateObserver: NSObjectProtocol?
    private var preventAutoHideObserver: NSObjectProtocol?
    private var windowOnTopObserver: NSObjectProtocol?
    private var stateValidationTimer: Timer?
    private var pendingWindowShow = false
    private var lastDockToggleTime: TimeInterval = 0
    private let dockToggleDelay: TimeInterval = 0.3 // 300ms 延迟避免冲突
    private var shouldPreventAutoHide = false
    
    // 边界情况处理
    private var lastToggleTime: TimeInterval = 0
    private let minToggleInterval: TimeInterval = 0.1 // 防止快速连续操作
    private var isProcessingToggle = false
    private var permissionCheckTimer: Timer?
    private var lastPermissionCheck: TimeInterval = 0
    
    init() {
        self.setupPreventAutoHideMonitoring()
        self.setupWindowOnTopMonitoring()
        self.startPeriodicStateValidation()
        self.startPermissionMonitoring()
    }
    
    func setupWindow() {
        let windows = NSApplication.shared.windows
        window = windows.first
        
        // 设置窗口固定大小
        if let window = window {
            window.styleMask.remove(.resizable)
            window.setContentSize(NSSize(width: 600, height: 700))
            window.minSize = NSSize(width: 600, height: 700)
            window.maxSize = NSSize(width: 600, height: 700)
            
            // 设置窗口委托来处理窗口事件
            setupWindowDelegate(window)
            
            // 应用初始的窗口置顶状态
            applyWindowOnTopState()
        }
        
        // 监听 Dock 状态变化
        setupDockStateMonitoring()
        
        // 监听窗口状态变化
        setupWindowStateMonitoring()
        
        logger.info("窗口管理器已初始化")
    }
    
    private func setupWindowDelegate(_ window: NSWindow) {
        // 确保窗口不会因为失去焦点就自动隐藏
        window.hidesOnDeactivate = false
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 确保窗口能够接收键盘事件，这对于删除键等快捷键处理至关重要
        window.acceptsMouseMovedEvents = true
        
        // 设置窗口为第一响应者，确保能够接收键盘事件
        if let contentView = window.contentView {
            contentView.allowedTouchTypes = [.direct]
        }
    }
    
    private func setupDockStateMonitoring() {
        dockStateObserver = NotificationCenter.default.addObserver(
            forName: .dockToggle,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let showInDock = notification.object as? Bool else { return }
            
            self.handleDockStateChange(showInDock: showInDock)
        }
    }
    
    private func setupWindowStateMonitoring() {
        guard let window = window else { return }
        
        windowStateObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.isWindowVisible = true
            self?.logger.debug("窗口已获得焦点")
        }
    }
    
    private func setupPreventAutoHideMonitoring() {
        // 监听防止自动隐藏通知
        preventAutoHideObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PreventAutoHide"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let shouldPrevent = notification.object as? Bool {
                self?.setPreventAutoHide(shouldPrevent)
                self?.logger.info("防止自动隐藏设置已更新: \(shouldPrevent)")
            }
        }
    }
    
    private func setupWindowOnTopMonitoring() {
        // 监听窗口置顶状态变化通知
        windowOnTopObserver = NotificationCenter.default.addObserver(
            forName: .WindowOnTopChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applyWindowOnTopState()
        }
    }
    
    private func handleDockStateChange(showInDock: Bool) {
        lastDockToggleTime = Date().timeIntervalSince1970
        
        logger.info("Dock 状态变化: \(showInDock ? "显示" : "隐藏")")
        
        // 如果窗口当前可见，需要特殊处理
        if isWindowVisible {
            if showInDock {
                // 要显示 Dock 图标，确保应用处于 regular 模式
                handleShowDockWithVisibleWindow()
            } else {
                // 要隐藏 Dock 图标，需要先隐藏窗口再切换模式
                handleHideDockWithVisibleWindow()
            }
        } else {
            // 窗口不可见时，直接切换应用模式
            switchApplicationMode(showInDock: showInDock)
        }
    }
    
    private func handleShowDockWithVisibleWindow() {
        // 显示 Dock 图标时，确保应用处于 regular 模式
        NSApp.setActivationPolicy(.regular)
        
        // 短暂延迟后重新激活窗口，确保其保持在前台
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if let window = self.window, self.isWindowVisible {
                window.makeKeyAndOrderFront(nil)
                // 移除强制激活，避免鼠标飘飞
            }
        }
        
        logger.info("已显示 Dock 图标并保持窗口可见")
    }
    
    private func handleHideDockWithVisibleWindow() {
        guard let window = window else { return }
        
        // 记录要重新显示窗口
        pendingWindowShow = true
        
        // 先隐藏窗口
        window.orderOut(nil)
        isWindowVisible = false
        
        // 延迟切换到 accessory 模式
        DispatchQueue.main.asyncAfter(deadline: .now() + dockToggleDelay) { [weak self] in
            guard let self = self else { return }
            NSApp.setActivationPolicy(.accessory)
            
            // 再延迟一点重新显示窗口
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                if self.pendingWindowShow {
                    self.pendingWindowShow = false
                    self.showWindowInBackground()
                }
            }
        }
        
        logger.info("隐藏 Dock 图标并准备重新显示窗口")
    }
    
    private func switchApplicationMode(showInDock: Bool) {
        let targetPolicy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        let reason = showInDock ? "用户设置显示Dock" : "用户设置隐藏Dock"
        safelySetActivationPolicy(targetPolicy, reason: reason)
    }
    
    private func showWindowInBackground() {
        guard let window = window else { return }
        
        // 只在窗口不可见或位置异常时才居中
        if !window.isVisible || window.frame.origin.x < 0 || window.frame.origin.y < 0 {
            window.center()
        }
        
        // 在后台模式下显示窗口
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        
        // 应用窗口置顶状态
        applyWindowOnTopState()
        
        isWindowVisible = true
        startGlobalClickMonitoring()
        
        logger.info("窗口已在后台模式下显示")
    }
    
    
    func showWindow() {
        guard let window = window else { return }
        
        DispatchQueue.main.async {
            // 智能窗口定位，考虑多显示器环境
            self.smartPositionWindow(window)
            
            window.makeKeyAndOrderFront(nil)
            
            // 确保窗口获得键盘焦点，这对于键盘事件处理至关重要
            window.makeKey()
            
            // 强制激活应用到最前面，确保键盘事件能够正确传递
            NSApp.activate(ignoringOtherApps: true)
            
            // 应用窗口置顶状态
            self.applyWindowOnTopState()
            
            self.isWindowVisible = true
            self.startGlobalClickMonitoring()
            self.logger.info("窗口已显示并获得键盘焦点")
            
            // 延迟验证窗口状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.validateAndSyncWindowState()
            }
        }
    }
    
    func hideWindow() {
        guard let window = window else { return }
        
        // 简化的窗口隐藏逻辑
        DispatchQueue.main.async {
            window.orderOut(nil)
            self.isWindowVisible = false
            self.stopGlobalClickMonitoring()
            
            // 根据设置调整应用策略
            let settingsManager = SettingsManager.shared
            if !settingsManager.showInDock {
                NSApp.setActivationPolicy(.accessory)
            }
            
            self.logger.info("窗口已隐藏")
            
            // 延迟验证窗口状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.validateAndSyncWindowState()
            }
        }
    }
    
    func toggleWindow() {
        let currentTime = Date().timeIntervalSince1970
        
        // 防止快速连续操作
        if isProcessingToggle {
            logger.debug("窗口切换正在处理中，忽略重复请求")
            return
        }
        
        let timeSinceLastToggle = currentTime - lastToggleTime
        if timeSinceLastToggle < minToggleInterval {
            logger.debug("窗口切换过于频繁，忽略请求（间隔: \(timeSinceLastToggle * 1000)ms）")
            return
        }
        
        // 检查是否在 Dock 切换的缓冲期内
        let timeSinceToggle = currentTime - lastDockToggleTime
        if timeSinceToggle < dockToggleDelay {
            logger.debug("Dock 切换中，延迟窗口切换操作")
            DispatchQueue.main.asyncAfter(deadline: .now() + (dockToggleDelay - timeSinceToggle + 0.1)) {
                self.performToggleWindow()
            }
            return
        }
        
        lastToggleTime = currentTime
        performToggleWindow()
    }
    
    private func performToggleWindow() {
        isProcessingToggle = true
        
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
        
        // 验证窗口状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.validateWindowState()
            
            // 如果窗口现在是可见的，确保应用激活到最前面
            if self.isWindowVisible, let window = self.window {
                let settingsManager = SettingsManager.shared
                
                // 强制激活应用到最前面
                NSApp.activate(ignoringOtherApps: true)
                
                if settingsManager.showInDock {
                    // Dock 模式：确保窗口获得焦点
                    window.makeKey()
                } else {
                    // Accessory 模式：确保窗口显示并获得焦点
                    window.makeKey()
                    window.orderFront(nil)
                }
            }
            
            // 完成处理
            self.isProcessingToggle = false
        }
    }
    
    func hideWindowAndPaste() {
        hideWindow()
        
        // 短暂延迟后执行粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            self.logger.info("已执行粘贴操作")
        }
    }
    
    // MARK: - 全局点击监听
    
    private func startGlobalClickMonitoring() {
        // 清除现有监听器
        stopGlobalClickMonitoring()
        
        // 延迟启动全局监听，避免与窗口显示操作冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleGlobalClick(event)
            }
            
            self.logger.info("开始监听全局点击事件")
        }
    }
    
    private func stopGlobalClickMonitoring() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
            logger.info("停止监听全局点击事件")
        }
    }
    
    private func handleGlobalClick(_ event: NSEvent) {
        guard let window = self.window, isWindowVisible else { return }
        
        // 如果设置了防止自动隐藏，则跳过
        if shouldPreventAutoHide {
            logger.info("防止自动隐藏已启用，跳过窗口隐藏")
            return
        }

        // 检查是否有模态窗口（如权限弹窗）显示
        if NSApp.modalWindow != nil {
            logger.info("检测到模态窗口显示，跳过窗口隐藏")
            return
        }
        
        // 检查事件类型，只处理左键点击
        guard event.type == .leftMouseDown else { return }

        // 使用 NSEvent.mouseLocation 获取鼠标在屏幕上的绝对坐标
        let mouseLocation = NSEvent.mouseLocation
        
        // 更精确的窗口边界检查
        let windowFrame = window.frame
        let isClickInsideWindow = windowFrame.contains(mouseLocation)
        
        if !isClickInsideWindow {
            // 额外检查：确保点击不在窗口的子视图或附属窗口中
            let shouldHideWindow = shouldHideWindowForClick(at: mouseLocation, mainWindow: window)
            
            if shouldHideWindow {
                logger.info("检测到窗口外部点击，隐藏窗口")
                DispatchQueue.main.async {
                    self.hideWindow()
                }
            } else {
                logger.info("点击在相关窗口区域，不隐藏窗口")
            }
        } else {
            logger.debug("点击在窗口内部，不隐藏窗口")
        }
    }
    
    /// 判断是否应该因为点击而隐藏窗口
    private func shouldHideWindowForClick(at mouseLocation: NSPoint, mainWindow: NSWindow) -> Bool {
        // 检查所有应用窗口
        let allAppWindows = NSApp.windows.filter { $0.isVisible }
        
        for appWindow in allAppWindows {
            // 检查点击是否在任何应用窗口内
            if appWindow.frame.contains(mouseLocation) {
                // 如果是主窗口，不隐藏
                if appWindow === mainWindow {
                    return false
                }
                
                // 如果是设置窗口、帮助窗口等，也不隐藏
                if isRelatedWindow(appWindow, to: mainWindow) {
                    return false
                }
            }
        }
        
        // 检查菜单栏和状态栏
        if isClickInMenuBarOrStatusBar(at: mouseLocation) {
            return false
        }
        
        // 其他情况下隐藏窗口
        return true
    }
    
    /// 检查窗口是否与主窗口相关
    private func isRelatedWindow(_ window: NSWindow, to mainWindow: NSWindow) -> Bool {
        // 检查是否是子窗口
        if mainWindow.childWindows?.contains(window) == true {
            return true
        }
        
        // 检查是否是模态窗口
        if window.isSheet || window.level == .modalPanel {
            return true
        }
        
        // 检查窗口标题或类型（设置窗口、帮助窗口等）
        let relatedTitles = ["设置", "Settings", "快捷键帮助", "Shortcuts Help", "关于", "About"]
        if relatedTitles.contains(where: { window.title.contains($0) }) {
            return true
        }
        
        return false
    }
    
    /// 检查点击是否在菜单栏或状态栏区域
    private func isClickInMenuBarOrStatusBar(at mouseLocation: NSPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        let screenFrame = screen.frame
        let menuBarHeight: CGFloat = 24 // 标准菜单栏高度
        
        // 检查是否在菜单栏区域（屏幕顶部）
        let menuBarFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - menuBarHeight,
            width: screenFrame.width,
            height: menuBarHeight
        )
        
        return menuBarFrame.contains(mouseLocation)
    }
    
    // MARK: - 防止自动隐藏控制
    func setPreventAutoHide(_ prevent: Bool) {
        shouldPreventAutoHide = prevent
        logger.info("防止自动隐藏设置为: \(prevent)")
    }
    
    func temporarilyPreventAutoHide(duration: TimeInterval = 0.5) {
        setPreventAutoHide(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.setPreventAutoHide(false)
        }
    }
    
    // MARK: - 窗口置顶控制
    
    /// 应用窗口置顶状态
    private func applyWindowOnTopState() {
        guard let window = window else { return }
        
        let settingsManager = SettingsManager.shared
        let shouldKeepOnTop = settingsManager.keepWindowOnTop
        
        DispatchQueue.main.async {
            if shouldKeepOnTop {
                // 设置窗口为浮动级别，保持在最前面
                window.level = .floating
                self.logger.info("窗口已设置为置顶")
            } else {
                // 恢复为正常级别
                window.level = .normal
                self.logger.info("窗口已取消置顶")
            }
        }
    }
    
    /// 切换窗口置顶状态
    func toggleWindowOnTop() {
        let settingsManager = SettingsManager.shared
        settingsManager.keepWindowOnTop.toggle()
        
        // 立即应用窗口置顶状态，确保窗口保持可见
        applyWindowOnTopState()
        
        logger.info("窗口置顶状态已切换为: \(settingsManager.keepWindowOnTop)")
    }
    
    
    deinit {
        // 停止全局点击监听
        stopGlobalClickMonitoring()
        
        // 停止定时器
        stateValidationTimer?.invalidate()
        stateValidationTimer = nil
        
        // 停止权限检查定时器
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        
        // 移除所有通知观察者
        if let observer = dockStateObserver {
            NotificationCenter.default.removeObserver(observer)
            dockStateObserver = nil
        }
        if let observer = windowStateObserver {
            NotificationCenter.default.removeObserver(observer)
            windowStateObserver = nil
        }
        if let observer = preventAutoHideObserver {
            NotificationCenter.default.removeObserver(observer)
            preventAutoHideObserver = nil
        }
        if let observer = windowOnTopObserver {
            NotificationCenter.default.removeObserver(observer)
            windowOnTopObserver = nil
        }
        
        logger.info("WindowManager 已释放，所有资源已清理")
    }
    
    // MARK: - 智能窗口管理方法
    
    /// 安全地显示窗口，考虑当前的 Dock 状态和应用模式
    func safeShowWindow() {
        // 检查当前应用状态
        let currentPolicy = NSApp.activationPolicy()
        let settingsManager = SettingsManager.shared
        let shouldShowInDock = settingsManager.showInDock
        
        logger.debug("安全显示窗口 - 当前策略: \(currentPolicy.rawValue), 设置要求: \(shouldShowInDock)")
        
        // 如果当前策略与设置不匹配，先调整策略
        if (currentPolicy == .regular) != shouldShowInDock {
            switchApplicationMode(showInDock: shouldShowInDock)
            
            // 给策略切换一些时间
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showWindowInternal()
            }
        } else {
            showWindowInternal()
        }
    }
    
    private func showWindowInternal() {
        guard let window = window else { return }
        
        // 简化的窗口显示逻辑
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 只在窗口不可见或位置异常时才居中
            if !window.isVisible || window.frame.origin.x < 0 || window.frame.origin.y < 0 {
                window.center()
            }
            
            window.makeKeyAndOrderFront(nil)
            // 移除强制激活检查，让系统自然处理焦点
            
            // 应用窗口置顶状态
            self.applyWindowOnTopState()
            
            self.isWindowVisible = true
            self.startGlobalClickMonitoring()
            self.logger.info("窗口已显示")
        }
    }
    
    /// 智能地隐藏窗口，根据设置决定是否保持 Dock 图标
    func smartHideWindow() {
        guard let window = window else { return }
        
        window.orderOut(nil)
        isWindowVisible = false
        stopGlobalClickMonitoring()
        
        // 根据设置决定应用策略
        let settingsManager = SettingsManager.shared
        if !settingsManager.showInDock {
            // 延迟切换到 accessory 模式，确保窗口完全隐藏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        
        logger.info("智能隐藏窗口完成")
    }
    
    /// 检查窗口状态一致性
    func validateWindowState() {
        guard let window = window else { return }
        
        let windowVisible = window.isVisible
        let stateVisible = isWindowVisible
        
        if windowVisible != stateVisible {
            logger.warning("窗口状态不一致 - 实际: \(windowVisible), 状态: \(stateVisible)")
            isWindowVisible = windowVisible
        }
    }
    
    // MARK: - 应用策略管理
    
    /// 当前应用策略状态
    private var currentActivationPolicy: NSApplication.ActivationPolicy {
        return NSApp.activationPolicy()
    }
    
    /// 安全地切换应用策略
    private func safelySetActivationPolicy(_ newPolicy: NSApplication.ActivationPolicy, reason: String) {
        let currentPolicy = currentActivationPolicy
        
        // 如果策略相同，无需切换
        guard currentPolicy != newPolicy else {
            logger.debug("应用策略已是 \(newPolicy == .accessory ? "accessory" : "regular")，无需切换")
            return
        }
        
        logger.info("切换应用策略: \(currentPolicy == .accessory ? "accessory" : "regular") -> \(newPolicy == .accessory ? "accessory" : "regular") (\(reason))")
        
        DispatchQueue.main.async {
            // 如果从 accessory 切换到 regular，需要特殊处理
            if currentPolicy == .accessory && newPolicy == .regular {
                // 先设置策略
                NSApp.setActivationPolicy(newPolicy)
                
                // 如果有窗口需要显示，确保激活
                if self.isWindowVisible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                        self.window?.makeKeyAndOrderFront(nil)
                    }
                }
            } else {
                // 普通策略切换
                NSApp.setActivationPolicy(newPolicy)
            }
            
            self.logger.info("应用策略切换完成: \(newPolicy == .accessory ? "accessory" : "regular")")
        }
    }
    
    /// 确保正确的应用策略
    private func ensureCorrectApplicationPolicy() {
        let settingsManager = SettingsManager.shared
        let shouldShowInDock = settingsManager.showInDock
        let hasVisibleWindow = isWindowVisible
        
        let shouldBeRegular = shouldShowInDock || hasVisibleWindow
        let targetPolicy: NSApplication.ActivationPolicy = shouldBeRegular ? .regular : .accessory
        
        let reason = shouldShowInDock ? "设置要求显示Dock" : (hasVisibleWindow ? "有可见窗口" : "无可见窗口且设置隐藏Dock")
        
        safelySetActivationPolicy(targetPolicy, reason: reason)
    }
    
    // MARK: - Accessory 模式专用窗口显示
    private func showWindowInAccessoryMode(_ window: NSWindow) {
        // 只在窗口不可见或位置异常时才居中
        if !window.isVisible || window.frame.origin.x < 0 || window.frame.origin.y < 0 {
            window.center()
        }
        
        // 显示窗口
        window.setIsVisible(true)
        window.orderFront(nil)
        
        // 应用窗口置顶状态
        applyWindowOnTopState()
        
        // 尝试获得键盘焦点
        DispatchQueue.main.async {
            window.makeKey()
            
            // 确保窗口在前台
            window.orderFront(nil)
            
            // 验证窗口状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.validateWindowVisibility(window)
            }
        }
    }
    
    // MARK: - 窗口状态验证和同步
    
    /// 验证并同步窗口状态
    private func validateAndSyncWindowState() {
        guard let window = window else {
            if isWindowVisible {
                logger.warning("窗口对象为空但状态为可见，修正状态")
                isWindowVisible = false
            }
            return
        }
        
        let actualVisible = window.isVisible
        let stateVisible = isWindowVisible
        
        if actualVisible != stateVisible {
            logger.warning("窗口状态不同步 - 实际: \(actualVisible), 状态: \(stateVisible)，正在修正")
            isWindowVisible = actualVisible
            
            // 根据实际状态调整监听器
            if actualVisible {
                startGlobalClickMonitoring()
            } else {
                stopGlobalClickMonitoring()
            }
        }
    }
    
    /// 强制同步窗口状态
    func forceSyncWindowState() {
        validateAndSyncWindowState()
    }
    
    /// 验证窗口可见性并尝试修复
    private func validateWindowVisibility(_ window: NSWindow) {
        let actuallyVisible = window.isVisible && window.occlusionState.contains(.visible)
        
        if !actuallyVisible {
            logger.warning("窗口显示失败，尝试重新显示")
            // 重新尝试显示
            window.orderFront(nil)
            window.makeKey()
            
            // 延迟验证修复结果
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.validateAndSyncWindowState()
            }
        } else {
            logger.debug("窗口显示验证通过")
        }
    }
    
    /// 定期验证窗口状态（防止状态漂移）
    private func startPeriodicStateValidation() {
        // 停止现有定时器
        stateValidationTimer?.invalidate()
        
        // 使用更长的验证间隔，减少CPU消耗
        let validationInterval: TimeInterval = 15.0 // 从5秒调整为15秒
        stateValidationTimer = Timer.scheduledTimer(withTimeInterval: validationInterval, repeats: true) { [weak self] _ in
            // 只在窗口可见时进行验证
            if self?.isWindowVisible == true {
                self?.validateAndSyncWindowState()
            }
        }
    }
    
    // MARK: - 多显示器环境处理
    
    /// 智能窗口定位，考虑多显示器环境
    private func smartPositionWindow(_ window: NSWindow) {
        // 获取当前鼠标位置所在的屏幕
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first
        
        guard let screen = targetScreen else {
            // 如果无法确定屏幕，使用默认居中
            window.center()
            return
        }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        // 检查窗口是否需要重新定位
        let needsRepositioning = !window.isVisible ||
                               windowFrame.origin.x < screenFrame.minX ||
                               windowFrame.origin.y < screenFrame.minY ||
                               windowFrame.maxX > screenFrame.maxX ||
                               windowFrame.maxY > screenFrame.maxY
        
        if needsRepositioning {
            // 计算窗口在目标屏幕上的居中位置
            let centeredX = screenFrame.minX + (screenFrame.width - windowFrame.width) / 2
            let centeredY = screenFrame.minY + (screenFrame.height - windowFrame.height) / 2
            
            let newOrigin = NSPoint(x: centeredX, y: centeredY)
            window.setFrameOrigin(newOrigin)
            
            logger.info("窗口已重新定位到屏幕: \(screen.localizedName)")
        } else {
            logger.debug("窗口位置正常，无需调整")
        }
    }
    
    /// 检查系统权限变化
    private func checkSystemPermissions() {
        let currentTime = Date().timeIntervalSince1970
        
        // 避免频繁检查权限
        if currentTime - lastPermissionCheck < 30.0 { // 30秒检查一次
            return
        }
        
        lastPermissionCheck = currentTime
        
        // 检查辅助功能权限（仅检查，不弹窗）
        let hasAccessibilityPermission = AXIsProcessTrusted()
        
        if !hasAccessibilityPermission {
            logger.warning("辅助功能权限已丢失，可能影响全局快捷键功能")
            // 只记录状态，不触发弹窗，弹窗统一由OneClipApp管理
        }
    }
    
    /// 启动权限监控
    private func startPermissionMonitoring() {
        // 使用更长的权限检查间隔，减少系统调用
        let permissionCheckInterval: TimeInterval = 300.0 // 从2分钟调整为5分钟
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckInterval, repeats: true) { [weak self] _ in
            // 只在应用活跃时检查权限
            if NSApp.isActive {
                self?.checkSystemPermissions()
            }
        }
    }
}