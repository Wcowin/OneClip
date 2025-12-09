# 架构设计

OneClip 采用简洁的 MVVM 架构设计，基于 **100% SwiftUI** 原生技术构建，确保高性能和良好的用户体验。

## 整体架构

### 核心层次

```
┌─────────────────────────────────────────┐
│              OneClip App                │
├─────────────────────────────────────────┤
│     SwiftUI Views & ViewModels          │
├─────────────────────────────────────────┤
│  ClipboardManager | SettingsManager     │
│  HotkeyManager    | WindowManager       │
│  FavoriteManager  | BackupManager       │
├─────────────────────────────────────────┤
│     SQLite  | Carbon  | Accessibility   │
├─────────────────────────────────────────┤
│         macOS System APIs               │
└─────────────────────────────────────────┘
```

### 设计原则

- **MVVM 模式**: View + ObservableObject 管理器
- **单一职责**: 每个管理器负责特定功能
- **数据驱动**: 使用 SQLite + WAL 进行数据持久化

## 核心组件

| 组件 | 职责 |
|------|------|
| **ClipboardManager** | 剪贴板监控和数据管理 |
| **SettingsManager** | 用户偏好设置管理 |
| **WindowManager** | 窗口状态和显示控制 |
| **HotkeyManager** | 全局快捷键处理 |
| **ClipboardStore** | SQLite 数据持久化 |
| **AIService** | AI 功能集成 |
| **SyncthingManager** | 云同步管理 |

### ClipboardManager

负责剪贴板监控和历史记录管理。

- 监控系统剪贴板变化
- 保存和管理历史记录
- 提供搜索和筛选功能
- 处理不同类型的内容

### HotkeyManager

处理全局快捷键功能。

- 基于 Carbon 框架 API
- 支持自定义快捷键组合
- 自动检测快捷键冲突

### AIService

集成 AI 功能。

- 支持本地 AI（Ollama/LMStudio）
- 支持在线 AI 服务（智谱清言、通义千问）
- OCR 识别和翻译

## 数据架构

### SQLite + WAL

OneClip 使用 SQLite + WAL 进行数据持久化，主要实体包括：

**ClipboardItem（剪贴板项目）**

- id: 唯一标识符
- content: 内容数据
- type: 内容类型（文本、图片、文件等）
- createdAt: 创建时间
- sourceApp: 来源应用
- isFavorite: 是否收藏

**QuickReply（快捷回复）**

- id: 唯一标识符
- title: 标题
- content: 内容
- category: 分类

### 数据存储

- **SQLite**: 主要数据存储
- **UserDefaults**: 应用设置
- **文件系统**: 大型文件和图片缓存

## 搜索功能

### 搜索实现

OneClip 提供简单高效的搜索功能：

**搜索方式：**

- 关键词匹配
- 内容类型筛选
- 时间范围筛选

**实现特点：**

- 实时搜索
- 支持中英文
- 模糊匹配

## 安全和隐私

### 数据安全

- **本地存储**: 所有数据仅存储在本地设备
- **权限控制**: 需要用户授权辅助功能权限
- **数据清理**: 支持手动和自动清理历史记录

### 隐私保护

- **敏感内容过滤**: 可设置过滤规则避免记录敏感信息
- **应用排除**: 可排除特定应用的内容记录
- **用户控制**: 用户完全控制数据的收集和使用

## 性能优化策略

- **批量更新机制**：减少频繁的视图重绘
- **搜索防抖**：延迟触发更新，避免每个字符都重新搜索
- **索引预计算**：按类型分组，快速筛选
- **智能监控**：根据活动状态自适应调整监控频率
- **懒加载缓存**：按需加载图片和文件内容
- **内存压力管理**：自动释放不必要的缓存

## 技术栈

- **Swift 5.9+**
- **SwiftUI**（100% 原生）
- **SQLite + WAL**（数据持久化）
- **Carbon Framework**（全局热键）
- **Accessibility API**（权限管理）
- **Sparkle**（自动更新）
- **Xcode 15+**