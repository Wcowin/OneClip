import SwiftUI
import AppKit

// 现代化列表项视图
struct ClipboardItemRowView: View {
    let item: ClipboardItem
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onDelete: () -> Void
    let onSmartPaste: () -> Void // 新增：直接粘贴回调
    let index: Int
    let isSelected: Bool // 新增：是否被选中
    let onHover: (Bool) -> Void // 新增：悬浮状态回调
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var tapTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false
    @State private var localIsFavorite: Bool = false // 本地收藏状态，用于立即响应
    @EnvironmentObject private var settingsManager: SettingsManager
    
    // 静态样式缓存 - 优化美化版本
    private static let gradientText = LinearGradient(
        colors: [.primary, .primary.opacity(0.85), .blue.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // 现代化删除按钮渐变
    private static let deleteButtonGradient = LinearGradient(
        colors: [Color.red.opacity(0.8), Color.red.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // 数字指示器颜色（原版样式）
    private func getNumberColor() -> Color {
        return .primary  // 恢复原版样式，使用系统主色调
    }
    
    // 根据内容类型获取光辉颜色（文字类型不返回光辉颜色）
    private func getGlowColor() -> Color? {
        switch item.type {
        case .text:
            return nil  // 文字类型不显示光辉效果
        case .image:
            return .green
        case .file:
            return .orange
        case .video:
            return .purple
        case .audio:
            return .red
        case .document:
            return .cyan
        case .code:
            return .mint
        case .archive:
            return .pink
        case .executable:
            return .indigo
        }
    }
    
    var body: some View {
        mainContent
            .background(cardBackground)
            .contextMenu {
                Button(action: onSingleTap) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                
                Button(action: onSmartPaste) {
                    Label("直接粘贴到光标位置", systemImage: "arrow.up.doc.on.clipboard")
                }
                
                Divider()
                
                Button(action: {
                    // 异步更新FavoriteManager，让onReceive监听器来更新UI状态
                    Task {
                        FavoriteManager.shared.toggleFavorite(item)
                    }
                }) {
                    Label(
                        localIsFavorite ? "取消收藏" : "添加收藏",
                        systemImage: localIsFavorite ? "star.fill" : "star"
                    )
                }
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                    if let searchURL = URL(string: "https://www.google.com/search?q=\(item.content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        NSWorkspace.shared.open(searchURL)
                    }
                }) {
                    Label("搜索此内容", systemImage: "magnifyingglass")
                }
                .disabled(item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                Divider()
                
                Button(role: .destructive, action: confirmDelete) {
                    Label("删除", systemImage: "trash")
                }
            }
            .onHover { hovering in
                // 使用更平滑的动画来减少抖动
                if settingsManager.enableAnimations {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                    }
                } else {
                    isHovered = hovering
                }
                // 调用悬浮状态回调
                onHover(hovering)
            }
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .onTapGesture(count: 1, perform: handleSingleTap)
            .onTapGesture(count: 2, perform: handleDoubleTap)
            .alert("确认删除", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    performDelete()
                }
            } message: {
                Text("确定要删除这个剪贴板项目吗？此操作无法撤销。")
            }
            .onAppear {
                // 初始化本地收藏状态
                localIsFavorite = FavoriteManager.shared.isFavorite(item)
            }
            .onChange(of: item.id) { _, _ in
                // 当item变化时更新本地状态
                localIsFavorite = FavoriteManager.shared.isFavorite(item)
            }
            .onReceive(FavoriteManager.shared.$favoriteItems) { _ in
                // 监听FavoriteManager状态变化，但添加延迟以避免覆盖用户的立即操作
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let newFavoriteState = FavoriteManager.shared.isFavorite(item)
                    if localIsFavorite != newFavoriteState {
                        if settingsManager.enableAnimations {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                localIsFavorite = newFavoriteState
                            }
                        } else {
                            localIsFavorite = newFavoriteState
                        }
                    }
                }
            }
    }
    
    private var mainContent: some View {
        HStack(spacing: 20) {
            numberIndicator
            contentArea
            if isHovered {
                HStack(spacing: 10) {
                    // 收藏按钮 - 增强视觉效果
                    Button(action: {
                        // 立即更新本地状态，提供即时的UI反馈
                        let newFavoriteState = !localIsFavorite
                        localIsFavorite = newFavoriteState
                        
                        // 使用动画增强用户体验
                        if settingsManager.enableAnimations {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                localIsFavorite = newFavoriteState
                            }
                        }
                        
                        // 异步更新FavoriteManager，但不依赖返回值
                        Task {
                            await MainActor.run {
                                FavoriteManager.shared.toggleFavorite(item)
                            }
                        }
                    }) {
                        Image(systemName: localIsFavorite ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(localIsFavorite ? 
                                LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing) : 
                                LinearGradient(colors: [.gray.opacity(0.8), .gray.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .scaleEffect(localIsFavorite ? 1.15 : 1.0)
                            .shadow(color: localIsFavorite ? .yellow.opacity(0.3) : .clear, radius: 2)
                    }
                    .buttonStyle(ModernCircleButtonStyle(size: .small))
                    .help(localIsFavorite ? "取消收藏" : "添加收藏")
                    
                    // 复制按钮 - 增强视觉效果
                    Button(action: onSingleTap) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LinearGradient(
                                colors: [.blue, .cyan.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .shadow(color: .blue.opacity(0.2), radius: 1)
                    }
                    .buttonStyle(ModernCircleButtonStyle(size: .small))
                    .help("复制")
                    
                    // 直接粘贴按钮 - 新增功能
                    Button(action: onSmartPaste) {
                        Image(systemName: "arrow.up.doc.on.clipboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LinearGradient(
                                colors: [.green, .mint.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .shadow(color: .green.opacity(0.2), radius: 1)
                    }
                    .buttonStyle(ModernCircleButtonStyle(size: .small))
                    .help("直接粘贴到光标位置")
                    
                    deleteButton
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.8))
                        .overlay(
                            Capsule()
                                .stroke(LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                    removal: .scale(scale: 1.1).combined(with: .opacity).combined(with: .move(edge: .trailing))
                ))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
    
    @ViewBuilder
    private var numberIndicator: some View {
        if index < 9 {
            Text("\(index + 1)")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(getNumberColor())
                .frame(width: 26, height: 26)
                .background(numberBackground)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .shadow(color: .black.opacity(0.1), radius: isHovered ? 2 : 1)
        }
    }
    
    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            contentView
            bottomInfo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var contentView: some View {
        if item.type == .image {
            ImagePreviewView(item: item)
                .id("\(item.id)-detail-\(item.timestamp.timeIntervalSince1970)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .shadow(color: .blue.opacity(0.05), radius: 2, x: 0, y: 1)
        } else {
            LineNumberedTextView(
                text: item.content,
                showLineNumbers: settingsManager.showLineNumbers,
                maxLines: 3
            )
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 0.5)
                    )
            )
        }
    }
    
    private var bottomInfo: some View {
        HStack(spacing: 12) {
            ModernItemTypeBadge(type: item.type)
                .scaleEffect(isHovered ? 1.02 : 1.0)
            
            Spacer()
            
            Text(item.timestamp, style: .relative)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [.secondary.opacity(0.9), .secondary.opacity(0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.6))
                        .overlay(
                            Capsule()
                                .stroke(LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0.5)
        }
    }
    
    private var deleteButton: some View {
        Button(action: confirmDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Self.deleteButtonGradient)
                .background(deleteButtonBackground)
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .shadow(color: .red.opacity(0.3), radius: isHovered ? 3 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .help("删除项目")
        .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .trailing)))
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay(cardBorder)
            .shadow(
                color: .black.opacity((isHovered || isSelected) ? 0.2 : 0.1),
                radius: (isHovered || isSelected) ? 16 : 8,
                x: 0,
                y: (isHovered || isSelected) ? 8 : 4
            )
            .modifier(ConditionalGlowModifier(
                glowColor: getGlowColor(),
                isHovered: isHovered,
                isSelected: isSelected
            ))
            .scaleEffect(isPressed ? 0.98 : 1.0)
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(
                getBorderColor().opacity((isHovered || isSelected) ? 0.6 : 0.3),
                lineWidth: isSelected ? 2.5 : (isHovered ? 2.0 : 1.5)
            )
    }
    
    // 获取边框颜色，为文本类型特别指定蓝色
    private func getBorderColor() -> Color {
        if item.type == .text {
            // 文本类型使用蓝色边框，与文本标签颜色一致
            return .blue
        } else {
            // 其他类型使用光辉颜色或默认颜色
            return getGlowColor() ?? .secondary
        }
    }
    
    private var numberBackground: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1.0)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var deleteButtonBackground: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1.0)
            )
    }
    
    // MARK: - Actions
    
    private func handleSingleTap() {
        // 取消之前的任务
        tapTask?.cancel()
        
        // 创建新的延迟任务
        tapTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms延迟
            
            if !Task.isCancelled {
                await MainActor.run {
                    onSingleTap()
                }
            }
        }
    }
    
    private func handleDoubleTap() {
        // 取消单击任务
        tapTask?.cancel()
        
        // 立即执行双击
        onDoubleTap()
    }
    
    private func confirmDelete() {
        showDeleteConfirmation = true
    }
    
    private func performDelete() {
        onDelete()
    }
}