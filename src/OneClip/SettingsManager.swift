import Foundation
import SwiftUI

/// 应用设置数据结构
struct AppSettings: Codable {
    var showInDock: Bool
    var maxItems: Int
    var enableHistoryPersistence: Bool
    var autoStartOnLogin: Bool
    var isFirstLaunch: Bool
    var hasShownWelcome: Bool
    var hasShownPermissionPrompt: Bool
    
    var previewSize: String
    var showLineNumbers: Bool
    var enableAnimations: Bool

    var showInMenuBar: Bool
    var enableNotifications: Bool
    var maxImageSize: Double
    var compressionQuality: Double
    var monitoringInterval: Double
    var autoCleanupDays: Int
    var themeMode: String
    var keepWindowOnTop: Bool
    
    init() {
        showInDock = false
        maxItems = 50
        enableHistoryPersistence = true
        autoStartOnLogin = false
        isFirstLaunch = true
        hasShownWelcome = false
        hasShownPermissionPrompt = false
        
        previewSize = "medium"
        showLineNumbers = false
        enableAnimations = true

        showInMenuBar = true
        enableNotifications = false
        maxImageSize = 1024.0
        compressionQuality = 0.8
        monitoringInterval = 0.6 // Default to 0.6 seconds
        autoCleanupDays = 30
        themeMode = "system"
        keepWindowOnTop = false
    }
}

/// 设置管理器 - 处理所有应用设置的读取、保存和管理
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // MARK: - 发布属性，用于 SwiftUI 绑定
    @Published var showInDock: Bool = false {
        didSet { saveSettings() }
    }
    
    @Published var maxItems: Int = 50 {
        didSet { saveSettings() }
    }
    
    @Published var enableHistoryPersistence: Bool = true {
        didSet { saveSettings() }
    }
    
    @Published var autoStartOnLogin: Bool = false {
        didSet { 
            saveSettings()
            // LaunchAtLoginManager将在OneClipApp中处理
        }
    }
    
    @Published var isFirstLaunch: Bool = true {
        didSet { saveSettings() }
    }
    
    @Published var hasShownWelcome: Bool = false {
        didSet { saveSettings() }
    }
    
    @Published var hasShownPermissionPrompt: Bool = false {
        didSet { saveSettings() }
    }
    
    // 新增缺失的发布属性
    @Published var previewSize: String = "medium" {
        didSet { saveSettings() }
    }
    
    @Published var showLineNumbers: Bool = false {
        didSet { saveSettings() }
    }
    
    @Published var enableAnimations: Bool = true {
        didSet { saveSettings() }
    }
    

    

    
    @Published var showInMenuBar: Bool = true {
        didSet { saveSettings() }
    }
    
    @Published var enableNotifications: Bool = false {
        didSet { 
            saveSettings()
            // 当关闭通知时，立即清除dock栏的红标
            if !enableNotifications {
                // NotificationManager.shared.clearBadge()
            }
        }
    }
    
    @Published var maxImageSize: Double = 1024.0 {
        didSet { saveSettings() }
    }
    
    @Published var compressionQuality: Double = 0.8 {
        didSet { saveSettings() }
    }
    
    @Published var monitoringInterval: Double = 0.6 {
        didSet { saveSettings() }
    }
    
    @Published var autoCleanupDays: Int = 30 {
        didSet { saveSettings() }
    }
    
    @Published var themeMode: String = "system" {
        didSet { 
            saveSettings()
            applyTheme()
        }
    }
    
    @Published var keepWindowOnTop: Bool = false {
        didSet { 
            saveSettings()
            // 通知WindowManager更新窗口置顶状态
            NotificationCenter.default.post(name: NSNotification.Name("WindowOnTopChanged"), object: keepWindowOnTop)
        }
    }
    
    // MARK: - 私有属性
    private let logger = Logger.shared
    private let settingsURL: URL
    
    // MARK: - 初始化
    private init() {
        // 使用 Application Support 目录
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oneClipDir = appSupportPath.appendingPathComponent("OneClip")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: oneClipDir, withIntermediateDirectories: true, attributes: nil)
        
        settingsURL = oneClipDir.appendingPathComponent("settings.json")
        
        // 执行数据迁移
        migrateSettingsIfNeeded()
        
        loadSettings()
        
        logger.info("SettingsManager initialized")
    }
    
    // MARK: - 公共方法
    
    /// 标记首次启动已完成
    func markFirstLaunchCompleted() {
        logger.info("Marking first launch as completed")
        isFirstLaunch = false
    }
    
    /// 标记欢迎页面已显示
    func markWelcomeShown() {
        logger.info("Marking welcome as shown")
        hasShownWelcome = true
    }
    
    /// 标记权限提示已显示
    func markPermissionPromptShown() {
        logger.info("Marking permission prompt as shown")
        hasShownPermissionPrompt = true
    }
    
    /// 重置到默认设置
    func resetToDefaults() {
        logger.info("Resetting settings to defaults")
        let defaults = AppSettings()
        DispatchQueue.main.async {
            self.showInDock = defaults.showInDock
            self.maxItems = defaults.maxItems
            self.enableHistoryPersistence = defaults.enableHistoryPersistence
            self.autoStartOnLogin = defaults.autoStartOnLogin
            self.isFirstLaunch = defaults.isFirstLaunch
            self.hasShownWelcome = defaults.hasShownWelcome
            self.hasShownPermissionPrompt = defaults.hasShownPermissionPrompt
            
            self.previewSize = defaults.previewSize
            self.showLineNumbers = defaults.showLineNumbers
            self.enableAnimations = defaults.enableAnimations

            self.showInMenuBar = defaults.showInMenuBar
            self.enableNotifications = defaults.enableNotifications
            self.maxImageSize = defaults.maxImageSize
            self.compressionQuality = defaults.compressionQuality
            self.monitoringInterval = defaults.monitoringInterval
            self.autoCleanupDays = defaults.autoCleanupDays
            self.themeMode = defaults.themeMode
            self.keepWindowOnTop = defaults.keepWindowOnTop
            
            self.applyTheme()
        }
    }
    
    // 高级功能相关方法已暂时禁用
    /*
    /// 导出数据到文件
    func exportData() -> URL? {
        logger.info("Exporting settings data")
        var settings = AppSettings()
        settings.showInDock = showInDock
        settings.maxItems = maxItems
        settings.enableHistoryPersistence = enableHistoryPersistence
        settings.autoStartOnLogin = autoStartOnLogin
        settings.isFirstLaunch = isFirstLaunch
        settings.hasShownWelcome = hasShownWelcome
        settings.hasShownPermissionPrompt = hasShownPermissionPrompt
        settings.previewSize = previewSize
        settings.showLineNumbers = showLineNumbers
        settings.enableAnimations = enableAnimations
        settings.showInMenuBar = showInMenuBar
        settings.enableNotifications = enableNotifications
        settings.maxImageSize = maxImageSize
        settings.compressionQuality = compressionQuality
        settings.monitoringInterval = monitoringInterval
        settings.autoCleanupDays = autoCleanupDays
        settings.themeMode = themeMode
        settings.keepWindowOnTop = keepWindowOnTop
        
        do {
            let data = try JSONEncoder().encode(settings)
            let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let oneClipDir = appSupportPath.appendingPathComponent("OneClip")
            let exportURL = oneClipDir.appendingPathComponent("settings_export.json")
            try data.write(to: exportURL)
            return exportURL
        } catch {
            logger.error("Failed to export settings: \(error)")
            return nil
        }
    }
    
    /// 从文件导入数据
    func importData(from url: URL) -> Bool {
        logger.info("Importing settings data from: \(url)")
        do {
            let data = try Data(contentsOf: url)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            
            DispatchQueue.main.async {
                self.showInDock = settings.showInDock
                self.maxItems = settings.maxItems
                self.enableHistoryPersistence = settings.enableHistoryPersistence
                self.autoStartOnLogin = settings.autoStartOnLogin
                self.isFirstLaunch = settings.isFirstLaunch
                self.hasShownWelcome = settings.hasShownWelcome
                self.hasShownPermissionPrompt = settings.hasShownPermissionPrompt
                
                self.previewSize = settings.previewSize
                self.showLineNumbers = settings.showLineNumbers
                self.enableAnimations = settings.enableAnimations

                self.showInMenuBar = settings.showInMenuBar
                self.enableNotifications = settings.enableNotifications
                self.maxImageSize = settings.maxImageSize
                self.compressionQuality = settings.compressionQuality
                self.monitoringInterval = settings.monitoringInterval
                self.autoCleanupDays = settings.autoCleanupDays
                self.themeMode = settings.themeMode
                self.keepWindowOnTop = settings.keepWindowOnTop
                
                self.applyTheme()
            }
            
            return true
        } catch {
            logger.error("Failed to import settings: \(error)")
            return false
        }
    }
    */
    
    // MARK: - 私有方法
    
    /// 迁移设置文件（如果需要）
    private func migrateSettingsIfNeeded() {
        // 检查旧位置是否存在设置文件
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldSettingsURL = documentsPath.appendingPathComponent("settings.json")
        
        // 如果新位置已经有文件，或者旧位置没有文件，则不需要迁移
        guard !FileManager.default.fileExists(atPath: settingsURL.path),
              FileManager.default.fileExists(atPath: oldSettingsURL.path) else {
            return
        }
        
        do {
            // 复制文件到新位置
            try FileManager.default.copyItem(at: oldSettingsURL, to: settingsURL)
            logger.info("Settings file migrated from Documents to Application Support")
            
            // 删除旧文件
            try FileManager.default.removeItem(at: oldSettingsURL)
            logger.info("Old settings file removed from Documents")
        } catch {
            logger.error("Failed to migrate settings file: \(error)")
        }
    }
    
    /// 加载设置
    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            logger.info("Settings file not found, using defaults")
            applyTheme()
            return
        }
        
        do {
            let data = try Data(contentsOf: settingsURL)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            
            DispatchQueue.main.async {
                self.showInDock = settings.showInDock
                self.maxItems = settings.maxItems
                self.enableHistoryPersistence = settings.enableHistoryPersistence
                self.autoStartOnLogin = settings.autoStartOnLogin
                self.isFirstLaunch = settings.isFirstLaunch
                self.hasShownWelcome = settings.hasShownWelcome
                self.hasShownPermissionPrompt = settings.hasShownPermissionPrompt
                
                self.previewSize = settings.previewSize
                self.showLineNumbers = settings.showLineNumbers
                self.enableAnimations = settings.enableAnimations

                self.showInMenuBar = settings.showInMenuBar
                self.enableNotifications = settings.enableNotifications
                self.maxImageSize = settings.maxImageSize
                self.compressionQuality = settings.compressionQuality
                self.monitoringInterval = settings.monitoringInterval
                self.autoCleanupDays = settings.autoCleanupDays
                self.themeMode = settings.themeMode
                self.keepWindowOnTop = settings.keepWindowOnTop
            }
            
            applyTheme()
            logger.info("Settings loaded successfully")
        } catch {
            logger.error("Failed to load settings: \(error)")
            applyTheme()
        }
    }
    
    /// 保存设置
    private func saveSettings() {
        var settings = AppSettings()
        settings.showInDock = showInDock
        settings.maxItems = maxItems
        settings.enableHistoryPersistence = enableHistoryPersistence
        settings.autoStartOnLogin = autoStartOnLogin
        settings.isFirstLaunch = isFirstLaunch
        settings.hasShownWelcome = hasShownWelcome
        settings.hasShownPermissionPrompt = hasShownPermissionPrompt
        settings.previewSize = previewSize
        settings.showLineNumbers = showLineNumbers
        settings.enableAnimations = enableAnimations
        settings.showInMenuBar = showInMenuBar
        settings.enableNotifications = enableNotifications
        settings.maxImageSize = maxImageSize
        settings.compressionQuality = compressionQuality
        settings.monitoringInterval = monitoringInterval
        settings.autoCleanupDays = autoCleanupDays
        settings.themeMode = themeMode
        settings.keepWindowOnTop = keepWindowOnTop
        
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL)
            logger.info("Settings saved successfully")
        } catch {
            logger.error("Failed to save settings: \(error)")
        }
    }
    
    /// 应用主题
    private func applyTheme() {
        DispatchQueue.main.async {
            switch self.themeMode {
            case "light":
                NSApp.appearance = NSAppearance(named: .aqua)
            case "dark":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            case "system", "auto":
                NSApp.appearance = nil
            default:
                NSApp.appearance = nil
            }
            
            self.logger.info("主题已切换到: \(self.themeMode)")
        }
    }
}
