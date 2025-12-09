//
//  UserActivityMonitor.swift
//  OneClip
//
//  Created by OneClip on 2024/01/01.
//

import Foundation
import Cocoa
import os.log

// 用户活动状态枚举
enum UserActivityState {
    case active      // 活跃状态
    case inactive    // 不活跃状态
    case sleeping    // 深度休眠状态
    
    var description: String {
        switch self {
        case .active: return "活跃"
        case .inactive: return "不活跃"
        case .sleeping: return "深度休眠"
        }
    }
}

// NSNotification.Name 扩展
extension NSNotification.Name {
    static let userBecameActive = NSNotification.Name("userBecameActive")
    static let userBecameInactive = NSNotification.Name("userBecameInactive")
}

// 用户活动监控器
class UserActivityMonitor {
    static let shared = UserActivityMonitor()
    
    private let logger = Logger.shared
    
    private var lastActivityTime: Date = Date()
    private var isMonitoring = false
    private var activityTimer: Timer?
    private var currentState: UserActivityState = .active
    private var globalEventMonitor: Any?
    
    // 监控配置
    private let checkInterval: TimeInterval = 1.0  // 每秒检查一次
    private let inactiveThreshold: TimeInterval = 60.0  // 1分钟无活动视为不活跃
    private let sleepThreshold: TimeInterval = 300.0   // 5分钟无活动视为深度休眠
    
    private init() {
        setupActivityMonitoring()
    }
    
    deinit {
        stopMonitoring()
        // 清理全局事件监听器
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        // 移除通知观察者
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // 开始监控用户活动
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastActivityTime = Date()
        
        // 设置定时器检查用户活动状态
        activityTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkActivityState()
        }
        
        logger.info("🔍 用户活动监控已启动")
    }
    
    // 停止监控
    func stopMonitoring() {
        isMonitoring = false
        activityTimer?.invalidate()
        activityTimer = nil
        
        logger.info("⏹️ 用户活动监控已停止")
    }
    
    // 获取不活跃持续时间
    func getInactivityDuration() -> TimeInterval {
        return Date().timeIntervalSince(lastActivityTime)
    }
    
    // 获取当前活动状态
    func getCurrentState() -> UserActivityState {
        return currentState
    }
    
    // 手动更新活动时间（当检测到用户操作时调用）
    func updateActivity() {
        lastActivityTime = Date()
        
        if currentState != .active {
            currentState = .active
            NotificationCenter.default.post(name: .userBecameActive, object: nil)
            logger.info("🟢 用户重新活跃")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupActivityMonitoring() {
        // 监听系统事件
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            self?.updateActivity()
        }
        
        // 监听应用激活事件
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActivity()
        }
        
        // 监听工作区切换事件
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActivity()
        }
    }
    
    private func checkActivityState() {
        let inactivityDuration = getInactivityDuration()
        let newState: UserActivityState
        
        if inactivityDuration > sleepThreshold {
            newState = .sleeping
        } else if inactivityDuration > inactiveThreshold {
            newState = .inactive
        } else {
            newState = .active
        }
        
        // 状态变化时发送通知
        if newState != currentState {
            let previousState = currentState
            currentState = newState
            
            switch newState {
            case .active:
                if previousState != .active {
                    NotificationCenter.default.post(name: .userBecameActive, object: nil)
                    logger.info("🟢 用户状态: 活跃")
                }
            case .inactive, .sleeping:
                if previousState == .active {
                    NotificationCenter.default.post(name: .userBecameInactive, object: nil)
                    logger.info("🟡 用户状态: \(newState == .sleeping ? "深度休眠" : "不活跃")")
                }
            }
        }
    }
}