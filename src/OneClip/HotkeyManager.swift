import Foundation
import AppKit

class HotkeyManager: ObservableObject {
    private var hotkeys: [Hotkey] = []
    private let logger = Logger.shared
    private var clipboardManager: ClipboardManager?
    private var windowManager: WindowManager?
    private var registeredHotkeyCount = 0
    
    func setupGlobalHotkeys(
        onToggleWindow: @escaping () -> Void,
        clipboardManager: ClipboardManager? = nil,
        windowManager: WindowManager? = nil
    ) {
        self.clipboardManager = clipboardManager
        self.windowManager = windowManager
        
        // 清除现有快捷键
        clearHotkeys()
        registeredHotkeyCount = 0
        
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
            registeredHotkeyCount += 1
            
            logger.info("全局快捷键已设置 - Ctrl+Cmd+V")
            
            // 🔧 修复：验证快捷键是否成功注册
            if registeredHotkeyCount == 1 {
                logger.info("✅ 快捷键注册成功 (共 \(registeredHotkeyCount) 个)")
            } else {
                logger.warning("⚠️ 快捷键注册可能不完整，预期1个，实际\(registeredHotkeyCount)个")
            }
            
        } catch {
            logger.error("❌ 设置全局快捷键失败: \(error.localizedDescription)")
            
            // 提供更详细的错误信息
            if registeredHotkeyCount == 0 {
                logger.error("未注册任何快捷键，快捷键功能不可用。请检查系统权限（辅助功能）")
            }
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
    
    // 🔧 修复：添加快捷键状态检查方法
    /// 检查快捷键是否已成功注册
    func isHotkeyRegistered(hotkeyID: UInt32) -> Bool {
        return hotkeys.contains { $0.hotkeyID == hotkeyID }
    }
    
    /// 获取已注册快捷键的总数
    func getRegisteredHotkeyCount() -> Int {
        return registeredHotkeyCount
    }
    
    /// 检查快捷键功能是否可用
    func isHotKeyFunctional() -> Bool {
        return registeredHotkeyCount > 0 && !hotkeys.isEmpty
    }
    
    deinit {
        clearHotkeys()
        logger.info("HotkeyManager 已释放")
    }
}