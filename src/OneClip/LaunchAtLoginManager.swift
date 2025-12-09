import Foundation
import ServiceManagement

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    private let bundleIdentifier = "com.yourcompany.OneClip"
    
    private init() {}
    
    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            // 使用新的API
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("设置开机启动失败: \(error)")
            }
        } else {
            // 使用旧的API (macOS 12及以下)
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
            if !success {
                print("设置开机启动失败 (旧版本API)")
            }
        }
    }
    
    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // 对于旧版本，检查登录项
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
}
