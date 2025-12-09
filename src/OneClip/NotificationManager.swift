import Foundation
import UserNotifications
import AppKit

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    // Badge 计数器
    @Published var badgeCount: Int = 0
    
    private init() {
        // 确保应用启动时 badge 数量为 0
        badgeCount = 0
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        print("🔔 开始请求通知权限...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let error = error {
                    print("❌ 通知权限请求失败: \(error.localizedDescription)")
                } else if granted {
                    print("✅ 通知权限已授予")
                } else {
                    print("❌ 通知权限被用户拒绝")
                    print("💡 提示：请在系统偏好设置 > 通知 > OneClip 中启用通知")
                }
            }
        }
    }
    
    func showClipboardNotification(content: String) {
        print("📢 NotificationManager: 收到通知请求，内容: \(String(content.prefix(20)))...")
        
        // 检查设置是否启用通知
        guard SettingsManager.shared.enableNotifications else {
            print("❌ 通知已在设置中禁用")
            return
        }
        
        print("✅ 通知设置已启用，继续处理...")
        
        // 检查通知权限
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("🔍 当前通知权限状态: \(settings.authorizationStatus.rawValue)")
                print("🔍 通知中心设置: \(settings.notificationCenterSetting.rawValue)")
                print("🔍 锁屏设置: \(settings.lockScreenSetting.rawValue)")
                print("🔍 横幅设置: \(settings.alertSetting.rawValue)")
                
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    print("✅ 通知权限已授权，发送通知")
                    self.sendNotification(content: content)
                case .denied:
                    print("❌ 通知权限被拒绝，请在系统设置中启用")
                case .notDetermined:
                    print("⚠️ 通知权限未确定，重新请求权限")
                    self.requestNotificationPermission()
                    // 权限请求后再次尝试发送
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.sendNotification(content: content)
                    }
                @unknown default:
                    print("❓ 未知的通知权限状态")
                }
            }
        }
    }
    
    private func sendNotification(content: String) {
        print("🚀 开始发送通知...")
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "新的剪贴板内容"
        notificationContent.body = String(content.prefix(50)) + (content.count > 50 ? "..." : "")
        notificationContent.sound = .default
        
        // 获取实际的未读数量来设置 badge
        let unreadCount = ClipboardManager.shared.unreadCount
        badgeCount = unreadCount
        notificationContent.badge = NSNumber(value: badgeCount)
        notificationContent.categoryIdentifier = "CLIPBOARD_CATEGORY"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil // 立即显示
        )
        
        print("📤 发送通知请求: \(request.identifier)")
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 通知发送失败: \(error.localizedDescription)")
                } else {
                    print("✅ 通知发送成功，badge 数量: \(self.badgeCount)")
                    // 同步更新 Dock 图标的 badge
                    self.setBadgeCount(self.badgeCount)
                }
            }
        }
    }
    
    func checkNotificationPermission() -> Bool {
        var isAuthorized = false
        let semaphore = DispatchSemaphore(value: 0)
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            isAuthorized = settings.authorizationStatus == .authorized
            semaphore.signal()
        }
        
        semaphore.wait()
        return isAuthorized
    }
    
    // 清除 badge 数量
    func clearBadge() {
        print("🔔 清除应用 badge 数量")
        badgeCount = 0
        
        // 清除应用图标上的 badge
        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = nil
        }
        
        // 清除通知中心的 badge
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("❌ 清除通知 badge 失败: \(error.localizedDescription)")
            } else {
                print("✅ 通知 badge 已清除")
            }
        }
    }
    
    // 设置 badge 数量
    func setBadgeCount(_ count: Int) {
        print("🔔 设置 badge 数量为: \(count)")
        badgeCount = count
        
        // 只有在启用通知时才显示红标
        guard SettingsManager.shared.enableNotifications else {
            print("❌ 通知已禁用，不显示 badge")
            DispatchQueue.main.async {
                NSApp.dockTile.badgeLabel = nil
            }
            return
        }
        
        DispatchQueue.main.async {
            if count > 0 {
                NSApp.dockTile.badgeLabel = "\(count)"
            } else {
                NSApp.dockTile.badgeLabel = nil
            }
        }
        
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("❌ 设置通知 badge 失败: \(error.localizedDescription)")
            } else {
                print("✅ 通知 badge 已设置为: \(count)")
            }
        }
    }
}
