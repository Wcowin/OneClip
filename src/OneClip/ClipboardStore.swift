import Foundation
import AppKit
import Combine

class ClipboardStore: ObservableObject {
    struct StorageInfo {
        let itemCount: Int
        let totalSize: Int64
        let cachePath: String
    }
    
    private let fileManager = FileManager.default
    private let maxItems = 100 // 最大项目数量
    
    // 文件存储配置
    private let storageDirectory: URL
    private let maxStorageSize: Int64 = 500 * 1024 * 1024 // 500MB最大存储
    
    // 获取清理天数的闭包
    private var getCleanupDays: () -> Int
    
    // 计算清理时间间隔
    private var maxFileAge: TimeInterval {
        return TimeInterval(getCleanupDays() * 24 * 60 * 60)
    }
    
    // 日期格式化器
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    init(getCleanupDays: @escaping () -> Int = { 30 }) {
        self.getCleanupDays = getCleanupDays
        
        // 创建专用的存储目录
        let documentsURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDirectory = documentsURL.appendingPathComponent("OneClip", isDirectory: true)
        
        // 创建存储目录
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // 只有在启用自动清理时才启动定期清理
        if getCleanupDays() > 0 {
            schedulePeriodicCleanup()
        }
    }
    
    // MARK: - 日期分类存储方法
    
    /// 获取今天的存储文件夹
    private func getTodayStorageDirectory() -> URL {
        let today = dateFormatter.string(from: Date())
        return storageDirectory.appendingPathComponent(today, isDirectory: true)
    }
    
    /// 获取指定日期的存储文件夹
    private func getStorageDirectory(for date: Date) -> URL {
        let dateString = dateFormatter.string(from: date)
        return storageDirectory.appendingPathComponent(dateString, isDirectory: true)
    }
    
    /// 确保日期文件夹存在
    private func ensureDateDirectoryExists(for date: Date) -> URL {
        let dateDirectory = getStorageDirectory(for: date)
        try? fileManager.createDirectory(at: dateDirectory, withIntermediateDirectories: true, attributes: nil)
        return dateDirectory
    }
    
    // MARK: - 核心存储方法
    
    func saveItem(_ item: ClipboardItem) {
        var items = loadItems()
        
        // 移除重复项
        items.removeAll { $0.id == item.id }
        
        // 处理所有数据的持久化存储（统一存储到日期文件夹）
        let processedItem = processPersistentStorage(for: item)
        
        // 添加到列表开头
        items.insert(processedItem, at: 0)
        
        // 限制项目数量
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        // 保存到存储
        saveItems(items)
    }
    
    func loadItems() -> [ClipboardItem] {
        var allItems: [ClipboardItem] = []
        
        do {
            // 获取所有日期文件夹
            let dateDirectories = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            // 按日期排序（最新的在前）
            let sortedDirectories = dateDirectories.sorted { dir1, dir2 in
                guard let date1 = try? dir1.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      let date2 = try? dir2.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return false
                }
                return date1 > date2
            }
            
            // 从每个日期文件夹加载项目
            for dateDirectory in sortedDirectories {
                let itemsFile = dateDirectory.appendingPathComponent("items.json")
                if fileManager.fileExists(atPath: itemsFile.path) {
                    let data = try Data(contentsOf: itemsFile)
                    let items = try JSONDecoder().decode([ClipboardItem].self, from: data)
                    allItems.append(contentsOf: items)
                }
            }
            
            // 按时间戳排序（最新的在前）
            allItems.sort { $0.timestamp > $1.timestamp }
            
            // 限制总数量
            if allItems.count > maxItems {
                allItems = Array(allItems.prefix(maxItems))
            }
            
        } catch {
            print("加载剪贴板项目失败: \(error)")
        }
        
        return allItems
    }
    
    func clearAllItems() {
        do {
            // 1. 先获取所有收藏项目
            let allItems = loadItems()
            let favoriteItems = allItems.filter { $0.isFavorite }
            
            // 2. 删除所有日期文件夹
            let dateDirectories = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for dateDirectory in dateDirectories {
                try fileManager.removeItem(at: dateDirectory)
            }
            
            // 3. 重新保存收藏项目
            for favoriteItem in favoriteItems {
                saveItem(favoriteItem)
            }
            
            print("所有剪贴板项目已清空，保留了 \(favoriteItems.count) 个收藏项目")
        } catch {
            print("清空剪贴板项目失败: \(error)")
        }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        var allItems = loadItems()
        allItems.removeAll { $0.id == item.id }
        
        // 重新保存所有项目
        clearAllItems()
        for item in allItems {
            saveItem(item)
        }
    }
    
    // MARK: - 私有辅助方法
    
    private func saveItems(_ items: [ClipboardItem]) {
        // 按日期分组保存项目
        let groupedItems = Dictionary(grouping: items) { item in
            dateFormatter.string(from: item.timestamp)
        }
        
        for (dateString, dateItems) in groupedItems {
            let dateDirectory = storageDirectory.appendingPathComponent(dateString, isDirectory: true)
            
            do {
                // 确保日期目录存在
                try fileManager.createDirectory(at: dateDirectory, withIntermediateDirectories: true, attributes: nil)
                
                // 保存项目到JSON文件
                let itemsFile = dateDirectory.appendingPathComponent("items.json")
                let data = try JSONEncoder().encode(dateItems)
                try data.write(to: itemsFile)
                
            } catch {
                print("保存日期项目失败 \(dateString): \(error)")
            }
        }
    }
    
    private func processPersistentStorage(for item: ClipboardItem) -> ClipboardItem {
        var processedItem = item
        
        // 为图片和文件类型处理持久化存储
        switch item.type {
        case .image:
            if let imageData = item.data {
                let dateDirectory = ensureDateDirectoryExists(for: item.timestamp)
                let imageFileName = "\(item.id.uuidString).png"
                let imageURL = dateDirectory.appendingPathComponent(imageFileName)
                
                do {
                    try imageData.write(to: imageURL)
                    processedItem.filePath = imageURL.path
                    // 清除内存中的数据，使用文件路径
                    processedItem.data = nil
                } catch {
                    print("保存图片文件失败: \(error)")
                }
            }
            
        case .file:
            if let fileData = item.data {
                let dateDirectory = ensureDateDirectoryExists(for: item.timestamp)
                let fileName = item.content.components(separatedBy: "/").last ?? "unknown_file"
                let fileURL = dateDirectory.appendingPathComponent(fileName)
                
                do {
                    try fileData.write(to: fileURL)
                    processedItem.filePath = fileURL.path
                    // 清除内存中的数据，使用文件路径
                    processedItem.data = nil
                } catch {
                    print("保存文件失败: \(error)")
                }
            }
            
        default:
            // 文本类型不需要额外处理
            break
        }
        
        return processedItem
    }
    
    // MARK: - 存储信息和清理方法
    
    func getStorageInfo() -> StorageInfo {
        var totalSize: Int64 = 0
        var itemCount = 0
        
        // 确保存储目录存在
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        do {
            let dateDirectories = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: .skipsHiddenFiles)
            
            for dateDirectory in dateDirectories {
                // 检查是否是目录
                let resourceValues = try? dateDirectory.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    let files = try fileManager.contentsOfDirectory(at: dateDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
                    
                    for file in files {
                        if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(fileSize)
                        }
                        
                        if file.pathExtension == "json" {
                            // 计算JSON文件中的项目数量
                            if let data = try? Data(contentsOf: file),
                               let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                                itemCount += items.count
                            }
                        }
                    }
                }
            }
        } catch {
            #if DEBUG
            print("获取存储信息失败: \(error)")
            print("存储目录路径: \(storageDirectory.path)")
            #endif
        }
        
        return StorageInfo(itemCount: itemCount, totalSize: totalSize, cachePath: storageDirectory.path)
    }
    
    func performManualCleanup() {
        // 手动清理：删除所有存储的数据
        do {
            // 删除整个存储目录
            if fileManager.fileExists(atPath: storageDirectory.path) {
                try fileManager.removeItem(at: storageDirectory)
                print("已删除所有存储数据")
            }
            
            // 重新创建空的存储目录
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
            print("已重新创建存储目录")
            
        } catch {
            print("手动清理失败: \(error)")
            // 如果删除失败，尝试清理所有子目录
            cleanupAllFiles()
        }
    }
    
    // 清理所有文件的备用方法
    private func cleanupAllFiles() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for item in contents {
                try fileManager.removeItem(at: item)
                print("已删除: \(item.lastPathComponent)")
            }
        } catch {
            print("清理所有文件失败: \(error)")
        }
    }
    
    private func schedulePeriodicCleanup() {
        // 每小时执行一次清理，但只有在启用自动清理时才执行
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self = self, self.getCleanupDays() > 0 else {
                return // 如果自动清理被禁用，则跳过清理
            }
            self.cleanupOldFiles()
        }
    }
    
    private func cleanupOldFiles() {
        let cutoffDate = Date().addingTimeInterval(-maxFileAge)
        
        do {
            let dateDirectories = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            for dateDirectory in dateDirectories {
                if let creationDate = try? dateDirectory.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try fileManager.removeItem(at: dateDirectory)
                    print("已清理过期文件夹: \(dateDirectory.lastPathComponent)")
                }
            }
        } catch {
            print("清理过期文件失败: \(error)")
        }
    }
    
    private func cleanupLargeStorage() {
        let storageInfo = getStorageInfo()
        
        if storageInfo.totalSize > maxStorageSize {
            // 如果存储超过限制，删除最旧的文件夹
            do {
                let dateDirectories = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                
                let sortedDirectories = dateDirectories.sorted { dir1, dir2 in
                    guard let date1 = try? dir1.resourceValues(forKeys: [.creationDateKey]).creationDate,
                          let date2 = try? dir2.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                        return false
                    }
                    return date1 < date2 // 最旧的在前
                }
                
                // 删除最旧的文件夹直到存储大小合理
                for directory in sortedDirectories {
                    try fileManager.removeItem(at: directory)
                    print("已清理存储文件夹: \(directory.lastPathComponent)")
                    
                    let newStorageInfo = getStorageInfo()
                    if newStorageInfo.totalSize <= maxStorageSize * 8 / 10 { // 清理到80%
                        break
                    }
                }
            } catch {
                print("清理大存储失败: \(error)")
            }
        }
    }
}