# OneClip 源码构建指南

这是 OneClip 早期版本的开源代码，基于文件系统存储。当前正式版已迁移至数据库存储。

## 系统要求

- **macOS** 12.0+
- **Xcode** 15.0+
- **Swift** 5.9+

## 快速构建

### 方式一：使用构建脚本（推荐）

```bash
cd src
chmod +x build.sh
./build.sh
```

构建完成后，应用位于 `src/dist/OneClip.app`。

### 方式二：使用 Xcode

1. 打开 `src/OneClip.xcodeproj`
2. 选择 `OneClip` scheme
3. 按 `⌘+B` 构建 或 `⌘+R` 运行

### 方式三：命令行构建

```bash
cd src
xcodebuild -project OneClip.xcodeproj -scheme OneClip -configuration Release build
```

## 安装运行

构建完成后：

```bash
# 复制到应用程序文件夹
cp -R dist/OneClip.app /Applications/

# 或直接运行
open dist/OneClip.app
```

## 项目结构

```
src/
├── OneClip/                 # 主应用源码
├── OneClip.xcodeproj/       # Xcode 项目文件
├── OneClipTests/            # 单元测试
├── OneClipUITests/          # UI 测试
├── build.sh                 # 构建脚本
└── dist/                    # 构建输出目录
```

## 常见问题

### 构建失败：缺少签名

如果遇到签名问题，在 Xcode 中：
1. 选择项目 → Signing & Capabilities
2. 将 Team 改为 "None" 或你的开发者账号
3. 取消勾选 "Automatically manage signing"（如需要）

### 运行时提示"已损坏"

```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```

## 许可证

此早期版本代码仅供学习参考。
