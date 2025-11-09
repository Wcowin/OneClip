---
title: OneClip 技术文档
description: OneClip macOS 剪贴板管理工具技术文档
---

<!-- OneClip 公告栏 -->
<div class="oneclip-announcement">
  <div class="oneclip-announcement-content">
    🎉 <strong>2025/12/31之前限时免费！</strong>
    <a href="https://oneclip.cloud/" target="_blank">OneClip</a>
    - 剪贴板管理工具，让你的工作效率翻倍！
    <a href="https://oneclip.cloud/" target="_blank" class="oneclip-cta">立即体验 →</a>
  </div>
</div>

# OneClip

OneClip 是一款**专为 macOS 打造**的剪贴板管理工具，采用 **SwiftUI 原生技术开发**，提供高效的剪贴板历史管理功能。

<div align="center" markdown="1">

![OneClip Logo](https://picx.zhimg.com/80/v2-34b000e56d1af7ef61092dcd031dfd9a_1440w.webp?source=2c26e567)

🚀 高效 · 🎨 现代 · ⚡ 流畅 · 🔒 安全

[![Release](https://img.shields.io/github/v/release/Wcowin/OneClip?style=for-the-badge&color=3b82f6)](https://github.com/Wcowin/OneClip/releases)
![Homebrew](https://img.shields.io/badge/Homebrew-Available-orange?style=for-the-badge&logo=homebrew&logoColor=white)
![macOS 12+](https://img.shields.io/badge/macOS-12%2B-0f172a?style=for-the-badge&logo=apple&logoColor=white)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white)

</div>

## 核心功能

- **剪贴板历史记录**：自动保存复制的内容，支持文本、图片、文件等多种格式
- **快速搜索**：支持关键词搜索历史记录
- **全局快捷键**：`Cmd+Option+V` 呼出主界面，`Cmd+Option+R` 呼出快捷回复
- **菜单栏集成**：在菜单栏显示最近的剪贴板内容
- **快捷回复**：预设常用文本，快速输入
- **多种界面模式**：支持丰富模式和极简模式切换

![OneClip界面预览](https://s1.imagehub.cc/images/2025/09/26/60252002e8ba561041062e3865e60f9a.jpg)

## 系统要求

- macOS 12.0 及以上
- 推荐使用 Apple Silicon（M 系列芯片）

## 安装方式

### Homebrew 安装（推荐）

```bash
brew install --cask wcowin/oneclip/oneclip
```

### 手动安装

1. 从 [GitHub Releases](https://github.com/Wcowin/OneClip/releases) 下载最新版本
2. 将 `OneClip.app` 拖入 `Applications` 文件夹
3. 如提示安全警告，在终端执行：
   ```bash
   sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
   ```

## 技术架构

### 核心技术栈

- Swift + SwiftUI
- Core Data（数据持久化）
- Carbon Framework（全局热键）
- Accessibility API（系统权限）

### 主要组件

- **ClipboardManager**: 剪贴板监控和数据管理
- **HotkeyManager**: 全局快捷键处理
- **WindowManager**: 窗口状态控制
- **SettingsManager**: 用户设置管理

### 权限要求

应用需要以下系统权限：

1. **辅助功能权限**（必需）
   - 用于全局快捷键功能
   - 在系统设置 → 隐私与安全性 → 辅助功能中添加 OneClip

2. **完全磁盘访问权限**（可选）
   - 用于文件类型内容的处理

## 基础使用

### 快捷键

- **主界面**: `Cmd+Option+V`
- **快捷回复**: `Cmd+Option+R`
- **菜单栏**: 点击状态栏图标

### 基本操作

1. 复制任何内容，自动保存到历史记录
2. 使用快捷键打开主界面浏览历史
3. 点击任意项目即可粘贴到当前位置
4. 支持搜索功能快速定位内容

### 主要设置

- **历史记录数量**: 可调整最大保存条目数
- **界面模式**: 丰富模式/极简模式切换
- **Dock 图标**: 可选择显示或隐藏
- **开机启动**: 支持自动启动

## 性能特点

- 内存占用：约 120MB
- CPU 使用率：空闲时 < 1%
- 启动时间：< 1 秒
- 快捷键响应：< 100ms

## 常见问题

### 快捷键不工作？
请确保已授予辅助功能权限，并重启应用。

### 状态栏图标消失？
重启应用或检查系统状态栏设置。

### 内存占用过高？
可在设置中调整历史记录数量限制。

## 获取 OneClip

### 免费试用

[🚀 免费下载试用](https://github.com/Wcowin/OneClip/releases/download/1.2.6/OneClip-1.2.6-apple-silicon.dmg){ .md-button }

### 解锁完整功能 🔥

[购买许可证 - 仅¥29.90起](purchase/index.md){ .md-button .md-button--primary }

---

需要帮助？查看 [常见问题](help/faq.md) 或 [联系我们](about/contact.md)。