import SwiftUI
import AppKit

class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()
    
    @Published var showFeedback = false
    @Published var feedbackMessage = ""
    
    private init() {}
    
    // MARK: - 简化的反馈方法
    
    func showCopyFeedback() {
        print("已复制到剪贴板")
    }
    
    func showDeleteFeedback() {
        print("已删除项目")
    }
    
    func showClearFeedback() {
        print("已清空历史记录")
    }
    
    func showSuccess(_ message: String) {
        print("✅ \(message)")
    }
    
    func showError(_ message: String) {
        print("❌ \(message)")
    }
    
    func showErrorFeedback(_ error: Error) {
        print("❌ 错误: \(error.localizedDescription)")
    }
}