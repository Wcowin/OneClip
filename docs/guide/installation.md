# 下载安装

## 系统要求

- macOS 12.0 及以上
- 推荐使用 Apple Silicon（M 系列芯片）
- 约 50MB 存储空间

## 安装方式

### Homebrew 安装（推荐）

```bash
brew install --cask wcowin/oneclip/oneclip
```

更新应用：
```bash
brew upgrade --cask oneclip
```

### 手动安装

1. 从 [GitHub Releases](https://github.com/Wcowin/OneClip/releases) 下载最新版本
2. 将 `OneClip.app` 拖入 `Applications` 文件夹
3. 双击启动应用

## 解决安全提示

如提示"来自未知开发者"，在终端执行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```

或在系统设置 → 隐私与安全性中点击"仍然打开"。

## 验证安装

安装成功后，您应该看到：

1. Applications 文件夹中的 OneClip.app
2. 应用正常启动
3. 状态栏显示 OneClip 图标