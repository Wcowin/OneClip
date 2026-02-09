import Foundation
import Cocoa

/// 优化的辅助功能权限管理器
/// 统一管理权限检查，减少重复调用和延迟
class AccessibilityPermissionManager: ObservableObject {
    static let shared = AccessibilityPermissionManager()
    
    // MARK: - Properties
    @Published private(set) var hasPermission: Bool = false
    @Published private(set) var isChecking: Bool = false
    
    private var permissionCache: Bool?
    private var lastCheckTime: Date = Date(timeIntervalSince1970: 0)
    private var observers: [() -> Void] = []
    private var permissionTimer: Timer?
    
    // 缓存有效期：1秒（减少频繁检查）
    private let cacheValidDuration: TimeInterval = 1.0
    // 监控间隔：优化到2秒
    private let monitoringInterval: TimeInterval = 2.0
    
    private init() {
        // 初始检查
        checkPermissionAsync()
    }
    
    // MARK: - Public Methods
    
    /// 异步检查权限状态（推荐使用）
    func checkPermissionAsync(completion: ((Bool) -> Void)? = nil) {
        // 如果缓存仍有效，直接返回缓存结果
        if let cached = permissionCache,
           Date().timeIntervalSince(lastCheckTime) < cacheValidDuration {
            completion?(cached)
            return
        }
        
        // 防止重复检查
        guard !isChecking else {
            completion?(hasPermission)
            return
        }
        
        isChecking = true
        
        // 在后台队列检查权限
        DispatchQueue.global(qos: .userInitiated).async {
            let permission = AXIsProcessTrusted()
            
            DispatchQueue.main.async {
                self.updatePermissionStatus(permission)
                self.isChecking = false
                completion?(permission)
            }
        }
    }
    
    /// 同步检查权限状态（仅在必要时使用）
    func checkPermissionSync() -> Bool {
        // 如果缓存仍有效，直接返回缓存结果
        if let cached = permissionCache,
           Date().timeIntervalSince(lastCheckTime) < cacheValidDuration {
            return cached
        }
        
        let permission = AXIsProcessTrusted()
        updatePermissionStatus(permission)
        return permission
    }
    
    /// 开始监控权限变化
    func startMonitoring() {
        stopMonitoring()
        
        #if DEBUG
        print("开始监控辅助功能权限（间隔: \(monitoringInterval)秒）")
        #endif
        
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkPermissionAsync()
        }
    }
    
    /// 停止监控权限变化
    func stopMonitoring() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        
        #if DEBUG
        print("停止监控辅助功能权限")
        #endif
    }
    
    /// 添加权限变化观察者
    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }
    
    /// 清除所有观察者
    func clearObservers() {
        observers.removeAll()
    }
    
    /// 请求辅助功能权限（仅检查，不显示弹窗）
    /// - Parameter showPrompt: 已废弃，权限弹窗统一由OneClipApp管理
    /// - Returns: 当前权限状态
    @discardableResult
    func requestPermission(showPrompt: Bool = false) -> Bool {
        print("[AccessibilityPermissionManager] 检查权限状态（不弹窗）")
        
        // 只检查权限状态，不显示弹窗
        let hasPermission = AXIsProcessTrusted()
        updatePermissionStatus(hasPermission)
        
        print("[AccessibilityPermissionManager] 权限检查结果: \(hasPermission)")
        return hasPermission
    }
    
    /// 静默检查权限（不显示对话框）
    func checkPermissionSilent() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        let permission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        updatePermissionStatus(permission)
        return permission
    }
    
    /// 强制显示权限对话框（已废弃，权限弹窗统一由OneClipApp管理）
    func forceShowPermissionDialog() {
        print("[AccessibilityPermissionManager] 强制权限检查（不弹窗，统一由OneClipApp管理）")
        
        // 只检查权限状态，不显示弹窗
        let hasPermission = AXIsProcessTrusted()
        updatePermissionStatus(hasPermission)
        
        print("[AccessibilityPermissionManager] 权限检查结果: \(hasPermission)")
        
        // 如果需要弹窗，通知OneClipApp处理
        if !hasPermission {
            print("[AccessibilityPermissionManager] 缺少权限，建议通过OneClipApp统一处理弹窗")
        }
    }
    
    // MARK: - Private Methods
    
    private func updatePermissionStatus(_ newStatus: Bool) {
        let oldStatus = hasPermission
        hasPermission = newStatus
        permissionCache = newStatus
        lastCheckTime = Date()
        
        // 如果状态发生变化，通知观察者
        if oldStatus != newStatus {
            #if DEBUG
            print("辅助功能权限状态变化: \(oldStatus ? "已授权" : "未授权") → \(newStatus ? "已授权" : "未授权")")
            #endif
            
            notifyObservers()
        }
    }
    
    private func notifyObservers() {
        for observer in observers {
            observer()
        }
    }
    
    // MARK: - Deinit
    
    deinit {
        stopMonitoring()
        clearObservers()
    }
}

// MARK: - Convenience Extensions

extension AccessibilityPermissionManager {
    /// 便捷方法：检查权限并在变化时执行回调
    func checkAndNotify(onChange: @escaping (Bool) -> Void) {
        checkPermissionAsync { hasPermission in
            onChange(hasPermission)
        }
    }
    
    /// 便捷方法：等待权限授权
    func waitForPermission(timeout: TimeInterval = 30.0, completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        
        func checkRecursively() {
            checkPermissionAsync { hasPermission in
                if hasPermission {
                    completion(true)
                } else if Date().timeIntervalSince(startTime) < timeout {
                    // 继续等待
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        checkRecursively()
                    }
                } else {
                    // 超时
                    completion(false)
                }
            }
        }
        
        checkRecursively()
    }
}
