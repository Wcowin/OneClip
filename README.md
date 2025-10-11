终生版0元优惠码：**FREE2024**   购买地址：https://oneclip.cloud/purchase/lifetime

<div align="center">
  <img src="https://picx.zhimg.com/80/v2-34b000e56d1af7ef61092dcd031dfd9a_1440w.webp?source=2c26e567" alt="OneClip Logo" width="120" height="120">
  <h1>OneClip</h1>
  <p><strong>一个简单专业的macOS 剪贴板管理工具</strong></p>
  <p>🚀 高效 · 🎨 现代 · ⚡ 流畅 · 🔒 安全</p>
</div>

<p align="center">
    <img src="https://img.shields.io/github/v/release/Wcowin/OneClip?style=for-the-badge&color=3b82f6" alt="Release" />
  <!-- <a href="https://github.com/Wcowin/OneClip/releases">
    <img src="https://img.shields.io/github/downloads/Wcowin/OneClip/total?style=for-the-badge&color=22c55e" alt="Downloads" />
  </a> -->
  <img src="https://img.shields.io/badge/Homebrew-Available-orange?style=for-the-badge&logo=homebrew&logoColor=white" alt="Homebrew" />
  <img src="https://img.shields.io/badge/macOS-12%2B-0f172a?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 12+" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 5.9+" />


---

## 概览

OneClip 是一款专为 macOS 打造的专业级剪贴板管理工具。采用 100% SwiftUI 原生技术，实现更顺滑的动画、更自然的系统融合与更低的资源占用。

### 🎯 核心能力

- **📋 智能记录**：自动保存剪贴板历史，支持文本、图片、文件等格式
- **🔎 极速搜索**：随打随搜，多维筛选快速定位

- **🗂️ 全格式支持**：图片/视频/音频/文档等，完整保留元数据

- **⌨️ 全局快捷键**：`Cmd+Option+V` 呼出主界面，支持自定义组合

- **🔄 快捷回复**: `Cmd+Option+R` 呼出快捷回复界面，支持自定义组合

- **🎯 菜单栏集成**：一键粘贴最近内容，状态实时可见

- **🔧 灵活控制**：Dock 图标、后台模式、主题适配均可配置

- **🍺 便捷安装**：支持 Homebrew 一键安装和自动更新

- **🎨 现代界面**：遵循 macOS 设计规范，毛玻璃与暗黑模式适配
![alt text](https://s1.imagehub.cc/images/2025/09/26/60252002e8ba561041062e3865e60f9a.jpg)

## ⬇下载与安装（推荐先看）

### 系统要求

- macOS 12.0 及以上
- Apple Silicon（M 系列）优先适配

### 🍺 Homebrew 安装（推荐）

如果你使用 Homebrew，可以通过以下命令快速安装：

```bash
# 一键安装（推荐）
brew install --cask wcowin/oneclip/oneclip

# 或者先添加 tap 再安装
brew tap wcowin/oneclip
brew install --cask oneclip
```

**更新应用：**
```bash
brew update && brew upgrade --cask oneclip
```

**卸载应用：**
```bash
brew uninstall --cask oneclip
```

### 手动安装

1) 前往 [Releases](https://github.com/Wcowin/OneClip/releases)或者[123网盘](https://www.123912.com/s/bXcDVv-HauG3) 下载最新版本。
2) 将 `OneClip.app` 拖入 `Applications`（应用程序）文件夹。
3) 首次打开若提示"来自未知开发者/已被隔离"，在终端执行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```
![image](https://s1.imagehub.cc/images/2025/09/29/4548190e0b2466dca56c3590ed15f880.png)
![image](https://s1.imagehub.cc/images/2025/09/15/25681c4221ff1bf29ee7c511e28e2654.png)

4) 或者打开`系统设置-隐私与安全性`选择仍然打开
![image](https://s1.imagehub.cc/images/2025/09/29/3ac62762dc125b32cba708eca3ba2144.png)

> 如果还是提示“无法打开/已损坏”，请参考：
> https://mp.weixin.qq.com/s/qjSx09tqNq1KfVug2WtQFg
>
> 想更省事？可使用[macOS 小助手](https://pan.quark.cn/s/f2302b6789b0)一键处理或者联系作者vip@oneclip.cloud



## 🏗️ 技术与架构（简版）

### 核心技术栈

- Swift 5.9+ 
- SwiftUI 
- Core Data 
- Carbon（全局热键） 
- Accessibility API 
- Xcode 15+

### 架构设计

```
            ┌─────────────────────────────────────────┐
            │                OneClip                  │
            ├─────────────────────────────────────────┤
            │     SwiftUI Views & ViewModels          │
            ├─────────────────────────────────────────┤
            │  ClipboardManager | SettingsManager     │
            │  HotkeyManager    |  WindowManager      │
            ├─────────────────────────────────────────┤
            │      Core Data | Carbon Framework       │
            ├─────────────────────────────────────────┤
            │           macOS System APIs             │
            └─────────────────────────────────────────┘
```

### 核心组件

- **ClipboardManager**: 剪贴板监控和数据管理
- **HotkeyManager**: 全局快捷键处理
- **WindowManager**: 窗口状态和显示控制
- **SettingsManager**: 用户偏好设置管理
- **FeedbackManager**: 用户反馈和通知系统

### 权限配置

首次启动时，OneClip 需要以下系统权限：

1. **辅助功能权限**（必需）
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 辅助功能
   - 添加 OneClip 并启用

2. **磁盘访问权限**（可选，用于文件操作）
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 完全磁盘访问
   - 添加 OneClip 并启用

## 🚀 使用指南

### 基础操作

1. **启动应用**
   - 双击 `OneClip.app` 启动
   - 应用将在状态栏显示图标

2. **快速访问**
   - 按 `Cmd+Option+V` 打开主界面
   - 点击状态栏图标快速粘贴

3. **快捷回复**
   - 按 `Cmd+Option+R` 打开快捷回复界面
   - 点击快捷回复即可粘贴

4. **内容管理**
   - 复制任何内容，自动保存到历史
   - 在主界面搜索和浏览历史记录
   - 点击任意项目即可粘贴

### 高级功能

- **分类筛选**: 按文本、图片、文件等类型筛选
- **搜索功能**: 快速查找历史内容
- **批量操作**: 清空历史、删除特定项目
- **设置自定义**: 调整快捷键、界面偏好等

## ⚙️ 配置选项

### 快捷键设置

- **主窗口呼出**: `Cmd+Option+V`
- **快捷回复呼出**: `Cmd+Option+R`
- **快速复制粘贴**: 系统默认 `Cmd+C/V`
- **菜单显示**: 状态栏左键点击

### 界面设置

- **Dock 图标**: 自动显示/隐藏
- **启动模式**: 开机自启动选项
- **主题适配**: 自动跟随系统主题
- **快捷回复**: 设置快捷回复快捷键
- **丰富模式/极简模式**: 切换界面模式

### 存储设置

- **历史数量**: 可设置最大保存条目数
- **数据清理**: 定期清理过期内容
- **文件处理**: 大文件存储策略

<!-- 开发构建部分暂不对外开放，如需试用内部版本请联系作者。 -->


## 📊 性能与体验

- **内存占用**: 运行时约120MB
- **CPU 使用**: 空闲时 < 1%
- **启动时间**: < 1 秒
- **响应速度**: 快捷键响应 < 100ms
- **存储效率**: 智能压缩，节省磁盘空间
- **性能优化**: 智能管理，优化性能
- **性能监控**: 实时监控性能指标
- **粘贴板自适应监控**: 根据活动与资源自动调整频率

## 🐛 常见问题（FAQ）

### Q: 快捷键不工作？
A: 请确保**已授予辅助功能权限**，并重启应用。

### Q: 无法复制文件？
A: 请检查完全磁盘访问权限是否已启用。

### Q: 应用无法启动？
A: 请确认系统版本为 macOS 12.0+，M1后续芯片，并检查应用完整性。

### Q: 状态栏图标消失？
A: 重启应用或检查系统状态栏设置。

### Q: 内存占用过高？
A: 可在设置中调整历史记录数量限制和检测间隔。


## 👨‍💻 作者信息

- **开发者**: [Wcowin](https://wcowin.work/blog/Mac/sunhuai/)
- **官方网站**: [https://oneclip.cloud](https://oneclip.cloud/)
- **联系邮箱**: [wcowin@qq.com](mailto:wcowin@qq.com)

## 🤝 反馈与支持

如果您在使用过程中遇到问题或有改进建议，欢迎通过以下方式联系：
  
- 📧 邮件: [wcowin@qq.com](mailto:wcowin@qq.com)
- 🐛 问题反馈: [GitHub Issues](https://github.com/Wcowin/OneClip/issues)
- 💡 功能建议: [GitHub Discussions](https://github.com/Wcowin/OneClip/discussions)
- 👉🏻 QQ群：[1060157293](https://qm.qq.com/q/ckSQ6MXgLm)

---

<div align="center">
  <p><strong>OneClip

  一个简单专业的macOS 剪贴板管理工具</strong></p>
  <p>© 2025 Wcowin. All rights reserved.</p>
</div>
