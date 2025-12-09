import Cocoa
import Carbon

class Hotkey {
    private let keyCode: UInt16
    private let modifierFlags: NSEvent.ModifierFlags
    private let callback: () -> Void
    private let hotkeyID: UInt32
    
    // Carbon 热键（更稳定的全局热键方案）
    private var carbonHotkeyID: EventHotKeyID?
    private var carbonHotkey: EventHotKeyRef?
    
    // NSEvent 监听器（备用）
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    // 状态管理
    private var permissionTimer: Timer?
    private var isRegistered = false
    private var hasRequestedPermission = false
    private var lastTriggerTime: TimeInterval = 0
    private let debounceInterval: TimeInterval = 0.2 // 200ms防抖动
    private var hasAccessibilityPermission = false
    private var useCarbon = false
    
    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, callback: @escaping () -> Void, hotkeyID: UInt32 = 1001) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.callback = callback
        self.hotkeyID = hotkeyID
        checkAccessibilityPermissions()
        
        // 设置Carbon热键事件处理
        setupCarbonEventHandler()
    }
    
    func register() {
        print("🚀 开始注册全局快捷键 (KeyCode: \(keyCode))...")
        
        // 立即检查权限
        checkAccessibilityPermissions()
        
        var success = false
        
        // 优先使用Carbon热键API（更可靠）
        if hasAccessibilityPermission {
            success = registerCarbonHotkey()
            if success {
                useCarbon = true
                print("✅ 使用Carbon API注册热键成功")
            }
        }
        
        // 如果Carbon失败或没有权限，使用NSEvent作为备用
        if !success {
            setupNSEventMonitors()
            useCarbon = false
            print("⚠️ 使用NSEvent备用方案")
            success = true  // NSEvent setup always "succeeds"
        }
        
        // 立即显示权限引导（如果需要）
        if !hasAccessibilityPermission && !hasRequestedPermission {
            print("💡 快捷键将仅在当前应用中工作，需要权限才能在所有应用中使用")
            hasRequestedPermission = true  // 仅标记已请求，不显示弹窗
            startPermissionMonitoring()
        }
        
        print("✅ 全局快捷键注册完成: \(modifierDescription())")
        
        // 显示状态信息
        if hasAccessibilityPermission {
            print("🌟 快捷键将在所有应用中工作")
        } else {
            print("⚡ 快捷键仅在当前应用中工作")
        }
    }
    
    // MARK: - Carbon 热键实现（主要方案）
    
    private func setupCarbonEventHandler() {
        // 设置Carbon事件处理器 - 修复版本
        let eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]
        
        // 使用Unmanaged来保存self引用，避免内存泄漏
        let unmanagedSelf = Unmanaged.passUnretained(self)
        
        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
                return hotkey.handleCarbonEvent(event: event)
            },
            eventTypes.count,
            eventTypes,
            unmanagedSelf.toOpaque(),
            nil
        )
        
        if result == noErr {
            print("✅ Carbon事件处理器安装成功")
        } else {
            print("❌ Carbon事件处理器安装失败: \(result)")
        }
    }
    
    private func registerCarbonHotkey() -> Bool {
        // 注销现有热键
        unregisterCarbonHotkey()
        
        // 创建热键ID，使用自定义的ID
        carbonHotkeyID = EventHotKeyID(signature: fourCharCodeFrom("MACP"), id: hotkeyID)
        guard let hotkeyIDStruct = carbonHotkeyID else { return false }
        
        // 转换修饰键
        let carbonModifiers = nsEventFlagsToCarbonFlags(modifierFlags)
        
        // 注册热键
        var hotkeyRef: EventHotKeyRef?
        let result = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotkeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if result == noErr, let hotkey = hotkeyRef {
            carbonHotkey = hotkey
            print("✅ Carbon热键注册成功: \(modifierDescription()) (ID: \(hotkeyID))")
            return true
        } else {
            print("❌ Carbon热键注册失败: \(result) (ID: \(hotkeyID))")
            return false
        }
    }
    
    private func handleCarbonEvent(event: EventRef?) -> OSStatus {
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
            // 检查是否是我们注册的热键
            if eventHotKeyID.signature == fourCharCodeFrom("MACP") {
                if eventHotKeyID.id == hotkeyID {
                    print("🎯 Carbon热键触发: \(modifierDescription()) (ID: \(hotkeyID))")
                    triggerHotkey()
                    return noErr
                }
            }
        }
        
        return OSStatus(eventNotHandledErr)
    }
    
    private func unregisterCarbonHotkey() {
        if let hotkey = carbonHotkey {
            UnregisterEventHotKey(hotkey)
            carbonHotkey = nil
            print("📴 Carbon热键已注销")
        }
    }
    
    // MARK: - NSEvent 实现（备用方案）
    
    private func setupNSEventMonitors() {
        // 清除现有监听器
        unregisterNSEventMonitors()
        
        // 设置全局键盘事件监听器（监听其他应用中的按键）
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // 设置本地键盘事件监听器（监听当前应用中的按键）
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
        
        if globalEventMonitor != nil || localEventMonitor != nil {
            print("⚡ NSEvent监听器已设置")
            isRegistered = true
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == self.keyCode && self.modifierFlagsMatch(event.modifierFlags) {
            print("🎯 NSEvent热键触发: \(modifierDescription())")
            triggerHotkey()
        }
    }
    
    private func unregisterNSEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    // MARK: - 通用触发处理
    
    private func triggerHotkey() {
        // 防抖动：检查距离上次触发的时间
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastTriggerTime < debounceInterval {
            print("⚡ 快捷键触发过于频繁，已忽略")
            return
        }
        
        lastTriggerTime = currentTime
        
        // 立即执行回调，减少延迟
        callback()
    }
    
    // MARK: - 权限管理
    
    private func checkAccessibilityPermissions() {
        // 缓存权限检查结果，避免频繁调用造成延迟
        let permission = AXIsProcessTrusted()
        if permission != hasAccessibilityPermission {
            hasAccessibilityPermission = permission
            
            if hasAccessibilityPermission {
                print("✅ 已获得辅助功能权限")
            } else {
                print("⚠️ 需要辅助功能权限以确保热键在所有应用中工作")
            }
        }
    }
    
    private func startPermissionMonitoring() {
        guard !hasAccessibilityPermission else { return }
        
        print("🔍 [HotkeyCarbon] 开始权限监控")
        
        // 每30秒检查一次权限，减少检查频率
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // 异步检查权限（仅检查，不弹窗）
            DispatchQueue.global(qos: .background).async {
                let newStatus = AXIsProcessTrusted()
                
                DispatchQueue.main.async {
                    if newStatus != self.hasAccessibilityPermission {
                        self.hasAccessibilityPermission = newStatus
                        
                        if newStatus {
                            print("✅ [HotkeyCarbon] 获得辅助功能权限，停止监控")
                            timer.invalidate()
                            self.permissionTimer = nil
                            
                            // 尝试切换到更稳定的Carbon API
                            if !self.useCarbon && self.registerCarbonHotkey() {
                                self.unregisterNSEventMonitors()
                                self.useCarbon = true
                                print("🔄 已切换到Carbon API")
                            }
                        } else {
                            print("⚠️ [HotkeyCarbon] 仍缺少辅助功能权限，但不在此处弹窗")
                            // 权限弹窗统一由OneClipApp管理
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func modifierFlagsMatch(_ eventFlags: NSEvent.ModifierFlags) -> Bool {
        let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventRelevantFlags = eventFlags.intersection(relevantFlags)
        let targetRelevantFlags = modifierFlags.intersection(relevantFlags)
        
        // 精确匹配修饰键
        return eventRelevantFlags == targetRelevantFlags
    }
    
    private func nsEventFlagsToCarbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        
        if flags.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }
        if flags.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }
        
        return carbonFlags
    }
    
    private func modifierDescription() -> String {
        var parts: [String] = []
        
        if modifierFlags.contains(.command) {
            parts.append("Cmd")
        }
        if modifierFlags.contains(.shift) {
            parts.append("Shift")
        }
        if modifierFlags.contains(.option) {
            parts.append("Option")
        }
        if modifierFlags.contains(.control) {
            parts.append("Control")
        }
        
        let keyName: String
        switch keyCode {
        case 9: keyName = "V"
        case 8: keyName = "C"
        case 15: keyName = "R"
        case 18: keyName = "1"
        case 19: keyName = "2"
        case 20: keyName = "3"
        case 21: keyName = "4"
        case 23: keyName = "5"
        case 22: keyName = "6"
        case 26: keyName = "7"
        case 28: keyName = "8"
        case 25: keyName = "9"
        default: keyName = "Key\(keyCode)"
        }
        
        return parts.joined(separator: "+") + "+\(keyName)"
    }
    
    private func fourCharCodeFrom(_ string: String) -> OSType {
        let chars = Array(string.utf8)
        return OSType(chars[0]) << 24 |
               OSType(chars[1]) << 16 |
               OSType(chars[2]) << 8 |
               OSType(chars[3])
    }
    
    func unregister() {
        print("🧹 开始注销全局快捷键...")
        
        // 停止定时器
        permissionTimer?.invalidate()
        permissionTimer = nil
        
        // 注销Carbon热键
        unregisterCarbonHotkey()
        
        // 移除NSEvent监听器
        unregisterNSEventMonitors()
        
        // 重置状态
        isRegistered = false
        hasRequestedPermission = false
        
        print("✅ 全局快捷键已注销")
    }
    
    deinit {
        unregister()
        print("🧹 Hotkey 实例已释放")
    }
}