# 下载安装

## 系统要求

- macOS 12.0 及以上
- 推荐使用 Apple Silicon（M 系列芯片）
- Intel 处理器也支持
- 约 50MB 存储空间

## 安装方式

### Homebrew 安装（推荐）

```bash
brew install --cask wcowin/oneclip/oneclip
```

### 手动安装

1. 从 [GitHub Releases](https://github.com/Wcowin/OneClip/releases) 下载最新版本
2. 将 `OneClip.app` 拖入 `Applications` 文件夹
3. 双击启动应用

## 解决安全提示

如提示"已损坏"或"来自未知开发者"：

**方法一：终端命令（推荐）**

```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```

**方法二：系统设置**

1. 打开"系统设置" → "隐私与安全性"
2. 在"安全性"部分找到 OneClip 相关提示
3. 点击"仍然打开"

## 验证安装

安装成功后，您应该看到：

1. Applications 文件夹中的 OneClip.app
2. 应用正常启动
3. 状态栏显示 OneClip 图标

!!! tip "提示"
    OneClip 是后台运行的应用，启动后会在状态栏显示图标。使用快捷键 `⌘ + ⇧ + V` 打开主界面。

## 更新应用

**Homebrew 用户：**

```bash
brew upgrade --cask oneclip
```

**手动安装用户：**

从 [GitHub Releases](https://github.com/Wcowin/OneClip/releases) 下载最新版本替换即可。