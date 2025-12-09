import Foundation

enum ClipboardItemType: String, Codable {
    case text = "text"
    case image = "image"
    case file = "file"
    case video = "video"
    case audio = "audio"
    case document = "document"
    case code = "code"
    case archive = "archive"
    case executable = "executable"
}

extension ClipboardItemType {
    var icon: String {
        switch self {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .video:
            return "video"
        case .audio:
            return "music.note"
        case .document:
            return "doc.text"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .archive:
            return "archivebox"
        case .executable:
            return "app"
        }
    }
    
    var displayName: String {
        switch self {
        case .text:
            return "文本"
        case .image:
            return "图片"
        case .file:
            return "文件"
        case .video:
            return "视频"
        case .audio:
            return "音频"
        case .document:
            return "文档"
        case .code:
            return "代码"
        case .archive:
            return "压缩包"
        case .executable:
            return "应用程序"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let type: ClipboardItemType
    let timestamp: Date
    var data: Data?
    var filePath: String? // 新增：文件存储路径
    var isFavorite: Bool // 新增：收藏状态
    
    init(id: UUID, content: String, type: ClipboardItemType, timestamp: Date, data: Data? = nil, filePath: String? = nil, isFavorite: Bool = false) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.data = data
        self.filePath = filePath
        self.isFavorite = isFavorite
    }
    
    // 用于 Codable 的自定义编码
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case type
        case timestamp
        case data
        case filePath
        case isFavorite
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(ClipboardItemType.self, forKey: .type)
        
        // 处理 Date 的 JSON 序列化
        if let dateString = try? container.decode(String.self, forKey: .timestamp) {
            // 如果是字符串格式，尝试解析
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: dateString) ?? Date()
        } else if let timeInterval = try? container.decode(Double.self, forKey: .timestamp) {
            // 如果是时间戳格式
            timestamp = Date(timeIntervalSince1970: timeInterval)
        } else {
            // 默认使用当前时间
            timestamp = Date()
        }
        
        data = try container.decode(Data?.self, forKey: .data)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        
        // 将 Date 转换为 ISO8601 字符串格式
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = formatter.string(from: timestamp)
        try container.encode(dateString, forKey: .timestamp)
        
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encode(isFavorite, forKey: .isFavorite)
    }
}