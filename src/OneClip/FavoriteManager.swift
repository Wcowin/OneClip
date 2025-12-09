import Foundation
import SwiftUI

class FavoriteManager: ObservableObject {
    static let shared = FavoriteManager()
    
    @Published var favoriteItems: [ClipboardItem] = []
    
    private let favoritesDirectory: URL
    private let favoritesFile: URL
    
    private init() {
        // 创建收藏目录路径
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oneClipDirectory = appSupportURL.appendingPathComponent("OneClip")
        self.favoritesDirectory = oneClipDirectory.appendingPathComponent("Favorites")
        self.favoritesFile = favoritesDirectory.appendingPathComponent("favorites.json")
        
        // 确保目录存在
        createDirectoryIfNeeded()
        
        // 加载收藏数据
        loadFavorites()
        
        // 延迟同步收藏状态，确保ClipboardManager已初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncWithClipboardStore()
            self.syncFavoriteStatusWithClipboardManager()
        }
    }
    
    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: favoritesDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.shared.error("创建收藏目录失败: \(error.localizedDescription)")
        }
    }
    
    // 加载收藏数据
    private func loadFavorites() {
        guard FileManager.default.fileExists(atPath: favoritesFile.path) else {
            Logger.shared.info("收藏文件不存在，初始化为空列表")
            return
        }
        
        do {
            let data = try Data(contentsOf: favoritesFile)
            let decoder = JSONDecoder()
            favoriteItems = try decoder.decode([ClipboardItem].self, from: data)
            Logger.shared.info("成功加载 \(favoriteItems.count) 个收藏项目")
        } catch {
            Logger.shared.error("加载收藏数据失败: \(error.localizedDescription)")
            favoriteItems = []
        }
    }
    
    // 保存收藏数据
    private func saveFavorites() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(favoriteItems)
            try data.write(to: favoritesFile)
            Logger.shared.info("成功保存 \(favoriteItems.count) 个收藏项目")
        } catch {
            Logger.shared.error("保存收藏数据失败: \(error.localizedDescription)")
        }
    }
    
    // 添加到收藏
    func addToFavorites(_ item: ClipboardItem) {
        // 检查是否已经收藏
        if favoriteItems.contains(where: { $0.id == item.id }) {
            Logger.shared.warning("项目已在收藏列表中")
            return
        }
        
        // 创建收藏版本的项目，确保数据完整性
        let favoriteItem = ClipboardItem(
            id: item.id,
            content: item.content,
            type: item.type,
            timestamp: item.timestamp,
            data: item.data,
            filePath: item.filePath,
            isFavorite: true
        )
        
        // 直接在主线程上更新@Published属性
        favoriteItems.append(favoriteItem)
        saveFavorites()
        
        Logger.shared.info("添加到收藏: \(item.content.prefix(50))")
    }
    
    // 从收藏中移除
    func removeFromFavorites(_ item: ClipboardItem) {
        // 直接在主线程上更新@Published属性
        favoriteItems.removeAll { $0.id == item.id }
        saveFavorites()
        
        Logger.shared.info("从收藏中移除: \(item.content.prefix(50))")
    }
    
    // 切换收藏状态
    func toggleFavorite(_ item: ClipboardItem) {
        let wasFavorite = isFavorite(item)
        
        if wasFavorite {
            removeFromFavorites(item)
        } else {
            addToFavorites(item)
        }
        
        // 立即同步更新ClipboardManager中的原始项目
        updateClipboardManagerItem(item, isFavorite: !wasFavorite)
        
        Logger.shared.info("切换收藏状态: \(item.content.prefix(30)) -> \(!wasFavorite)")
    }
    
    // 同步更新ClipboardManager中的项目收藏状态
    private func updateClipboardManagerItem(_ item: ClipboardItem, isFavorite: Bool) {
        let clipboardManager = ClipboardManager.shared
        
        // 查找并更新ClipboardManager中的对应项目
        if let index = clipboardManager.clipboardItems.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = clipboardManager.clipboardItems[index]
            updatedItem.isFavorite = isFavorite
            clipboardManager.clipboardItems[index] = updatedItem
            
            // 保存更新后的项目到存储
            clipboardManager.store.saveItem(updatedItem)
            
            Logger.shared.info("同步更新ClipboardManager中的项目收藏状态: \(isFavorite)")
        }
    }
    
    // 检查是否已收藏
    func isFavorite(_ item: ClipboardItem) -> Bool {
        return favoriteItems.contains(where: { $0.id == item.id })
    }
    
    // 获取所有收藏项目
    func getAllFavorites() -> [ClipboardItem] {
        return favoriteItems.sorted { $0.timestamp > $1.timestamp }
    }
    
    // 按类型获取收藏项目
    func getFavorites(ofType type: ClipboardItemType) -> [ClipboardItem] {
        return favoriteItems.filter { $0.type == type }.sorted { $0.timestamp > $1.timestamp }
    }
    
    // 清空所有收藏
    func clearAllFavorites() {
        // 确保在主线程上更新@Published属性
        DispatchQueue.main.async {
            self.favoriteItems.removeAll()
        }
        saveFavorites()
        Logger.shared.info("清空所有收藏")
    }
    
    // 获取收藏数量
    var favoriteCount: Int {
        return favoriteItems.count
    }
    
    // 导出收藏数据
    func exportFavorites() -> URL? {
        let exportURL = favoritesDirectory.appendingPathComponent("favorites_export_\(Date().timeIntervalSince1970).json")
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(favoriteItems)
            try data.write(to: exportURL)
            Logger.shared.info("导出收藏数据到: \(exportURL.path)")
            return exportURL
        } catch {
            Logger.shared.error("导出收藏数据失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // 导入收藏数据
    func importFavorites(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let importedItems = try decoder.decode([ClipboardItem].self, from: data)
            
            // 合并导入的数据，避免重复
            var itemsToAdd: [ClipboardItem] = []
            for item in importedItems {
                if !favoriteItems.contains(where: { $0.id == item.id }) {
                    itemsToAdd.append(item)
                }
            }
            
            // 确保在主线程上更新@Published属性
            DispatchQueue.main.async {
                self.favoriteItems.append(contentsOf: itemsToAdd)
            }
            
            saveFavorites()
            Logger.shared.info("成功导入 \(importedItems.count) 个收藏项目")
            return true
        } catch {
            Logger.shared.error("导入收藏数据失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // 同步收藏状态与ClipboardManager
    private func syncFavoriteStatusWithClipboardManager() {
        let clipboardManager = ClipboardManager.shared
        
        // 更新ClipboardManager中项目的收藏状态
        for i in 0..<clipboardManager.clipboardItems.count {
            let item = clipboardManager.clipboardItems[i]
            let shouldBeFavorite = favoriteItems.contains(where: { $0.id == item.id })
            
            if item.isFavorite != shouldBeFavorite {
                var updatedItem = item
                updatedItem.isFavorite = shouldBeFavorite
                clipboardManager.clipboardItems[i] = updatedItem
                
                // 保存更新后的项目到存储
                clipboardManager.store.saveItem(updatedItem)
                
                Logger.shared.info("同步收藏状态: \(item.content.prefix(30)) -> \(shouldBeFavorite)")
            }
        }
        
        // 注意：不再清理FavoriteManager中的收藏项目
        // 收藏项目应该独立于ClipboardManager存在，即使在清空历史记录后也要保留
        // 这样可以确保收藏的内容在清空历史记录和重启应用后仍然可用
        
        Logger.shared.info("收藏状态同步完成，保留了所有收藏项目")
    }
    
    // 与ClipboardStore同步收藏数据
    func syncWithClipboardStore() {
        let clipboardManager = ClipboardManager.shared
        let storeItems = clipboardManager.store.loadItems()
        
        // 1. 从ClipboardStore中获取所有标记为收藏的项目
        let storeFavoriteItems = storeItems.filter { $0.isFavorite }
        
        // 2. 更新FavoriteManager中的收藏列表
        var updatedFavorites: [ClipboardItem] = []
        
        // 保留现有的收藏项目，无论是否在store中存在
        // 这确保了收藏项目的独立性和持久性
        for favoriteItem in favoriteItems {
            if let storeItem = storeItems.first(where: { $0.id == favoriteItem.id }) {
                // 使用store中的最新数据更新收藏项目
                var updatedItem = storeItem
                updatedItem.isFavorite = true
                updatedFavorites.append(updatedItem)
            } else {
                // 即使store中不存在，也保留收藏项目
                // 这对于清空历史记录后的收藏项目恢复很重要
                updatedFavorites.append(favoriteItem)
            }
        }
        
        // 添加store中新的收藏项目（不在当前收藏列表中的）
        for storeItem in storeFavoriteItems {
            if !updatedFavorites.contains(where: { $0.id == storeItem.id }) {
                updatedFavorites.append(storeItem)
            }
        }
        
        // 3. 更新收藏列表并保存
        let originalCount = favoriteItems.count
        
        // 确保在主线程上更新@Published属性
        DispatchQueue.main.async {
            self.favoriteItems = updatedFavorites
        }
        saveFavorites()
        
        // 4. 确保ClipboardManager中的项目收藏状态正确
        for i in 0..<clipboardManager.clipboardItems.count {
            let item = clipboardManager.clipboardItems[i]
            let shouldBeFavorite = favoriteItems.contains(where: { $0.id == item.id })
            
            if item.isFavorite != shouldBeFavorite {
                var updatedItem = item
                updatedItem.isFavorite = shouldBeFavorite
                clipboardManager.clipboardItems[i] = updatedItem
            }
        }
        
        Logger.shared.info("与ClipboardStore同步完成: 原有\(originalCount)个收藏，现有\(favoriteItems.count)个收藏")
    }
    
    // 数据验证机制
    func validateDataConsistency() -> Bool {
        var isConsistent = true
        var issues: [String] = []
        
        let clipboardManager = ClipboardManager.shared
        let storeItems = clipboardManager.store.loadItems()
        
        // 1. 验证FavoriteManager中的收藏项目是否在ClipboardStore中存在
        for favoriteItem in favoriteItems {
            if !storeItems.contains(where: { $0.id == favoriteItem.id }) {
                issues.append("收藏项目\(favoriteItem.id)在ClipboardStore中不存在")
                isConsistent = false
            }
        }
        
        // 2. 验证ClipboardStore中标记为收藏的项目是否在FavoriteManager中存在
        let storeFavoriteItems = storeItems.filter { $0.isFavorite }
        for storeItem in storeFavoriteItems {
            if !favoriteItems.contains(where: { $0.id == storeItem.id }) {
                issues.append("ClipboardStore中的收藏项目\(storeItem.id)在FavoriteManager中不存在")
                isConsistent = false
            }
        }
        
        // 3. 验证ClipboardManager中的收藏状态是否与FavoriteManager一致
        for clipboardItem in clipboardManager.clipboardItems {
            let shouldBeFavorite = favoriteItems.contains(where: { $0.id == clipboardItem.id })
            if clipboardItem.isFavorite != shouldBeFavorite {
                issues.append("ClipboardManager中项目\(clipboardItem.id)的收藏状态不一致")
                isConsistent = false
            }
        }
        
        // 4. 验证收藏文件的完整性
        if !FileManager.default.fileExists(atPath: favoritesFile.path) {
            if !favoriteItems.isEmpty {
                issues.append("收藏文件不存在但内存中有收藏项目")
                isConsistent = false
            }
        } else {
            // 验证文件内容与内存数据是否一致
            do {
                let data = try Data(contentsOf: favoritesFile)
                let fileItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
                if fileItems.count != favoriteItems.count {
                    issues.append("收藏文件中的项目数量与内存不一致")
                    isConsistent = false
                }
            } catch {
                issues.append("收藏文件读取失败: \(error.localizedDescription)")
                isConsistent = false
            }
        }
        
        // 记录验证结果
        if isConsistent {
            Logger.shared.info("数据一致性验证通过")
        } else {
            Logger.shared.warning("数据一致性验证失败，发现\(issues.count)个问题:")
            for issue in issues {
                Logger.shared.warning("- \(issue)")
            }
        }
        
        return isConsistent
    }
    
    // 自动修复数据不一致问题
    func autoFixDataInconsistency() {
        Logger.shared.info("开始自动修复数据不一致问题")
        
        // 执行同步操作来修复大部分问题
        syncWithClipboardStore()
        
        // 重新验证
        let isFixed = validateDataConsistency()
        
        if isFixed {
            Logger.shared.info("数据不一致问题已自动修复")
        } else {
            Logger.shared.error("自动修复失败，需要手动处理")
        }
    }
}