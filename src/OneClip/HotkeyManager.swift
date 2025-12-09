import Foundation
import AppKit

class HotkeyManager: ObservableObject {
    private var hotkeys: [Hotkey] = []
    private let logger = Logger.shared
    private var clipboardManager: ClipboardManager?
    private var windowManager: WindowManager?
    
    func setupGlobalHotkeys(
        onToggleWindow: @escaping () -> Void,
        clipboardManager: ClipboardManager? = nil,
        windowManager: WindowManager? = nil
    ) {
        self.clipboardManager = clipboardManager
        self.windowManager = windowManager
        
        // 清除现有快捷键
        clearHotkeys()
        
        do {
            // 全局快捷键: Ctrl+Cmd+V (显示/隐藏窗口)
            let mainHotkey = try createHotkey(
                keyCode: 9, // V键
                modifierFlags: [.command, .control],
                action: onToggleWindow,
                description: "显示/隐藏窗口",
                hotkeyID: 1001
            )
            
            hotkeys.append(mainHotkey)
            
            logger.info("全局快捷键已设置 - Ctrl+Cmd+V")
            
        } catch {
            logger.error("设置全局快捷键失败: \(error.localizedDescription)")
        }
    }
    
    private func createHotkey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, action: @escaping () -> Void, description: String, hotkeyID: UInt32) throws -> Hotkey {
        let hotkey = Hotkey(keyCode: keyCode, modifierFlags: modifierFlags, callback: action, hotkeyID: hotkeyID)
        
        // 直接注册，让 Hotkey 类自己处理权限
        hotkey.register()
        logger.info("注册快捷键: \(description)")
        
        return hotkey
    }
    
    private func clearHotkeys() {
        hotkeys.forEach { $0.unregister() }
        hotkeys.removeAll()
        logger.info("已清除所有快捷键")
    }
    
    deinit {
        clearHotkeys()
        logger.info("HotkeyManager 已释放")
    }
}