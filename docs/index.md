---
title: OneClip 文档
description: OneClip - 简单专业的 macOS 剪贴板管理工具
---

<div align="center" markdown="1">

![OneClip Logo](https://picx.zhimg.com/80/v2-34b000e56d1af7ef61092dcd031dfd9a_1440w.webp?source=2c26e567){ width="120" }

# OneClip

**一个简单专业的 macOS 剪贴板管理工具**

🚀 高效 · 🎨 现代 · ⚡️ 流畅 · 🔒 安全

[![Release](https://img.shields.io/github/v/release/Wcowin/OneClip?style=for-the-badge&color=3b82f6)](https://github.com/Wcowin/OneClip/releases)
[![Downloads](https://img.shields.io/github/downloads/Wcowin/OneClip/total?style=for-the-badge&color=22c55e)](https://github.com/Wcowin/OneClip/releases)
![Homebrew](https://img.shields.io/badge/Homebrew-Available-orange?style=for-the-badge&logo=homebrew&logoColor=white)
![macOS 12+](https://img.shields.io/badge/macOS-12%2B-0f172a?style=for-the-badge&logo=apple&logoColor=white)

</div>

---

## 概览

OneClip 是一款专为 macOS 打造的**专业级剪贴板管理工具**。采用 **100% SwiftUI** 原生技术，实现更顺滑的动画、更自然的系统融合与更低的资源占用。

!!! tip "为什么选择 OneClip？"
    - ✅ **纯原生开发**：100% SwiftUI，无第三方框架依赖，性能卓越
    - ✅ **独特创新**：栈粘贴板、拖拽容器等创新功能，提升工作效率
    - ✅ **隐私安全**：数据完全本地存储，无任何网络上传
    - ✅ **持续更新**：社群积极维护，快速响应用户反馈
    - ✅ **免费试用**：提供完整功能试用

![OneClip 主界面](https://i.imgant.com/v2/RKyVhgF.png)

## 🎯 核心功能

- **📋 智能记录**：自动保存剪贴板历史，支持文本、图片、文件等格式
- **🔎 极速搜索**：随打随搜，多维筛选快速定位
- **🗂️ 全格式支持**：图片/视频/音频/文档等，完整保留元数据
- **⌨️ 全局快捷键**：`⌘+⇧+V` 呼出主界面，支持自定义组合
- **� 快捷回复**：`⌘+⇧+R` 呼出快捷回复界面
- **🎨 布局多样**：支持列表/卡片双模式切换，支持 Paste 同款布局
- **📥 栈粘贴板**：`⌘+⇧+C` 呼出栈粘贴板，`⌘+V` 依次粘贴栈内容
- **📦 拖拽容器**：`⌘+⇧+D` 呼出拖拽容器，方便管理
- **🧀 OCR 识别**：支持屏幕/图片内容识别，OCR 翻译
- **🤖 AI 集成**：支持本地 AI（Ollama/LMStudio）和在线 AI 服务
- **☁️ 云同步**：支持 Syncthing 和自定义 iCloud 等多设备同步
- **👍 访达增强**：支持访达 `⌘+X` 剪切文件，然后 `⌘+V` 移动文件

![OneClip 功能展示](https://i.imgant.com/v2/Zn6arLh.png)

## ⬇️ 下载与安装

### 系统要求

- macOS 12.0 及以上
- Apple Silicon + Intel 支持

### 📦 安装方式

=== "Homebrew（推荐）"

    ```bash
    brew install --cask Wcowin/oneclip/oneclip
    ```

=== "GitHub Releases"

    1. 前往 [Releases 页面](https://github.com/Wcowin/OneClip/releases) 下载最新版本
    2. 将 `OneClip.app` 拖入 `Applications` 文件夹

=== "网盘下载"

    - [123网盘下载](https://www.123912.com/s/bXcDVv-HauG3)

### 🔓 解决安全提示

如提示"来自未知开发者"或"已损坏"：

**方法一：终端命令（推荐）**

```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```

**方法二：系统设置**

1. 打开 `系统设置` → `隐私与安全性`
2. 找到 OneClip 相关提示
3. 点击"仍然打开"

## ⌨️ 快捷键速查表

| 功能 | 默认快捷键 | 说明 |
|------|-----------|------|
| **主窗口呼出** | `⌘+⇧+V` | 打开/关闭主界面 |
| **快捷回复** | `⌘+⇧+R` | 呼出快捷回复窗口 |
| **栈面板呼出** | `⌘+⇧+C` | 打开栈粘贴板面板 |
| **依次粘贴** | `⌘+V` | 从栈中依次粘贴 |
| **拖拽容器** | `⌘+⇧+D` | 打开拖拽容器 |
| **预览** | `Space` | 预览选中内容 |

> 💡 所有快捷键均可在设置中自定义，支持检测冲突

## 🎬 功能演示

### 1️⃣ 主窗口 - 快速访问历史

- 按 `⌘+⇧+V` 呼出主窗口
- 支持列表/卡片双模式切换
- 实时搜索、分类筛选
- 点击即可粘贴到当前应用

### 2️⃣ 栈粘贴板 - 批量复制粘贴

- `⌘+⇧+C` 呼出栈面板
- 将多个项目加入栈中
- `⌘+V` 依次粘贴
- 适合表单填写、批量编辑场景

### 3️⃣ 快捷回复 - 常用文本模板

- `⌘+⇧+R` 呼出快捷回复
- 支持文本、图片、文件模板
- 可设置独立快捷键

### 4️⃣ 拖拽容器 - 文件临时存储

- `⌘+⇧+D` 呼出拖拽容器
- 暂存文件、图片等内容
- 支持拖出到其他应用

## 🔐 权限配置

首次启动时，OneClip 需要以下系统权限：

1. **辅助功能权限**（必需）
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 辅助功能
   - 添加 OneClip 并启用

2. **磁盘访问权限**（可选，用于文件操作）
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 完全磁盘访问
   - 添加 OneClip 并启用

## 📊 性能与体验

| 指标 | 数值 |
|------|------|
| 内存占用 | ~120MB |
| CPU 使用 | 空闲时 < 1% |
| 启动时间 | < 1 秒 |
| 响应速度 | < 100ms |

## 🛠️ 技术架构

- **Swift 5.9+** + **SwiftUI**（100% 原生）
- **SQLite + WAL**（数据持久化）
- **Carbon Framework**（全局热键）
- **Sparkle**（自动更新）

## 🚀 获取 OneClip

[🚀 免费下载试用](https://github.com/Wcowin/OneClip/releases){ .md-button }
[💎 购买许可证 - ¥29.90起](purchase/index.md){ .md-button .md-button--primary }

---

## 📮 联系方式

| 方式 | 链接 |
|------|------|
| 📧 **邮件** | [vip@oneclip.cloud](mailto:vip@oneclip.cloud) |
| 👥 **QQ 群** | [1060157293](https://qm.qq.com/q/xiImGHVMcM) |
| 🌐 **官网** | [https://oneclip.cloud](https://oneclip.cloud) |

需要帮助？查看 [常见问题](help/faq.md) 或 [联系我们](about/contact.md)。