# OneClip 图片清理策略优化建议

## 当前图片清理机制问题

1. **过于激进的清理策略**：
   - 自动清理按天数清理整个日期文件夹
   - 存储大小限制会删除最旧的文件夹
   - 没有对图片类型的特殊保护

2. **缺少用户控制选项**：
   - 无法设置图片专门的保留期
   - 无法禁用图片的自动清理
   - 没有图片优先级保护

## 优化方案

### 方案1：图片专门保护设置

在设置中添加图片专门的清理选项：

```swift
struct AppSettings: Codable {
    // 现有设置...
    var autoCleanupDays: Int
    
    // 新增图片保护设置
    var imageCleanupDays: Int // 图片专门的清理天数
    var protectImages: Bool   // 是否保护图片不被自动清理
    var maxImageStorage: Int  // 图片最大存储MB
}
```

### 方案2：改进ClipboardStore的清理逻辑

```swift
private func cleanupOldFiles() {
    let cutoffDate = Date().addingTimeInterval(-maxFileAge)
    let imageProtectionDate = Date().addingTimeInterval(-TimeInterval(getImageCleanupDays() * 24 * 60 * 60))
    
    do {
        let dateDirectories = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
        
        for dateDirectory in dateDirectories {
            if let creationDate = try? dateDirectory.resourceValues(forKeys: [.creationDateKey]).creationDate {
                
                // 检查是否需要部分清理（保护图片）
                if shouldProtectImages() && creationDate > imageProtectionDate && creationDate < cutoffDate {
                    cleanupFolderExceptImages(dateDirectory)
                } else if creationDate < cutoffDate {
                    try fileManager.removeItem(at: dateDirectory)
                    print("已清理过期文件夹: \\(dateDirectory.lastPathComponent)")
                }
            }
        }
    } catch {
        print("清理过期文件失败: \\(error)")
    }
}

private func cleanupFolderExceptImages(_ directory: URL) {
    // 只清理非图片文件，保留图片
    do {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        for file in files {
            let isImageFile = ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp"].contains(file.pathExtension.lowercased())
            
            if !isImageFile && file.lastPathComponent != "items.json" {
                try fileManager.removeItem(at: file)
            }
        }
        
        // 更新items.json，只保留图片项目
        updateItemsFileKeepingImages(directory)
    } catch {
        print("部分清理失败: \\(error)")
    }
}
```

### 方案3：用户界面改进

在设置界面添加图片保护选项：

```swift
// 在存储设置中添加
VStack(alignment: .leading, spacing: 12) {
    Text("图片保护设置")
        .font(.headline)
    
    Toggle("保护图片不被自动清理", isOn: $settingsManager.protectImages)
        .help("启用后，图片将不会被自动清理删除")
    
    if !settingsManager.protectImages {
        HStack {
            Text("图片保留天数")
            Spacer()
            Picker("", selection: $settingsManager.imageCleanupDays) {
                Text("7天").tag(7)
                Text("30天").tag(30)
                Text("60天").tag(60)
                Text("90天").tag(90)
                Text("永不清理").tag(0)
            }
            .pickerStyle(MenuPickerStyle())
        }
    }
    
    HStack {
        Text("图片最大存储空间")
        Spacer()
        Picker("", selection: $settingsManager.maxImageStorage) {
            Text("100MB").tag(100)
            Text("500MB").tag(500)
            Text("1GB").tag(1000)
            Text("2GB").tag(2000)
            Text("无限制").tag(0)
        }
        .pickerStyle(MenuPickerStyle())
    }
}
```

### 方案4：智能图片清理

实现基于使用频率的智能清理：

```swift
private func intelligentImageCleanup() {
    // 根据图片访问频率、大小、类型等因素决定清理优先级
    let allItems = loadItems()
    let imageItems = allItems.filter { $0.type == .image }
    
    // 按访问时间和重要性排序
    let sortedImages = imageItems.sorted { item1, item2 in
        // 收藏的图片优先级最高
        if item1.isFavorite != item2.isFavorite {
            return item1.isFavorite
        }
        
        // 最近访问的优先级高
        return item1.timestamp > item2.timestamp
    }
    
    // 只清理最不重要的图片
    let imagesToKeep = Array(sortedImages.prefix(getMaxImageCount()))
    // 删除其余图片...
}
```

## 立即可用的解决方案

如果你不想图片被清理，可以：

1. **将重要图片加入收藏**：收藏的项目不会被清理
2. **增加自动清理天数**：在设置中将3天改为更长时间（如30天、60天）
3. **禁用自动清理**：将清理天数设为"永不清理"

## 推荐实施步骤

1. **短期**：增加清理天数设置，将3天改为至少30天
2. **中期**：实施图片专门保护设置
3. **长期**：开发智能清理算法，基于使用频率而非单纯时间清理

这样可以更好地保护用户的图片数据，避免重要内容被意外清理。
