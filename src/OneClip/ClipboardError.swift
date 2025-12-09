import Foundation

enum ClipboardError: LocalizedError {
    case accessDenied
    case dataCorrupted
    case storageFailure
    case imageProcessingFailed
    case permissionRequired
    case fileOperationFailed
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "剪贴板访问被拒绝"
        case .dataCorrupted:
            return "剪贴板数据损坏"
        case .storageFailure:
            return "存储操作失败"
        case .imageProcessingFailed:
            return "图像处理失败"
        case .permissionRequired:
            return "需要辅助功能权限"
        case .fileOperationFailed:
            return "文件操作失败"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accessDenied, .permissionRequired:
            return "请在系统设置中授予应用权限"
        case .dataCorrupted:
            return "请重新复制内容"
        case .storageFailure:
            return "请检查磁盘空间"
        case .imageProcessingFailed:
            return "请尝试复制其他格式的图片"
        case .fileOperationFailed:
            return "请检查文件是否存在且有权限访问"
        }
    }
}

