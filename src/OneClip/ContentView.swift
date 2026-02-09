import SwiftUI
import CoreGraphics
import AppKit
import ApplicationServices

// 确保ClipboardItemRowView可以被找到
// ClipboardItemRowView在同一个模块中定义

struct ContentView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @EnvironmentObject private var windowManager: WindowManager
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var favoriteManager = FavoriteManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showFeedback = false
    @State private var feedbackMessage = ""
    @State private var showSettings = false
    @State private var showShortcutsHelp = false
    @State private var selectedCategory: ContentCategory = .all
    @State private var showWelcomeMessage = false
    @State private var showClearAllConfirmation = false
    @State private var isFirstLaunch = true // 首次启动标志位，避免每次窗口显示都清理图片缓存
    @State private var selectedIndex: Int? = nil // 当前选中的项目索引
    @State private var showDeleteConfirmation = false // 删除确认对话框
    @State private var selectedItemToDelete: ClipboardItem? = nil // 待删除的项目
    
    // 动画辅助方法
    private func performAnimation(_ animation: Animation, action: @escaping () -> Void) {
        if settingsManager.enableAnimations {
            withAnimation(animation) {
                action()
            }
        } else {
            action()
        }
    }
    
    // 自适应样式，优化深色模式
    private static func feedbackGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ? 
                [Color.white.opacity(0.2), Color.clear] : 
                [Color.white.opacity(0.4), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ? [
                Color.white.opacity(0.02),
                Color.clear,
                Color.black.opacity(0.05)
            ] : [
                Color.white.opacity(0.03),
                Color.clear,
                Color.black.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private static func searchBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ? 
                [Color.white.opacity(0.15), Color.clear] : 
                [Color.white.opacity(0.3), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // 简洁的纯色按钮样式
    private static let buttonColor = Color.blue
    private static let clearButtonColor = Color.red
    
    enum ContentCategory: String, CaseIterable {
        case all = "全部"
        case favorites = "收藏"
        case text = "文本"
        case image = "图片"
        case file = "文件"
        case video = "视频"
        case audio = "音频"
        case document = "文档"
        case code = "代码"
        case archive = "压缩包"
        case executable = "应用程序"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .favorites: return "star.fill"
            case .text: return "doc.text"
            case .image: return "photo"
            case .file: return "doc"
            case .video: return "video"
            case .audio: return "music.note"
            case .document: return "doc.text"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .archive: return "archivebox"
            case .executable: return "app"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .primary
            case .favorites: return .yellow
            case .text: return .blue
            case .image: return .green
            case .file: return .orange
            case .video: return .purple
            case .audio: return .red
            case .document: return .cyan
            case .code: return .mint
            case .archive: return .pink
            case .executable: return .indigo
            }
        }
    }
    
    // 简化的过滤逻辑 - 直接计算避免缓存问题
    var filteredItems: [ClipboardItem] {
        var items: [ClipboardItem]
        
        // 按分类过滤
        if selectedCategory == .favorites {
            // 优先从FavoriteManager获取收藏项目，确保数据一致性
            let favoriteItems = FavoriteManager.shared.getAllFavorites()
            if !favoriteItems.isEmpty {
                items = favoriteItems
            } else {
                // 如果FavoriteManager为空，从主列表中过滤收藏项目作为备选
                items = clipboardManager.clipboardItems.filter { $0.isFavorite }
            }
        } else if selectedCategory != .all {
            let targetType: ClipboardItemType = {
                switch selectedCategory {
                case .all, .favorites: return .text // 不会用到
                case .text: return .text
                case .image: return .image
                case .file: return .file
                case .video: return .video
                case .audio: return .audio
                case .document: return .document
                case .code: return .code
                case .archive: return .archive
                case .executable: return .executable
                }
            }()
            
            items = clipboardManager.clipboardItems.filter { $0.type == targetType }
        } else {
            items = clipboardManager.clipboardItems
        }
        
        // 按搜索文本过滤
        if !searchText.isEmpty {
            items = items.filter { item in
                item.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items
    }
    
    // 分解复杂的body为更小的计算属性
    private var topToolbar: some View {
        HStack(spacing: 14) {
            // 为左上角窗口操作按钮留出空间
            Spacer()
                .frame(width: 80)
            
            searchBar
            
            Spacer()
            
            controlButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color.clear)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .medium))
                .opacity(0.7)
            
            TextField("搜索剪贴板内容...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body, design: .default))
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.searchBorderGradient(for: colorScheme), lineWidth: 1)
        )
    }
    
    private var controlButtons: some View {
        HStack(spacing: 8) {
            // 快捷键帮助按钮
            Button(action: {
                windowManager.temporarilyPreventAutoHide(duration: 1.0)
                showShortcutsHelp = true
            }) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Self.buttonColor)
            }
            .buttonStyle(ModernCircleButtonStyle())
            .help("快捷键帮助")
            
            // 设置按钮
            Button(action: {
                windowManager.temporarilyPreventAutoHide(duration: 1.0)
                showSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Self.buttonColor)
            }
            .buttonStyle(ModernCircleButtonStyle())
            .help("设置")
            
            // 窗口置顶按钮
            Button(action: {
                windowManager.toggleWindowOnTop()
            }) {
                Image(systemName: settingsManager.keepWindowOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(settingsManager.keepWindowOnTop ? 
                        Color.orange : 
                        Self.buttonColor)
            }
            .buttonStyle(ModernCircleButtonStyle())
            .help(settingsManager.keepWindowOnTop ? "取消置顶" : "窗口置顶")
            
            // 清空历史按钮
            Button(action: {
                windowManager.temporarilyPreventAutoHide(duration: 2.0)
                showClearAllConfirmation = true
            }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Self.clearButtonColor)
            }
            .buttonStyle(ModernCircleButtonStyle())
            .help("清空历史")
        }
    }
    
    private var dividerLine: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, Color.primary.opacity(0.1), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
    
    private var categoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContentCategory.allCases, id: \.self) { category in
                    CategoryTabView(
                        category: category,
                        isSelected: selectedCategory == category,
                        count: getCategoryCount(category)
                    ) {
                        selectedCategory = category
                    }
                }
                
                // 统计信息
                Spacer(minLength: 16)
                
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("共 \(clipboardManager.clipboardItems.count) 项")
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.5))
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.clear)
    }
    
    private var clipboardItemsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if filteredItems.isEmpty {
                    if settingsManager.isFirstLaunch && !settingsManager.hasShownWelcome {
                        WelcomeStateView()
                            .onAppear {
                                settingsManager.markWelcomeShown()
                            }
                    } else {
                        EmptyStateView()
                    }
                } else {
                    ForEach(filteredItems.indices, id: \.self) { index in
                        let item = filteredItems[index]
                        ClipboardItemRowView(
                             item: item,
                             onSingleTap: {
                                 clipboardManager.copyToClipboard(item: item)
                                 showCopyFeedback()
                 // 单击复制后隐藏窗口
                                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                     self.hideWindow()
                                 }
                             },
                             onDoubleTap: {
                                 clipboardManager.copyToClipboard(item: item)
                                 hideWindowAndPaste()
                             },
                             onDelete: {
                                 clipboardManager.deleteItem(item)
                                 showDeleteFeedback()
                             },
                             onSmartPaste: {
                                 performSmartPaste(item: item)
                             },
                             index: index,
                             isSelected: selectedIndex == index,
                             onHover: { isHovering in
                                 if isHovering {
                                     print("鼠标悬浮在索引 \(index) 的项目上，设置selectedIndex = \(index)")
                                     selectedIndex = index
                                 } else {
                                     // 鼠标离开时，只有当前选中的是这个项目时才重置
                                     if selectedIndex == index {
                                         print("鼠标离开索引 \(index) 的项目，重置selectedIndex = nil")
                                         selectedIndex = nil
                                     }
                                 }
                             }
                         )
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            dividerLine
            categoryTabBar
            dividerLine
            clipboardItemsList
        }
        .padding(.top, 28) // 为自定义标题栏留出空间
        .background(
            ZStack {
                // 主背景 - 使用更匹配的材质效果
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea(.all)
                
                // 渐变覆盖层增强深度
                Self.backgroundGradient(for: colorScheme)
                    .ignoresSafeArea(.all)
                    .allowsHitTesting(false)
            }
        )
        .overlay(
            // 反馈提示 - 现代化设计
            VStack {
                if showFeedback {
                    Text(feedbackMessage)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                                .overlay(
                                    Capsule()
                                        .stroke(Self.feedbackGradient(for: colorScheme), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .top)),
                            removal: .scale(scale: 1.1).combined(with: .opacity).combined(with: .move(edge: .top))
                        ))
                        .padding(.top, 12)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: showFeedback)
        )
        .onAppear {
            // 安全地初始化组件，避免ViewBridge错误
            DispatchQueue.main.async {
                self.clipboardManager.startMonitoring()
                
                // 同步收藏数据，确保收藏功能正常工作
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.favoriteManager.syncWithClipboardStore()
                }
                
                // 只在首次启动时清理图片预览缓存，避免窗口重新打开时出现空白界面
                if self.isFirstLaunch {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: NSNotification.Name("ClearImagePreviewCache"), object: nil)
                        // 首次启动已清理图片预览缓存
                    }
                    self.isFirstLaunch = false
                }
            }
        }
        .onDisappear {
            // 清理通知观察者，避免内存泄漏
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        }
        .onChange(of: windowManager.isWindowVisible) { _, newValue in
            // 根据WindowManager的状态控制窗口状态
            DispatchQueue.main.async {
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // 窗口显示时重置选中状态
                        self.selectedIndex = nil
                    }
                } else {
                    self.isSearchFocused = false
                    // 窗口隐藏时重置选中状态
                    self.selectedIndex = nil
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            // 搜索文本变化时重置选中状态
            selectedIndex = nil
        }
        .onChange(of: selectedCategory) { _, _ in
            // 分类变化时重置选中状态
            selectedIndex = nil
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showShortcutsHelp) {
            ShortcutsHelpView {
                showShortcutsHelp = false
            }
        }
        .alert("确认清空所有历史记录？", isPresented: $showClearAllConfirmation) {
            Button("取消", role: .cancel) { }
            Button("全部清空", role: .destructive) {
                clipboardManager.clearAllItems()
                showClearFeedback()
            }
        } message: {
            Text("此操作将永久删除所有剪贴板历史，且无法撤销。")
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                showDeleteConfirmation = false
                selectedItemToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let item = selectedItemToDelete {
                    clipboardManager.deleteItem(item)
                    showDeleteFeedback()
                    // 删除后重置选中状态
                    selectedIndex = nil
                }
                showDeleteConfirmation = false
                selectedItemToDelete = nil
            }
        } message: {
            Text("确定要删除这个剪贴板项目吗？此操作无法撤销。")
        }
        .onChange(of: showSettings) {
            // 当设置面板显示时防止自动隐藏
            windowManager.setPreventAutoHide(showSettings)
        }
        .onChange(of: showShortcutsHelp) {
            // 当快捷键帮助面板显示时防止自动隐藏
            windowManager.setPreventAutoHide(showShortcutsHelp)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivateSearchField"))) { _ in
            // 激活搜索框
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClipboardItemsChanged"))) { _ in
            // 当剪贴板项目发生变化时，避免过度刷新图片预览
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // 只在必要时发送图片刷新通知
                let hasImageItems = clipboardManager.clipboardItems.contains { $0.type == .image }
                if hasImageItems {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshImagePreviews"), object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("themeChanged"))) { notification in
            // 响应主题变更
            // 主题变更由 SettingsManager 处理，这里只需要记录日志
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseSettingsPanel"))) { _ in
            // 响应关闭设置面板的通知
            // 收到关闭设置面板通知
            if showSettings {
                showSettings = false
                // 设置面板已关闭
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowFavorites"))) { _ in
            // 响应显示收藏夹的通知
            DispatchQueue.main.async {
                selectedCategory = .favorites
                // 重置搜索文本和选中状态
                searchText = ""
                selectedIndex = nil
            }
        }
        .focusable(true)
        .onKeyPress(.escape) {
            // ESC 键隐藏窗口并隐藏Dock图标
            // ESC键被按下，隐藏窗口
            
            // 发送通知给AppDelegate执行窗口隐藏逻辑
            NotificationCenter.default.post(name: NSNotification.Name("HideWindowAndDock"), object: nil)
            
            return .handled
        }
        // 应用内快捷键 Cmd+1-9
        .onKeyPress("1", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(1)
            }
            return .ignored
        }
        .onKeyPress("2", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(2)
            }
            return .ignored
        }
        .onKeyPress("3", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(3)
            }
            return .ignored
        }
        .onKeyPress("4", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(4)
            }
            return .ignored
        }
        .onKeyPress("5", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(5)
            }
            return .ignored
        }
        .onKeyPress("6", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(6)
            }
            return .ignored
        }
        .onKeyPress("7", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(7)
            }
            return .ignored
        }
        .onKeyPress("8", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(8)
            }
            return .ignored
        }
        .onKeyPress("9", phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleNumberKey(9)
            }
            return .ignored
        }
        // 应用内其他快捷键
        .onKeyPress(.return) {
            // 立即激活用户活动状态，确保快捷键响应及时
            clipboardManager.updateUserActivity()
            
            // Enter 键复制选中项目
            let targetItem: ClipboardItem?
            if let index = selectedIndex, index < filteredItems.count {
                targetItem = filteredItems[index]
            } else if let firstItem = filteredItems.first {
                targetItem = firstItem
            } else {
                targetItem = nil
            }
            
            if let item = targetItem {
                clipboardManager.copyToClipboard(item: item)
                showCopyFeedback()
                // 复制后隐藏窗口
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.hideWindow()
                }
            }
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { keyPress in
            // 检查是否按下了 Cmd+Delete 组合键
            guard keyPress.modifiers.contains(.command) else {
                return .ignored
            }
            
            // 立即激活用户活动状态，确保快捷键响应及时
            clipboardManager.updateUserActivity()
            
            // 调试信息：记录Cmd+Delete键被按下
            print("Cmd+Delete键被按下，当前selectedIndex: \(selectedIndex?.description ?? "nil")，filteredItems数量: \(filteredItems.count)")
            
            // Cmd+Delete 键删除选中项目 - 需要二次确认
            if let index = selectedIndex, index < filteredItems.count {
                print("准备删除索引 \(index) 的项目")
                showDeleteConfirmation = true
            } else if !filteredItems.isEmpty {
                print("没有选中项目，选中第一个项目并准备删除")
                selectedIndex = 0
                showDeleteConfirmation = true
            } else {
                print("没有可删除的项目")
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            // 上键导航：支持循环导航
            if filteredItems.isEmpty { return .handled }
            
            if let currentIndex = selectedIndex {
                // 如果当前有选中项，向上移动（支持循环）
                selectedIndex = currentIndex > 0 ? currentIndex - 1 : filteredItems.count - 1
            } else {
                // 如果没有选中项，选中最后一个
                selectedIndex = filteredItems.count - 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            // 下键导航：支持循环导航
            if filteredItems.isEmpty { return .handled }
            
            if let currentIndex = selectedIndex {
                // 如果当前有选中项，向下移动（支持循环）
                selectedIndex = currentIndex < filteredItems.count - 1 ? currentIndex + 1 : 0
            } else {
                // 如果没有选中项，选中第一个
                selectedIndex = 0
            }
            return .handled
        }
    }
    
    // MARK: - 应用内快捷键处理
    
    private func handleNumberKey(_ number: Int) -> KeyPress.Result {
        // 立即激活用户活动状态，确保快捷键响应及时
        clipboardManager.updateUserActivity()
        
        // 只有在窗口可见时处理 Cmd+数字键组合
        guard windowManager.isWindowVisible else {
            return .ignored
        }
        
        let index = number - 1
        
        // 检查索引是否有效
        guard index >= 0 && index < filteredItems.count else {
            return .ignored
        }
        
        let item = filteredItems[index]
        
        // 只复制到剪贴板，不执行粘贴
        clipboardManager.copyToClipboard(item: item)
        showCopyFeedback()
        
        // 复制完成后自动隐藏窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hideWindow()
        }
        
        return .handled
    }
    
    // MARK: - 窗口管理（委托给WindowManager）
    
    private func showWindow() {
        // 委托给WindowManager处理窗口显示
    }
    
    private func hideWindow() {
        // 委托给WindowManager处理窗口隐藏
        windowManager.hideWindow()
    }
    
    private func hideWindowAndPaste() {
        // 隐藏窗口
        windowManager.hideWindow()
        
        // 延迟执行粘贴操作，避免与窗口隐藏冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
    }
    
    // 智能粘贴功能 - 直接粘贴到光标位置
    private func performSmartPaste(item: ClipboardItem) {
        // 先将内容复制到系统剪贴板
        clipboardManager.copyToClipboard(item: item)
        
        // 隐藏窗口
        windowManager.hideWindow()
        
        // 延迟执行粘贴操作，确保窗口隐藏完成且前台应用获得焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.sendCmdVKeyEvent()
        }
        
        // 显示反馈
        showFeedback(message: "已粘贴到光标位置")
    }
    
    // 使用CGEvent发送Cmd+V键盘事件
    private func sendCmdVKeyEvent() {
        // 创建Cmd键按下事件
        let cmdKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true)
        cmdKeyDown?.flags = .maskCommand
        
        // 创建V键按下事件（带Cmd修饰符）
        let vKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        vKeyDown?.flags = .maskCommand
        
        // 创建V键释放事件（带Cmd修饰符）
        let vKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        vKeyUp?.flags = .maskCommand
        
        // 创建Cmd键释放事件
        let cmdKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false)
        
        // 发送事件序列
        cmdKeyDown?.post(tap: .cghidEventTap)
        usleep(10000) // 10ms延迟
        vKeyDown?.post(tap: .cghidEventTap)
        usleep(10000) // 10ms延迟
        vKeyUp?.post(tap: .cghidEventTap)
        usleep(10000) // 10ms延迟
        cmdKeyUp?.post(tap: .cghidEventTap)
    }
    
    private func showFeedback(message: String, duration: TimeInterval = 2.0) {
        feedbackMessage = message
        showFeedback = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            showFeedback = false
        }
    }
    
    private func showCopyFeedback() {
        showFeedback(message: "已复制到剪贴板")
    }
    
    private func showDeleteFeedback() {
        showFeedback(message: "已删除项目")
    }
    
    private func showClearFeedback() {
        showFeedback(message: "已清空历史记录")
    }
    
    // MARK: - 分类相关方法
    private func getCategoryCount(_ category: ContentCategory) -> Int {
        switch category {
        case .all:
            return clipboardManager.clipboardItems.count
        case .favorites:
            // 优先使用FavoriteManager的计数
            let favoriteManagerCount = FavoriteManager.shared.favoriteCount
            if favoriteManagerCount > 0 {
                return favoriteManagerCount
            } else {
                // 如果FavoriteManager计数为0，使用主列表计数作为备选
                return clipboardManager.clipboardItems.filter { $0.isFavorite }.count
            }
        case .text:
            return clipboardManager.clipboardItems.filter { $0.type == .text }.count
        case .image:
            return clipboardManager.clipboardItems.filter { $0.type == .image }.count
        case .file:
            return clipboardManager.clipboardItems.filter { $0.type == .file }.count
        case .video:
            return clipboardManager.clipboardItems.filter { $0.type == .video }.count
        case .audio:
            return clipboardManager.clipboardItems.filter { $0.type == .audio }.count
        case .document:
            return clipboardManager.clipboardItems.filter { $0.type == .document }.count
        case .code:
            return clipboardManager.clipboardItems.filter { $0.type == .code }.count
        case .archive:
            return clipboardManager.clipboardItems.filter { $0.type == .archive }.count
        case .executable:
            return clipboardManager.clipboardItems.filter { $0.type == .executable }.count
        }
    }
}

// MARK: - 分类标签视图
struct CategoryTabView: View {
    let category: ContentView.ContentCategory
    let isSelected: Bool
    let count: Int
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    // 自适应颜色计算 - 优化可读性
    private var adaptiveBackgroundColor: Color {
        if isSelected {
            // 选中状态：使用更饱和的颜色确保对比度
            switch category {
            case .all:
                return colorScheme == .dark ? Color.gray.opacity(0.8) : Color.black.opacity(0.85)
            case .favorites:
                return colorScheme == .dark ? Color.yellow.opacity(0.8) : Color.orange.opacity(0.85)
            case .text:
                return colorScheme == .dark ? Color.blue.opacity(0.8) : Color.blue.opacity(0.85)
            case .image:
                return colorScheme == .dark ? Color.green.opacity(0.8) : Color.green.opacity(0.85)
            case .file:
                return colorScheme == .dark ? Color.orange.opacity(0.8) : Color.brown.opacity(0.85)
            default:
                return category.color.opacity(0.85)
            }
        } else {
            // 未选中状态：提升背景对比度
            return colorScheme == .dark ? Color.gray.opacity(0.25) : Color.gray.opacity(0.08)
        }
    }
    
    private var adaptiveForegroundColor: Color {
        if isSelected {
            return .white
        } else {
            // 未选中状态：大幅提升文字对比度
            switch category {
            case .all:
                return colorScheme == .dark ? .white.opacity(0.95) : Color.black.opacity(0.85)
            case .favorites:
                return colorScheme == .dark ? Color.yellow.opacity(0.95) : Color.orange.opacity(0.9)
            case .text:
                return colorScheme == .dark ? Color.blue.opacity(0.95) : Color.blue.opacity(0.9)
            case .image:
                return colorScheme == .dark ? Color.green.opacity(0.95) : Color.green.opacity(0.9)
            case .file:
                return colorScheme == .dark ? Color.orange.opacity(0.95) : Color.brown.opacity(0.9)
            default:
                return colorScheme == .dark ? category.color.opacity(0.95) : category.color.opacity(0.9)
            }
        }
    }
    
    private var adaptiveBadgeBackgroundColor: Color {
        if isSelected {
            return .white.opacity(0.25)
        } else {
            // 提升徽章背景对比度
            switch category {
            case .all:
                return colorScheme == .dark ? Color.gray.opacity(0.4) : Color.black.opacity(0.15)
            case .favorites:
                return colorScheme == .dark ? Color.yellow.opacity(0.4) : Color.orange.opacity(0.2)
            case .text:
                return colorScheme == .dark ? Color.blue.opacity(0.4) : Color.blue.opacity(0.2)
            case .image:
                return colorScheme == .dark ? Color.green.opacity(0.4) : Color.green.opacity(0.2)
            case .file:
                return colorScheme == .dark ? Color.orange.opacity(0.4) : Color.brown.opacity(0.2)
            default:
                return colorScheme == .dark ? category.color.opacity(0.4) : category.color.opacity(0.2)
            }
        }
    }
    
    private var adaptiveBadgeForegroundColor: Color {
        if isSelected {
            return .white
        } else {
            // 提升徽章文字对比度
            switch category {
            case .all:
                return colorScheme == .dark ? .white.opacity(0.95) : Color.black.opacity(0.85)
            case .favorites:
                return colorScheme == .dark ? Color.yellow : Color.orange.opacity(0.9)
            case .text:
                return colorScheme == .dark ? Color.blue : Color.blue.opacity(0.9)
            case .image:
                return colorScheme == .dark ? Color.green : Color.green.opacity(0.9)
            case .file:
                return colorScheme == .dark ? Color.orange : Color.brown.opacity(0.9)
            default:
                return colorScheme == .dark ? category.color : category.color.opacity(0.9)
            }
        }
    }
    
    private var adaptiveStrokeColor: Color {
        if isSelected {
            return Color.white.opacity(0.2)
        } else {
            // 增强边框可见性
            switch category {
            case .all:
                return colorScheme == .dark ? Color.gray.opacity(0.6) : Color.black.opacity(0.3)
            case .favorites:
                return colorScheme == .dark ? Color.yellow.opacity(0.6) : Color.orange.opacity(0.4)
            case .text:
                return colorScheme == .dark ? Color.blue.opacity(0.6) : Color.blue.opacity(0.4)
            case .image:
                return colorScheme == .dark ? Color.green.opacity(0.6) : Color.green.opacity(0.4)
            case .file:
                return colorScheme == .dark ? Color.orange.opacity(0.6) : Color.brown.opacity(0.4)
            default:
                return colorScheme == .dark ? category.color.opacity(0.6) : category.color.opacity(0.4)
            }
        }
    }
    
    private var adaptiveShadowColor: Color {
        if isSelected {
            return category.color.opacity(0.4)
        } else {
            // 增强阴影效果提升层次感
            return colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.08)
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(category.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(adaptiveBadgeBackgroundColor)
                        )
                        .foregroundStyle(adaptiveBadgeForegroundColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(adaptiveBackgroundColor)
                    .overlay(
                        Capsule()
                            .stroke(adaptiveStrokeColor, lineWidth: 1)
                    )
                    .shadow(
                        color: adaptiveShadowColor,
                        radius: isSelected ? 6 : 2,
                        x: 0,
                        y: isSelected ? 3 : 1
                    )
            )
            .foregroundStyle(adaptiveForegroundColor)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1.0)
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 根据文件类型显示不同的预览
            switch item.type {
            case .image:
                ImagePreviewView(item: item)
                    .id("\(item.id)-\(item.timestamp.timeIntervalSince1970)") // 确保每个视图唯一
            case .video:
                VideoPreviewView(item: item)
                    .id("\(item.id)-video-\(item.timestamp.timeIntervalSince1970)")
            case .audio:
                AudioPreviewView(item: item)
                    .id("\(item.id)-audio-\(item.timestamp.timeIntervalSince1970)")
            case .document, .code, .archive, .executable:
                FilePreviewView(item: item)
                    .id("\(item.id)-file-\(item.timestamp.timeIntervalSince1970)")
            default:
                Text(item.content)
                    .lineLimit(2)
                    .font(.body)
                    .id("\(item.id)-text-\(item.timestamp.timeIntervalSince1970)") // 文本内容也需要唯一ID
            }
            
            HStack {
                Text(item.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                ModernItemTypeBadge(type: item.type)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 条件光辉效果修饰器
struct ConditionalGlowModifier: ViewModifier {
    let glowColor: Color?
    let isHovered: Bool
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        if let color = glowColor {
            content
                .shadow(
                    color: color.opacity((isHovered || isSelected) ? 0.15 : 0.08),
                    radius: (isHovered || isSelected) ? 12 : 6,
                    x: 0,
                    y: (isHovered || isSelected) ? 2 : 1
                )
                .shadow(
                    color: color.opacity((isHovered || isSelected) ? 0.1 : 0.05),
                    radius: (isHovered || isSelected) ? 8 : 4,
                    x: 0,
                    y: 0
                )
        } else {
            content  // 文字类型不显示光辉效果
        }
    }
}

// MARK: - 现代化自动清理天数设置组件
struct ModernCleanupDaysStepper: View {
    @Binding var value: Int
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    // 预设选项
    private let presetOptions = [0, 7, 15, 30, 60, 90]
    
    private var previewText: String {
        switch value {
        case 0:
            return "永不清理"
        case 1...7:
            return "频繁清理"
        case 8...30:
            return "定期清理"
        case 31...90:
            return "长期保存"
        default:
            return "自定义设置"
        }
    }
    
    private var stepperBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ? [
                Color.white.opacity(0.08),
                Color.white.opacity(0.04)
            ] : [
                Color.white.opacity(0.9),
                Color.gray.opacity(0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var stepperBorderGradient: LinearGradient {
        LinearGradient(
            colors: isHovered ? [
                Color.blue.opacity(0.6),
                Color.purple.opacity(0.4)
            ] : [
                Color.primary.opacity(0.15),
                Color.primary.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题和描述
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.body, design: .default, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // 预览文本
                    HStack(spacing: 4) {
                        Image(systemName: value == 0 ? "infinity.circle.fill" : "clock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(value == 0 ? .orange : .blue)
                        
                        Text(previewText)
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(value == 0 ? .orange : .blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((value == 0 ? Color.orange : Color.blue).opacity(0.1))
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 现代化步进器控件
                HStack(spacing: 2) {
                    // 减少按钮
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            let newValue = max(0, value - 1)
                            if newValue != value {
                                value = newValue
                            }
                        }
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(value > 0 ? .white : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        value > 0 ?
                                        LinearGradient(
                                            colors: [Color.red.opacity(0.8), Color.red.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) :
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(value <= 0)
                    .help("减少 1 天")
                    .scaleEffect(value > 0 ? 1.0 : 0.95)
                    
                    // 数值显示区域
                    VStack(spacing: 2) {
                        Text(value == 0 ? "∞" : "\(value)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                        
                        Text(value == 0 ? "永不" : "天")
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                            .opacity(0.8)
                    }
                    .frame(width: 70, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(stepperBackgroundGradient)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    )
                    
                    // 增加按钮
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            let newValue = min(365, value + 1)
                            if newValue != value {
                                value = newValue
                            }
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(value < 365 ? .white : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        value < 365 ?
                                        LinearGradient(
                                            colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) :
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(value >= 365)
                    .help("增加 1 天")
                    .scaleEffect(value < 365 ? 1.0 : 0.95)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(stepperBorderGradient, lineWidth: 1.5)
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                    }
                }
            }
            
            // 预设选项按钮
            VStack(spacing: 8) {
                HStack {
                    Text("快速选择")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(presetOptions, id: \.self) { option in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                value = option
                            }
                        }) {
                            VStack(spacing: 4) {
                                Text(option == 0 ? "永不" : "\(option)天")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundColor(value == option ? .white : .primary)
                                
                                Text(getOptionDescription(option))
                                    .font(.system(.caption2, design: .default))
                                    .foregroundColor(value == option ? .white.opacity(0.8) : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        value == option ?
                                        LinearGradient(
                                            colors: option == 0 ? 
                                                [Color.orange.opacity(0.8), Color.orange.opacity(0.6)] :
                                                [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) :
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                value == option ? Color.clear : Color.primary.opacity(0.1),
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(getOptionDescription(option))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func getOptionDescription(_ days: Int) -> String {
        switch days {
        case 0: return "不清理"
        case 7: return "一周"
        case 15: return "半月"
        case 30: return "一月"
        case 60: return "两月"
        case 90: return "三月"
        default: return "\(days)天"
        }
    }
}

struct ImagePreviewView: View {
    let item: ClipboardItem
    @State private var data: Data?
    @State private var image: NSImage?
    @State private var isLoading: Bool = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var dataHash: String = "" // 用于确保图片数据一一对应
    @State private var viewId: UUID = UUID() // 唯一视图标识符
    @State private var lastItemId: UUID? // 跟踪当前项目ID，防止视图复用错乱
    @State private var loadingStartTime: Date? // 记录加载开始时间
    @State private var showLoadingIndicator: Bool = false // 控制加载指示器显示
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var clipboardStore: ClipboardStore
    
    // 根据设置计算预览尺寸
    private var previewHeight: CGFloat {
        switch settingsManager.previewSize {
        case "small": return 60
        case "large": return 120
        default: return 80 // medium
        }
    }
    
    private var previewWidth: CGFloat {
        switch settingsManager.previewSize {
        case "small": return 90
        case "large": return 160
        default: return 120 // medium
        }
    }
    
    var body: some View {
        Group {
            if let image = image {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: min(geometry.size.width, previewWidth),
                            height: min(geometry.size.height, previewHeight)
                        )
                        .clipped()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .frame(height: previewHeight)
            } else if showLoadingIndicator {
                // 优化的加载指示器，减少闪烁
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("加载中...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(height: previewHeight)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.2), value: showLoadingIndicator)
            } else {
                // 优化的占位符，减少初始闪烁
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary.opacity(0.6))
                                .font(.system(size: 16))
                            if !isLoading {
                                Text("图片")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                    )
                    .frame(height: previewHeight)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: image != nil)
        .onAppear {
            // ImagePreviewView appeared
            
            // 1. 优先从缓存加载
            if let cachedImage = ImageCacheManager.shared.getImage(forKey: item.id.uuidString) {
                if settingsManager.enableAnimations {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.image = cachedImage
                        self.isLoading = false
                    }
                } else {
                    self.image = cachedImage
                    self.isLoading = false
                }
                self.dataHash = String(cachedImage.hash) // 更新哈希以避免重加载
                return // 命中缓存，直接返回
            }

            // 检查是否是新的项目
            if lastItemId != item.id {
                // 检测到新项目，重置状态
                // 重置所有状态
                image = nil
                data = nil
                isLoading = false
                showLoadingIndicator = false
                loadingStartTime = nil
                dataHash = ""
                loadingTask?.cancel()
                loadingTask = nil
                // 取消队列中的加载任务
                ImageLoadingQueueManager.shared.cancelImageLoad(itemId: item.id.uuidString)
                lastItemId = item.id
            }
            
            // 2. 尝试从内存数据快速加载
            if let memoryData = item.data, memoryData.count > 0 {
                // 使用内存数据快速加载
                data = memoryData
                loadImageSynchronously(from: memoryData)
            } else {
                // 3. 延迟加载机制 - 避免所有图片同时加载
                if data == nil {
                    // 从文件路径加载数据
                    if let filePath = item.filePath, !filePath.isEmpty {
                        data = try? Data(contentsOf: URL(fileURLWithPath: filePath))
                    } else {
                        data = item.data
                    }
                }
                
                // 添加随机延迟，避免同时加载大量图片
                let delay = Double.random(in: 0.05...0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // 确保视图仍然可见且项目ID未改变
                    guard lastItemId == item.id else { return }
                    loadImage()
                }
            }
        }
        .onChange(of: item.id) { _, newItemId in
            // Item ID changed
            // 当项目ID改变时，强制重置状态
            image = nil
            data = nil
            isLoading = false
            showLoadingIndicator = false
            loadingStartTime = nil
            dataHash = ""
            loadingTask?.cancel()
            loadingTask = nil
            // 取消队列中的加载任务
            ImageLoadingQueueManager.shared.cancelImageLoad(itemId: item.id.uuidString)
            lastItemId = newItemId
            
            // 重新加载数据
            if let filePath = item.filePath, !filePath.isEmpty {
                data = try? Data(contentsOf: URL(fileURLWithPath: filePath))
            } else {
                data = item.data
            }
            loadImage()
        }
        .onChange(of: data) { _, newData in
            // 只有当数据真正改变时才重新加载
            let newHash = newData?.hashValue.description ?? ""
            if newHash != dataHash {
                // 数据哈希改变
                loadImage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshImagePreviews"))) { _ in
            // 防止过度刷新导致的闪烁
            guard !isLoading else { return }
            // 收到图片预览刷新通知，重新加载图片
            loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearImagePreviewCache"))) { _ in
            // 清理图片预览缓存，防止重启后重复显示
            // 清理图片预览缓存
            if settingsManager.enableAnimations {
                withAnimation(.easeOut(duration: 0.2)) {
                    image = nil
                    data = nil
                    isLoading = false
                    dataHash = "" // 重置哈希
                }
            } else {
                image = nil
                data = nil
                isLoading = false
                dataHash = "" // 重置哈希
            }
            // 取消当前加载任务
            loadingTask?.cancel()
            loadingTask = nil
            
            // 延迟重新加载，确保去重逻辑已完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                loadImage()
            }
        }
    }
    
    private func loadImage() {
        // 强制验证当前项目ID，防止异步加载时项目已改变
        guard lastItemId == item.id else {
            // loadImage: 项目ID不匹配，停止加载
            return
        }
        
        // 首先尝试获取数据
        let imageData: Data?
        if let existingData = data {
            imageData = existingData
        } else {
            // 从文件路径或内存加载数据
            let loadedData: Data?
            if let filePath = item.filePath, !filePath.isEmpty {
                loadedData = try? Data(contentsOf: URL(fileURLWithPath: filePath))
            } else {
                loadedData = item.data
            }
            
            if let loadedData = loadedData {
                imageData = loadedData
                data = loadedData  // 缓存到状态中
            } else {
                imageData = nil
            }
        }
        
        guard let imageData = imageData, imageData.count > 0 else {
            if settingsManager.enableAnimations {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.image = nil
                    self.isLoading = false
                    self.dataHash = ""
                }
            } else {
                self.image = nil
                self.isLoading = false
                self.dataHash = ""
            }
            // ImagePreviewView: 数据为空或无效
            return
        }

        // 计算数据哈希确保一一对应
        let newDataHash = String(imageData.hashValue)
        
        // 如果哈希相同，说明是同一张图片，避免重复处理
        if !dataHash.isEmpty && dataHash == newDataHash && image != nil {
            // ImagePreviewView: 数据哈希相同，跳过重复加载
            isLoading = false  // 确保停止加载状态
            return
        }

        // ImagePreviewView: 开始加载图片

        // 更新数据哈希
        dataHash = newDataHash

        loadingTask?.cancel()
        
        // 使用队列管理器控制并发加载
        ImageLoadingQueueManager.shared.enqueueImageLoad(itemId: item.id.uuidString) {
            await self.performImageLoad(imageData: imageData, newDataHash: newDataHash)
        }
    }
    
    @MainActor
    private func performImageLoad(imageData: Data, newDataHash: String) async {
        // 再次验证项目ID，防止队列延迟导致的错误
        guard lastItemId == item.id else {
            // 队列加载时项目ID已改变，取消加载
            return
        }
        
        loadingTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            // 优化的加载状态管理，减少闪烁
            if image == nil {
                loadingStartTime = Date()
                
                // 延迟显示加载指示器，避免快速加载时的闪烁
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard !Task.isCancelled, image == nil, lastItemId == item.id else { return }
                    if settingsManager.enableAnimations {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showLoadingIndicator = true
                            isLoading = true
                        }
                    } else {
                        showLoadingIndicator = true
                        isLoading = true
                    }
                }
            }

            // 增强的异步图片解码，支持多种格式和修复机制
            let nsImage: NSImage? = await withCheckedContinuation { continuation in
                Task.detached(priority: .userInitiated) {
                    var resultImage: NSImage?
                    // 检测图片格式
                    let imageFormat = await detectImageFormat(imageData)
                    
                    // 尝试直接解码图片
                    // 方法1: 直接解码
                    resultImage = NSImage(data: imageData)
                    // 直接解码尝试完成
                    
                    if resultImage == nil {
                        // 直接解码失败，尝试 CGImageSource
                        // 方法2: 使用 CGImageSource
                        if let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) {
                            if let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                                let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                                resultImage = NSImage(cgImage: cgImage, size: size)
                            }
                        }
                    }
                    
                    if resultImage == nil {
                        // 尝试 NSBitmapImageRep 创建
                        // 方法3: 尝试 NSBitmapImageRep
                        if let bitmapRep = NSBitmapImageRep(data: imageData) {
                            resultImage = NSImage(size: NSSize(width: bitmapRep.pixelsWide, height: bitmapRep.pixelsHigh))
                            resultImage?.addRepresentation(bitmapRep)
                            // NSBitmapImageRep 创建成功
                        }
                    }
                    
                    if resultImage == nil && imageFormat == "TIFF" {
                        // 尝试 TIFF 特殊处理
                        // 方法4: TIFF 特殊处理
                        if let tiffRep = NSBitmapImageRep(data: imageData) {
                            let image = NSImage()
                            image.addRepresentation(tiffRep)
                            // 确保图片有有效的尺寸
                            if image.size.width > 0 && image.size.height > 0 {
                                resultImage = image
                                // TIFF 特殊处理成功
                            }
                        }
                    }
                    
                    if resultImage == nil {
                        // 尝试数据修复
                        // 方法5: 尝试数据修复
                        if let repairedData = await attemptImageDataRepair(imageData) {
                            resultImage = NSImage(data: repairedData)
                            if resultImage != nil {
                                // 数据修复成功
                            }
                        }
                    }
                    
                    if resultImage == nil {
                        // 尝试强制解码
                        // 方法6: 强制解码尝试
                        if let imageSource = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldAllowFloat: true] as CFDictionary),
                           CGImageSourceGetCount(imageSource) > 0 {
                            let options = [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: 512
                            ] as CFDictionary
                            
                            if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) {
                                let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                                resultImage = NSImage(cgImage: cgImage, size: size)
                                // 强制解码成功
                            }
                        }
                    }
                    
                    // 图片解码完成
                    
                    continuation.resume(returning: resultImage)
                }
            }

            guard !Task.isCancelled else { return }
            
            // 再次验证当前项目ID，防止异步完成时项目已改变
            guard lastItemId == item.id else {
                // 异步加载完成时项目ID已改变，取消设置图片
                return
            }

            // 确保加载指示器显示足够时间，避免闪烁
            let minDisplayTime: TimeInterval = 0.3
            let elapsedTime = loadingStartTime?.timeIntervalSinceNow ?? 0
            let remainingTime = max(0, minDisplayTime + elapsedTime)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) {
                guard !Task.isCancelled, lastItemId == item.id else { return }
                
                if settingsManager.enableAnimations {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.image = nsImage
                        self.isLoading = false
                        self.showLoadingIndicator = false
                        if nsImage != nil {
                            self.dataHash = newDataHash // 成功时更新哈希
                        } else {
                            self.dataHash = "" // 失败时清除哈希
                        }
                    }
                } else {
                    self.image = nsImage
                    self.isLoading = false
                    self.showLoadingIndicator = false
                    if nsImage != nil {
                        self.dataHash = newDataHash // 成功时更新哈希
                    } else {
                        self.dataHash = "" // 失败时清除哈希
                    }
                }
                
                // 重置加载时间
                self.loadingStartTime = nil
            }
            
            if let finalImage = nsImage {
                ImageCacheManager.shared.setImage(finalImage, forKey: item.id.uuidString)
                print("📷 ImagePreviewView: 图片加载成功并已缓存 (ViewID: \(viewId), ItemID: \(item.id), Hash: \(newDataHash))")
            } else {
                // ImagePreviewView: 图片加载失败
            }
        }
    }
    
    // 检测图片格式
    private func detectImageFormat(_ data: Data) -> String {
        let bytes = Array(data.prefix(16))
        
        if bytes.count >= 4 {
            // JPEG
            if bytes[0] == 0xFF && bytes[1] == 0xD8 {
                return "JPEG"
            }
            // PNG
            if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
                return "PNG"
            }
            // GIF
            if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
                return "GIF"
            }
            // TIFF (Intel)
            if bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00 {
                return "TIFF"
            }
            // TIFF (Motorola)
            if bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A {
                return "TIFF"
            }
            // BMP
            if bytes[0] == 0x42 && bytes[1] == 0x4D {
                return "BMP"
            }
            // WebP
            if bytes.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
               bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                return "WebP"
            }
        }
        
        return "Unknown"
    }
    
    // 尝试修复图片数据
    private func attemptImageDataRepair(_ data: Data) -> Data? {
        let bytes = Array(data)
        guard bytes.count > 10 else { return nil }
        
        // 对于 JPEG 格式的修复
        if !bytes.starts(with: [0xFF, 0xD8]) {
            // 寻找 JPEG 标识
            for i in 0..<min(bytes.count - 1, 100) {
                if bytes[i] == 0xFF && bytes[i + 1] == 0xD8 {
                    let repairedData = Data(bytes.dropFirst(i))
                    // 修复 JPEG 数据
                    return repairedData
                }
            }
        }
        
        // 对于 PNG 格式的修复
        if !bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            // 寻找 PNG 标识
            for i in 0..<min(bytes.count - 3, 100) {
                if bytes[i] == 0x89 && bytes[i + 1] == 0x50 && 
                   bytes[i + 2] == 0x4E && bytes[i + 3] == 0x47 {
                    let repairedData = Data(bytes.dropFirst(i))
                    // 修复 PNG 数据
                    return repairedData
                }
            }
        }
        
        return nil
    }
    
    // 同步加载方法，用于内存数据的快速显示
    private func loadImageSynchronously(from imageData: Data) {
        let currentHash = String(imageData.hashValue)
        
        // 检查是否需要重新加载
        if dataHash == currentHash, image != nil {
            // 同步加载：图片已加载且哈希匹配，跳过
            return
        }
        
        // 同步加载图片
        
        guard let loadedImage = NSImage(data: imageData) else {
            // 同步加载：无法创建图片对象
            return
        }
        
        // 直接设置图片，无需动画
        image = loadedImage
        dataHash = currentHash
        isLoading = false
        
        // 存入缓存
        ImageCacheManager.shared.setImage(loadedImage, forKey: item.id.uuidString)
        // 同步加载完成并已缓存
    }
}

// 视频预览视图
struct VideoPreviewView: View {
    let item: ClipboardItem
    @State private var viewId: UUID = UUID() // 唯一视图标识符
    @State private var lastItemId: UUID? // 跟踪当前项目ID
    @State private var contentHash: String = "" // 内容哈希验证
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(2)
                
                if let data = item.data,
                   let fileInfos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstFile = fileInfos.first,
                   let sizeFormatted = firstFile["sizeFormatted"] as? String {
                    Text(sizeFormatted)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            // VideoPreviewView appeared
            validateContent()
        }
        .onChange(of: item.id) { _, newItemId in
            // Video Item ID changed
            lastItemId = newItemId
            validateContent()
        }
    }
    
    private func validateContent() {
        let newHash = "\(item.id)-\(item.content.hashValue)-\(item.timestamp.timeIntervalSince1970)"
        if contentHash != newHash {
            // Video content validated
            contentHash = newHash
            lastItemId = item.id
        }
    }
}

// 音频预览视图
struct AudioPreviewView: View {
    let item: ClipboardItem
    @State private var viewId: UUID = UUID() // 唯一视图标识符
    @State private var lastItemId: UUID? // 跟踪当前项目ID
    @State private var contentHash: String = "" // 内容哈希验证
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(2)
                
                if let data = item.data,
                   let fileInfos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstFile = fileInfos.first,
                   let sizeFormatted = firstFile["sizeFormatted"] as? String {
                    Text(sizeFormatted)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            // AudioPreviewView appeared
            validateContent()
        }
        .onChange(of: item.id) { _, newItemId in
            // Audio Item ID changed
            lastItemId = newItemId
            validateContent()
        }
    }
    
    private func validateContent() {
        let newHash = "\(item.id)-\(item.content.hashValue)-\(item.timestamp.timeIntervalSince1970)"
        if contentHash != newHash {
            // Audio content validated
            contentHash = newHash
            lastItemId = item.id
        }
    }
}

// 文件预览视图（用于文档、代码、压缩包等）
struct FilePreviewView: View {
    let item: ClipboardItem
    @State private var viewId: UUID = UUID() // 唯一视图标识符
    @State private var lastItemId: UUID? // 跟踪当前项目ID
    @State private var contentHash: String = "" // 内容哈希验证
    
    private var iconName: String {
        switch item.type {
        case .document:
            return "doc.text.fill"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .archive:
            return "archivebox.fill"
        case .executable:
            return "app.fill"
        default:
            return "doc.fill"
        }
    }
    
    private var iconColor: [Color] {
        switch item.type {
        case .document:
            return [.blue, .cyan]
        case .code:
            return [.green, .mint]
        case .archive:
            return [.purple, .pink]
        case .executable:
            return [.red, .orange]
        default:
            return [.gray, .secondary]
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: iconColor,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(iconColor.first?.opacity(0.3) ?? .gray.opacity(0.3), lineWidth: 1)
                        )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(2)
                
                if let data = item.data,
                   let fileInfos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstFile = fileInfos.first {
                    
                    HStack(spacing: 8) {
                        if let sizeFormatted = firstFile["sizeFormatted"] as? String {
                            Text(sizeFormatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if let description = firstFile["description"] as? String {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(description)
                                .font(.system(.caption))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke((iconColor.first ?? .gray).opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            // FilePreviewView appeared
            validateContent()
        }
        .onChange(of: item.id) { _, newItemId in
            // File Item ID changed
            lastItemId = newItemId
            validateContent()
        }
    }
    
    private func validateContent() {
        let newHash = "\(item.id)-\(item.content.hashValue)-\(item.timestamp.timeIntervalSince1970)"
        if contentHash != newHash {
            // File content validated
            contentHash = newHash
            lastItemId = item.id
        }
    }
}

// 现代化类型标签 - 优化可读性
struct ModernItemTypeBadge: View {
    let type: ClipboardItemType
    @Environment(\.colorScheme) private var colorScheme
    
    // 缓存颜色和图标的计算属性
    private var typeInfo: (color: Color, iconName: String) {
        switch type {
        case .text:
            return (.blue, "text.alignleft")
        case .image:
            return (.green, "photo")
        case .file:
            return (.orange, "doc.fill")
        case .video:
            return (.purple, "video")
        case .audio:
            return (.red, "music.note")
        case .document:
            return (.cyan, "doc.text")
        case .code:
            return (.mint, "chevron.left.forwardslash.chevron.right")
        case .archive:
            return (.pink, "archivebox")
        case .executable:
            return (.indigo, "app")
        }
    }
    
    // 优化的背景材质
    private var adaptiveBackgroundMaterial: Material {
        colorScheme == .dark ? .regularMaterial : .thickMaterial
    }
    
    // 优化的前景色
    private var adaptiveForegroundColor: Color {
        let info = typeInfo
        return colorScheme == .dark ? info.color.opacity(0.95) : info.color.opacity(0.9)
    }
    
    // 优化的边框颜色
    private var adaptiveStrokeColors: [Color] {
        let info = typeInfo
        return colorScheme == .dark 
            ? [info.color.opacity(0.7), info.color.opacity(0.4)]
            : [info.color.opacity(0.6), info.color.opacity(0.3)]
    }
    
    var body: some View {
        let info = typeInfo
        
        HStack(spacing: 4) {
            Image(systemName: info.iconName)
                .font(.system(size: 10, weight: .semibold))
            
            Text(type.displayName)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(adaptiveBackgroundMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: adaptiveStrokeColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(
                    color: info.color.opacity(colorScheme == .dark ? 0.3 : 0.2), 
                    radius: 3, 
                    x: 0, 
                    y: 1
                )
        )
        .foregroundStyle(adaptiveForegroundColor)
    }
}

// 现代化圆形按钮样式
struct ModernCircleButtonStyle: ButtonStyle {
    enum Size {
        case regular, small
        
        var dimension: CGFloat {
            switch self {
            case .regular: return 32
            case .small: return 24
            }
        }
    }
    
    let size: Size
    
    init(size: Size = .regular) {
        self.size = size
    }
    
    // 静态样式缓存
    private static let borderGradient = LinearGradient(
        colors: [Color.white.opacity(0.4), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size.dimension, height: size.dimension)
            .background(
                Circle()
                    .fill(.regularMaterial.opacity(0.9))
                    .overlay(
                        Circle()
                            .stroke(Self.borderGradient, lineWidth: 1)
                    )
                    .shadow(
                        color: .black.opacity(configuration.isPressed ? 0.3 : 0.2),
                        radius: configuration.isPressed ? 2 : 6,
                        x: 0,
                        y: configuration.isPressed ? 1 : 3
                    )
            )
            // 减少按钮动画的强度以减少抖动
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}



// 设置界面
struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @EnvironmentObject private var windowManager: WindowManager
    @State private var showingExportAlert = false
    @State private var showingImportAlert = false
    @State private var showingResetAlert = false
    @State private var showingAbout = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var selectedTab = 0
    
    // 存储管理相关状态
    @State private var storageInfo = ClipboardStore.StorageInfo(
        itemCount: 0,
        totalSize: 0,
        cachePath: ""
    )
    
    @Environment(\.presentationMode) var presentationMode
    
    // 静态样式缓存
    private static let titleGradient = LinearGradient(
        colors: [.blue.opacity(0.9), .purple.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private static let separatorGradient = LinearGradient(
        colors: [
            Color.clear,
            Color.primary.opacity(0.06),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    private static let backgroundGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.04),
            Color.clear,
            Color.black.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private static let borderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.2),
            Color.clear,
            Color.black.opacity(0.1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航栏 - 简化设计
            VStack(spacing: 0) {
                // 简化的标题区域
                VStack(spacing: 8) {
                    Text("常规设置")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // 简化的导航选项卡
                VStack(spacing: 2) {
                    ModernSidebarButton(
                        title: "通用设置",
                        icon: "gear",
                        isSelected: selectedTab == 0
                    ) { selectedTab = 0 }
                    
                    ModernSidebarButton(
                        title: "界面设置",
                        icon: "paintbrush",
                        isSelected: selectedTab == 1
                    ) { selectedTab = 1 }
                    
                    ModernSidebarButton(
                        title: "监控设置",
                        icon: "chart.line.uptrend.xyaxis",
                        isSelected: selectedTab == 2
                    ) { selectedTab = 2 }
                    
                    ModernSidebarButton(
                        title: "存储",
                        icon: "externaldrive",
                        isSelected: selectedTab == 3
                    ) { selectedTab = 3 }
                    
                    ModernSidebarButton(
                        title: "快捷键",
                        icon: "command",
                        isSelected: selectedTab == 4
                    ) { selectedTab = 4 }
                    
                    ModernSidebarButton(
                        title: "高级功能",
                        icon: "slider.horizontal.2.square",
                        isSelected: selectedTab == 5
                    ) { 
                        // 高级功能暂时禁用
                        // selectedTab = 5 
                    }
                    .disabled(true)
                    .opacity(0.4)
                    
                    ModernSidebarButton(
                        title: "关于",
                        icon: "info.circle",
                        isSelected: selectedTab == 6
                    ) { selectedTab = 6 }
                }
                .padding(.horizontal, 12)
                
                Spacer()
                
                // 简化的底部区域
                VStack(spacing: 8) {
                    Button("重置所有设置") {
                        windowManager.temporarilyPreventAutoHide(duration: 1.0)
                        showingResetAlert = true
                    }
                    .font(.system(.caption, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 16)
            }
            .frame(width: 200)
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(0.6)
            )
            
            // 右侧内容区域
            VStack(spacing: 0) {
                // 简化的标题栏
                HStack {
                    Text(getTabTitle())
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 关闭按钮
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(.quaternary)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("关闭设置")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(0.3)
                )
                
                // 内容区域
                ScrollView(showsIndicators: false) {
                    getTabContent()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                }
                .background(
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(0.2)
                )
            }
        }
        .frame(width: 760, height: 600)
        .background(
            Rectangle()
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        .alert(alertTitle, isPresented: $showingExportAlert) {
            Button("确定") { }
        } message: {
            Text(alertMessage)
        }
        .alert(alertTitle, isPresented: $showingImportAlert) {
            Button("确定") { }
        } message: {
            Text(alertMessage)
        }
        .alert("重置设置", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                settingsManager.resetToDefaults()
                alertTitle = "重置完成"
                alertMessage = "所有设置已重置为默认值"
                showingExportAlert = true
            }
        } message: {
            Text("确定要重置所有设置吗？此操作无法撤销。")
        }
        .onAppear {
            // 初始化存储信息
            self.storageInfo = self.clipboardManager.getStorageInfo()
        }
        .onChange(of: selectedTab) {
            // 切换到存储标签页时刷新存储信息
            if selectedTab == 3 {
                self.storageInfo = self.clipboardManager.getStorageInfo()
            }
        }
    }
    
    // 获取标签页标题
    
    // 高级功能相关方法已暂时禁用
    /*
    private func exportData() {
        if let exportURL = settingsManager.exportData() {
            alertTitle = "导出成功"
            alertMessage = "数据已导出到: \(exportURL.lastPathComponent)"
            showingExportAlert = true
            
            // 显示文件在Finder中
            NSWorkspace.shared.activateFileViewerSelecting([exportURL])
        } else {
            alertTitle = "导出失败"
            alertMessage = "无法导出数据，请重试"
            showingExportAlert = true
        }
    }
    
    private func cleanupData() {
        // 实现清理无效数据的逻辑
        alertTitle = "清理完成"
        alertMessage = "已删除所有无效数据"
        showingExportAlert = true
    }
    
    private func openLogFolder() {
        // 打开日志文件夹
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("OneClip/Logs")
        if let url = logURL {
            NSWorkspace.shared.open(url)
        }
    }
    */
    
    private func resetSettings() {
        showingResetAlert = true
    }
    
    // 获取标签页标题
    private func getTabTitle() -> String {
        switch selectedTab {
        case 0: return "常规设置"
        case 1: return "界面设置"
        case 2: return "性能优化"
        case 3: return "存储管理"
        case 4: return "快捷键配置"
        case 5: return "高级选项"
        case 6: return "关于 OneClip"
        default: return "设置"
        }
    }
    
    // 获取标签页内容
    @ViewBuilder
    private func getTabContent() -> some View {
        switch selectedTab {
        case 0: generalSettingsView()
        case 1: interfaceSettingsView()
        case 2: performanceSettingsView()
        case 3: storageSettingsView()
        case 4: shortcutSettingsView()
        case 5: advancedSettingsView()
        case 6: aboutView()
        default: generalSettingsView()
        }
    }
    
    // 常规设置
    @ViewBuilder
    private func generalSettingsView() -> some View {
        LazyVStack(spacing: 24) {
            // 启动与行为
            ModernSettingsCard(title: "启动与行为", icon: "power.circle.fill", color: .green) {
                VStack(spacing: 16) {
                    ModernToggleRow(
                        title: "开机自动启动",
                        subtitle: "系统启动时自动运行 OneClip",
                        icon: "power",
                        binding: $settingsManager.autoStartOnLogin
                    )
                    
                    Divider().opacity(0.5)
                    
                    ModernToggleRow(
                        title: "显示在菜单栏",
                        subtitle: "在系统菜单栏显示应用图标",
                        icon: "menubar.rectangle",
                        binding: $settingsManager.showInMenuBar
                    )
                    
                    Divider().opacity(0.5)
                    
                    ModernToggleRow(
                        title: "启用通知",
                        subtitle: "复制新内容时显示通知",
                        icon: "bell.fill",
                        binding: $settingsManager.enableNotifications
                    )
                }
            }
            
            // 历史记录
            ModernSettingsCard(title: "历史记录", icon: "clock.fill", color: .purple) {
                VStack(spacing: 16) {
                    ModernNumberStepper(
                        value: $settingsManager.maxItems,
                        range: 5...25,
                        step: 5,
                        title: "最大保存数量",
                        subtitle: "超过此数量的旧项目将被自动删除"
                    )
                }
            }
            
            // 智能Dock控制
            ModernSettingsCard(title: "智能 Dock 控制", icon: "dock.rectangle", color: .blue) {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "command")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.blue.opacity(0.1))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("快捷键呼出")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("自动显示 Dock 图标")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("✓")
                            .font(.system(.headline, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    
                    Divider().opacity(0.5)
                    
                    HStack {
                        Image(systemName: "escape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.blue.opacity(0.1))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ESC 键隐藏")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("自动隐藏 Dock 图标")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("✓")
                            .font(.system(.headline, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    
                    Divider().opacity(0.5)
                    
                    HStack {
                        Image(systemName: "gear.badge.checkmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.blue.opacity(0.1))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("无需手动管理")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("完全自动化处理")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("✓")
                            .font(.system(.headline, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
    
    // 界面设置
    @ViewBuilder
    private func interfaceSettingsView() -> some View {
        LazyVStack(spacing: 24) {
            // 显示选项
            ModernSettingsCard(title: "显示选项", icon: "eye.fill", color: .purple) {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("预览尺寸")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("调整图片和内容预览的大小")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Picker("", selection: $settingsManager.previewSize) {
                            Text("小").tag("small")
                            Text("中").tag("medium")
                            Text("大").tag("large")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 140)
                    }
                    
                    Divider().opacity(0.5)
                    
                    ModernToggleRow(
                        title: "显示行号",
                        subtitle: "在文本内容中显示行号",
                        icon: "number.circle.fill",
                        binding: $settingsManager.showLineNumbers
                    )
                    

                }
            }
            
            // 主题与外观
            ModernSettingsCard(title: "主题与外观", icon: "paintbrush.fill", color: .orange) {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("界面主题")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("选择应用的外观主题")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Picker("", selection: $settingsManager.themeMode) {
                            Text("跟随系统").tag("system")
                            Text("浅色").tag("light")
                            Text("深色").tag("dark")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 160)
                    }
                    
                    Divider().opacity(0.5)
                    
                    ModernToggleRow(
                        title: "动画效果",
                        subtitle: "启用界面动画和过渡效果",
                        icon: "sparkles",
                        binding: $settingsManager.enableAnimations
                    )
                }
            }
        }
    }
    
    // 性能设置
    @ViewBuilder
    private func performanceSettingsView() -> some View {
        LazyVStack(spacing: 24) {
            // 监控设置
            ModernSettingsCard(title: "监控设置", icon: "chart.line.uptrend.xyaxis", color: .green) {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("监控间隔")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("剪贴板检查频率（秒）")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
Slider(value: $settingsManager.monitoringInterval, in: 0.1...2.0, step: 0.1)
                                .frame(width: 100)
                            Text(String(format: "%.1f", settingsManager.monitoringInterval))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }
                }
            }
            
            // 图片处理
            ModernSettingsCard(title: "图片处理", icon: "photo.fill", color: .blue) {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最大图片尺寸")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("图片预览的最大尺寸（像素）")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Slider(value: $settingsManager.maxImageSize, in: 200...2000, step: 50)
                                .frame(width: 100)
                            Text(String(format: "%.0f", settingsManager.maxImageSize))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }
                    
                    Divider().opacity(0.5)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("压缩质量")
                                .font(.system(.body, design: .default, weight: .medium))
                            Text("图片压缩质量（0.1-1.0）")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Slider(value: $settingsManager.compressionQuality, in: 0.1...1.0, step: 0.05)
                                .frame(width: 100)
                            Text(String(format: "%.2f", settingsManager.compressionQuality))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }
                }
            }
            
            // 内存管理
            ModernSettingsCard(title: "内存管理", icon: "memorychip.fill", color: .purple) {
                ModernActionButton(
                    title: "优化内存",
                    subtitle: "清理不必要的缓存数据",
                    icon: "arrow.clockwise",
                    color: .purple
                ) {
                    // 实际的内存优化逻辑
                    ImageCacheManager.shared.clearCache()
                    // 显示反馈
                    FeedbackManager.shared.showSuccess("内存优化完成")
                }
            }
        }
    }
    
    // 快捷键设置
    @ViewBuilder
    private func shortcutSettingsView() -> some View {
        LazyVStack(spacing: 24) {
            // 全局快捷键
            ModernSettingsCard(title: "全局快捷键", icon: "command.circle.fill", color: .orange) {
                VStack(spacing: 12) {
                    ModernShortcutRow(keys: "⌃+⌘+V", description: "显示/隐藏窗口")
                }
            }
            
            // 应用内快捷键
            ModernSettingsCard(title: "应用内快捷键", icon: "keyboard.fill", color: .blue) {
                VStack(spacing: 12) {
                    ModernShortcutRow(keys: "⌘+1...9", description: "快速复制对应序号的项目")
                    Divider().opacity(0.3)
                    ModernShortcutRow(keys: "ESC", description: "隐藏窗口并隐藏 Dock 图标")
                    Divider().opacity(0.3)
                    // ModernShortcutRow(keys: "⌘+F", description: "聚焦搜索框")
                    // Divider().opacity(0.3)
                    // ModernShortcutRow(keys: "↑ / ↓", description: "选择上/下一个项目")
                    // Divider().opacity(0.3)
                    ModernShortcutRow(keys: "Enter", description: "复制选中项目")
                    Divider().opacity(0.3)
                    ModernShortcutRow(keys: "Delete", description: "删除选中项目")
                }
            }
            
            // 快捷键提示
            ModernInfoCard(
                title: "使用提示",
                icon: "lightbulb",
                color: .yellow,
                items: [
                    ("应用内快捷键", "在应用内按 Cmd+1-9 快速复制对应内容"),
                    ("搜索过滤", "输入关键词快速定位内容"),
                    ("快速操作", "支持键盘和鼠标混合操作")
                ]
            )
        }
    }
    
    // 高级设置
    @ViewBuilder
    private func advancedSettingsView() -> some View {
        VStack(spacing: 30) {
            Spacer()
            
            // 高级功能暂时禁用提示
            VStack(spacing: 20) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                VStack(spacing: 12) {
                    Text("高级功能即将推出")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("高级功能正在开发中，将在后续版本中提供")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("敬请期待更多强大功能！")
                        .font(.callout)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 存储管理页面
    @ViewBuilder
    private func storageSettingsView() -> some View {
        VStack(spacing: 24) {
            // 标题
            HStack {
                Image(systemName: "folder.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("存储管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // 存储信息卡片
            VStack(spacing: 16) {
                HStack {
                    Text("存储信息")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("刷新") {
                        self.storageInfo = self.clipboardManager.getStorageInfo()
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
                
                // 存储详情
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("存储位置：")
                                .fontWeight(.medium)
                            Text(storageInfo.cachePath)
                                .foregroundColor(.secondary)
                                .help(storageInfo.cachePath)
                            Spacer()
                            Button("打开文件夹") {
                                let url = URL(fileURLWithPath: self.storageInfo.cachePath)
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(BorderedButtonStyle())
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("存储项目数量")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(storageInfo.itemCount)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("占用空间")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(ByteCountFormatter().string(fromByteCount: storageInfo.totalSize))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .padding()
                }
            }
            
            // 清理选项
            VStack(spacing: 16) {
                HStack {
                    Text("清理选项")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                GroupBox {
                    VStack(spacing: 12) {
                        ModernCleanupDaysStepper(
                            value: $settingsManager.autoCleanupDays,
                            title: "自动清理周期",
                            subtitle: "系统会自动清理超过指定天数的旧内容"
                        )
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("手动清理")
                                    .fontWeight(.medium)
                                Text("立即清理所有历史内容和临时文件")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("清理全部") {
                                let alert = NSAlert()
                                alert.messageText = "确认清理"
                                alert.informativeText = "这将删除所有历史剪贴板内容和相关文件，此操作不可撤销。"
                                alert.addButton(withTitle: "清理")
                                alert.addButton(withTitle: "取消")
                                alert.alertStyle = .warning
                                
                                if alert.runModal() == .alertFirstButtonReturn {
                                    self.clipboardManager.performManualCleanup()
                                    self.storageInfo = self.clipboardManager.getStorageInfo()
                                    self.alertTitle = "清理完成"
                                    self.alertMessage = "已成功清理所有历史内容和临时文件"
                                    self.showingExportAlert = true
                                }
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                            .foregroundColor(.white)
                            .disabled(storageInfo.itemCount == 0)
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
        }
        .padding(24)
        .onAppear {
            self.storageInfo = self.clipboardManager.getStorageInfo()
        }
    }
    
    // 关于页面
    @ViewBuilder
    private func aboutView() -> some View {
        VStack(spacing: 24) {
            // 应用信息
            VStack(spacing: 16) {
                // 使用应用图标
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                } else {
                    // 回退图标
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("OneClip")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("智能剪贴板管理器")
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("版本 1.1.0")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
            
            // 功能特性
            ModernSettingsCard(title: "主要功能", icon: "star.fill", color: .orange) {
                VStack(spacing: 16) {
                    FeatureRow(icon: "doc.on.clipboard", title: "智能剪贴板管理", description: "自动保存和分类剪贴板内容")
                    
                    Divider().opacity(0.5)
                    
                    FeatureRow(icon: "magnifyingglass", title: "快速搜索", description: "即时搜索和过滤历史记录")
                    
                    Divider().opacity(0.5)
                    
                    FeatureRow(icon: "photo", title: "多媒体支持", description: "支持文本、图片、文件等多种格式")
                    
                    Divider().opacity(0.5)
                    
                    FeatureRow(icon: "keyboard", title: "全局快捷键", description: "随时随地快速访问")
                }
            }
            
            // 开发者信息
            VStack(spacing: 8) {
                Text("开发者：Wcowin")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                Text("联系我：wcowin@qq.com")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)                
                Text("© 2025 OneClip. All rights reserved.")
                    .font(.system(.caption, design: .default))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 辅助视图

// 特性行
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


// 空状态视图
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "clipboard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("剪贴板为空")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                
                Text("复制一些内容开始使用")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            // 快速提示
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                    Text("⌘ + C 复制内容到剪贴板")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                    Text("⌘ + ^ +V 打开历史记录")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                    Text("点击右上角 ? 查看更多快捷键")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial.opacity(0.5))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// 视觉效果视图
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// 键盘按键样式
struct KeyboardKey: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

// MARK: - 现代化设置组件

// 现代化设置卡片 - 简洁设计
struct ModernSettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 简化的标题区域
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(color.opacity(0.1))
                    )
                
                Text(title)
                    .font(.system(.headline, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // 内容区域
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .opacity(0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// 现代化操作按钮
struct ModernActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDestructive ? .white : color)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isDestructive ? color.opacity(0.8) : color.opacity(0.2))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 1.0 : 0.5)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? .white.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            // 使用更平滑的动画来减少抖动
            let settingsManager = SettingsManager.shared
            if settingsManager.enableAnimations {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
    }
}

// 现代化开关行 - 简洁设计
struct ModernToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var binding: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: $binding)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
        .padding(.vertical, 4)
    }
}

// 现代化信息卡片
struct ModernInfoCard: View {
    let title: String
    let icon: String
    let color: Color
    let items: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(color)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(item.1)
                                .font(.system(.caption2))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(
            .init(top: 16, leading: 16, bottom: 12, trailing: 16)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// 现代化快捷键行
struct ModernShortcutRow: View {
    let keys: String
    let description: String
    
    var body: some View {
        HStack {
            Text(description)
                .font(.system(.body, design: .default))
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 4) {
                ForEach(keys.components(separatedBy: "+"), id: \.self) { key in
                    KeyboardKey(text: key.trimmingCharacters(in: .whitespaces))
                }
            }
        }
    }
}

// 标签页按钮 - 优化可读性
struct SettingsTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    // 优化的前景色
    private var adaptiveIconColor: Color {
        if isSelected {
            return .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.8) : .secondary.opacity(0.9)
        }
    }
    
    private var adaptiveTextColor: Color {
        if isSelected {
            return .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.95) : .primary.opacity(0.9)
        }
    }
    
    // 优化的背景渐变
    private var adaptiveBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark 
                ? [.blue.opacity(0.85), .blue.opacity(0.65)]
                : [.blue.opacity(0.9), .blue.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // 优化的阴影颜色
    private var adaptiveShadowColor: Color {
        colorScheme == .dark ? .blue.opacity(0.4) : .blue.opacity(0.3)
    }
    
    // 优化的边框颜色
    private var adaptiveStrokeColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.25) : Color.white.opacity(0.2)
        } else {
            return colorScheme == .dark ? Color.gray.opacity(0.3) : Color.clear
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(adaptiveIconColor)
                .frame(width: 18, height: 16)
            
            Text(title)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundColor(adaptiveTextColor)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(adaptiveBackgroundGradient)
                        .shadow(color: adaptiveShadowColor, radius: 4, x: 0, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            colorScheme == .dark 
                                ? Color.gray.opacity(0.08) 
                                : Color.clear
                        )
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(adaptiveStrokeColor, lineWidth: isSelected ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(SettingsManager.shared.enableAnimations ? .easeInOut(duration: 0.2) : .none, value: isSelected)
    }
}

// 现代化侧边栏按钮 - 简洁设计
struct ModernSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20, height: 20)
                
                Text(title)
                    .font(.system(.body, design: .default, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected ? 
                        Color.accentColor.opacity(0.1) :
                        (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            let settingsManager = SettingsManager.shared
            if settingsManager.enableAnimations {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 支持行号的文本组件
struct LineNumberedTextView: View {
    let text: String
    let showLineNumbers: Bool
    let maxLines: Int?
    @State private var isHovered: Bool = false
    @State private var isExpanded: Bool = false
    
    // 缓存分割后的行，避免重复计算
    private var textLines: [String] {
        let lines = text.components(separatedBy: .newlines)
        return lines
    }
    
    // 显示的行数
    private var displayLines: [String] {
        if isExpanded || maxLines == nil {
            return textLines
        }
        if let maxLines = maxLines {
            return Array(textLines.prefix(maxLines))
        }
        return textLines
    }
    
    // 检查是否有更多内容
    private var hasMoreContent: Bool {
        guard let maxLines = maxLines else { return false }
        return textLines.count > maxLines
    }
    
    init(text: String, showLineNumbers: Bool = false, maxLines: Int? = nil) {
        self.text = text
        self.showLineNumbers = showLineNumbers
        self.maxLines = maxLines
    }
    
    var body: some View {
        if showLineNumbers && !text.isEmpty {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    // 行号列
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .frame(minWidth: 20, alignment: .trailing)
                                .padding(.vertical, 1)
                        }
                    }
                    .padding(.trailing, 4)
                    
                    // 内容列
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.body, design: .default))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 1)
                        }
                        
                        // 省略号提示
                        if hasMoreContent && !isExpanded {
                            HStack {
                                Text("...")
                                    .font(.system(.body, design: .default))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 1)
                                Spacer()
                                Text("悬浮查看更多")
                                    .font(.system(.caption, design: .default))
                                    .foregroundColor(.blue.opacity(0.7))
                                    .opacity(isHovered ? 1.0 : 0.6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            )
            .scaleEffect(isHovered && hasMoreContent ? 1.02 : 1.0)
            .shadow(color: .black.opacity(isHovered && hasMoreContent ? 0.1 : 0.05), radius: isHovered && hasMoreContent ? 8 : 2)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                    if hovering && hasMoreContent {
                        isExpanded = true
                    } else if !hovering {
                        isExpanded = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isExpanded)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(.body, design: .default))
                    .lineLimit(isExpanded ? nil : maxLines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 省略号提示（非行号模式）
                if hasMoreContent && !isExpanded {
                    HStack {
                        Spacer()
                        Text("悬浮查看更多")
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.blue.opacity(0.7))
                            .opacity(isHovered ? 1.0 : 0.6)
                    }
                }
            }
            .scaleEffect(isHovered && hasMoreContent ? 1.01 : 1.0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                    if hovering && hasMoreContent {
                        isExpanded = true
                    } else if !hovering {
                        isExpanded = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
    }
}

// MARK: - 首次使用欢迎页面
struct WelcomeStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 欢迎图标
            VStack(spacing: 16) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)
                
                VStack(spacing: 8) {
                    Text("欢迎使用 OneClip！")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("智能剪贴板管理器")
                        .font(.system(.callout, design: .default, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            
            // 功能介绍
            VStack(spacing: 20) {
                WelcomeFeatureRow(
                    icon: "doc.on.clipboard",
                    title: "自动保存",
                    description: "复制的内容会自动保存到历史记录"
                )
                
                WelcomeFeatureRow(
                    icon: "keyboard",
                    title: "快捷键",
                    description: "使用 ⌘⌃V 快速显示/隐藏窗口"
                )
                
                WelcomeFeatureRow(
                    icon: "menubar.rectangle",
                    title: "菜单栏",
                    description: "点击菜单栏图标快速访问剪贴板"
                )
            }
            .padding(.horizontal, 8)
            
            // 使用提示
            VStack(spacing: 12) {
                Text("开始使用")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("复制任何内容到剪贴板，它会自动出现在这里。")
                    .font(.system(.callout, design: .default))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 欢迎页面功能行
struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.callout, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// 快捷键帮助视图
struct ShortcutsHelpView: View {
    let onDismiss: () -> Void
    
    private let shortcuts = [
        ("⌘ + 1-9", "快速复制并粘贴"),
        ("⌘ + ^ + V", "显示/隐藏窗口"),
        ("⌘ + Q", "退出应用"),
        ("Esc", "关闭窗口(没有选中项时)"),
        ("Enter", "复制选中项"),
        ("Delete", "删除选中项")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.blue)
                
                Text("快捷键帮助")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                
                Spacer()
                
                // 关闭按钮
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("关闭")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial)
            
            // 快捷键列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                        HStack(spacing: 16) {
                            // 快捷键
                            Text(shortcut.0)
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.gray.opacity(0.8))
                                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                )
                            
                            // 描述
                            Text(shortcut.1)
                                .font(.system(.body, design: .default))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                        
                        if index < shortcuts.count - 1 {
                            Divider()
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            
            // 底部提示
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                
                Text("提示：大部分快捷键在窗口激活时可用")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

// MARK: - 现代化数字步进器组件
struct ModernNumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    init(value: Binding<Int>, range: ClosedRange<Int> = 10...1000, step: Int = 1, title: String, subtitle: String) {
        self._value = value
        self.range = range
        self.step = step
        self.title = title
        self.subtitle = subtitle
    }
    
    private var previewText: String {
        if value <= 50 {
            return "适合轻度使用"
        } else if value <= 200 {
            return "适合日常使用"
        } else if value <= 500 {
            return "适合重度使用"
        } else {
            return "适合专业使用"
        }
    }
    
    private var stepperBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ? [
                Color.white.opacity(0.08),
                Color.white.opacity(0.04)
            ] : [
                Color.white.opacity(0.9),
                Color.gray.opacity(0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var stepperBorderGradient: LinearGradient {
        LinearGradient(
            colors: isHovered ? [
                Color.blue.opacity(0.6),
                Color.purple.opacity(0.4)
            ] : [
                Color.primary.opacity(0.15),
                Color.primary.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // 预览文本 - 更突出的样式
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    
                    Text(previewText)
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 现代化步进器控件
            HStack(spacing: 2) {
                // 减少按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        let newValue = max(range.lowerBound, value - step)
                        if newValue != value {
                            value = newValue
                        }
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(value > range.lowerBound ? .white : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    value > range.lowerBound ?
                                    LinearGradient(
                                        colors: [Color.red.opacity(0.8), Color.red.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(value <= range.lowerBound)
                .help("减少 \(step)")
                .scaleEffect(value > range.lowerBound ? 1.0 : 0.95)
                
                // 数值显示区域 - 更现代的设计
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                    
                    Text("项目")
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                        .opacity(0.8)
                }
                .frame(width: 70, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(stepperBackgroundGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                )
                .onTapGesture {
                    // 可以添加直接编辑功能
                }
                
                // 增加按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        let newValue = min(range.upperBound, value + step)
                        if newValue != value {
                            value = newValue
                        }
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(value < range.upperBound ? .white : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    value < range.upperBound ?
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(value >= range.upperBound)
                .help("增加 \(step)")
                .scaleEffect(value < range.upperBound ? 1.0 : 0.95)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(stepperBorderGradient, lineWidth: 1.5)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
        .padding(.vertical, 4)
    }
}
