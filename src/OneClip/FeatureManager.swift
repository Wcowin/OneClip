import Foundation
import UserNotifications
import ServiceManagement
import Combine

/// 应用功能管理器 - 统一管理各种应用功能
class FeatureManager: ObservableObject {
    static let shared = FeatureManager()
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSettingsObservers()
        requestNotificationPermission()
    }
    
    // MARK: - 通知功能
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知权限请求失败: \(error)")
            } else if granted {
                print("通知权限已授予")
            } else {
                print("通知权限被拒绝")
            }
        }
    }
    
    @objc func showClipboardNotification(content: String) {
        // 检查设置是否启用通知
        guard SettingsManager.shared.enableNotifications else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "新的剪贴板内容"
        notificationContent.body = String(content.prefix(50)) + (content.count > 50 ? "..." : "")
        notificationContent.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil // 立即显示
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知发送失败: \(error)")
            }
        }
    }
    
    // MARK: - 开机启动功能
    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                print("开机启动设置成功: \(enabled)")
            } catch {
                print("设置开机启动失败: \(error)")
            }
        } else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.yourcompany.OneClip"
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
            if success {
                print("开机启动设置成功: \(enabled)")
            } else {
                print("设置开机启动失败 (旧版本API)")
            }
        }
    }
    
    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.yourcompany.OneClip"
            let jobDicts = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: AnyObject]]
            
            if let jobDicts = jobDicts {
                for job in jobDicts {
                    if let label = job["Label"] as? String, label == bundleIdentifier {
                        return job["OnDemand"] as? Bool == false
                    }
                }
            }
            return false
        }
    }
    
    // MARK: - 设置监听
    private func setupSettingsObservers() {
        let settings = SettingsManager.shared
        
        // 监听开机自动启动设置变化
        settings.$autoStartOnLogin
            .sink { [weak self] enabled in
                self?.setLaunchAtLogin(enabled)
            }
            .store(in: &cancellables)
    }
}
