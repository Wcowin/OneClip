# FAQ 常见问题

这里收集了用户最常遇到的问题和解决方案。

## 安装和启动

### Q: 下载后无法打开应用，提示"已损坏"或"来自未知开发者"

**A: 这是 macOS 的安全机制，解决方法：**

**方法一：终端命令（推荐）**
```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```

**方法二：系统设置**
1. 打开"系统设置" → "隐私与安全性"
2. 在"安全性"部分找到 OneClip 相关提示
3. 点击"仍然打开"

### Q: 应用启动后没有看到任何界面

**A: OneClip 是后台运行的应用，启动后会在状态栏显示图标。**

- 查看屏幕顶部右侧的状态栏
- 寻找 OneClip 的图标
- 使用快捷键 `⌘ + ⇧ + V` 打开主界面

### Q: Homebrew 安装失败

**A: 常见解决方法：**

```bash
# 更新 Homebrew
brew update

# 重新安装
brew install --cask wcowin/oneclip/oneclip
```

## 权限问题

### Q: 快捷键不工作

**A: 需要授予辅助功能权限：**

1. 打开"系统设置" → "隐私与安全性"
2. 选择"辅助功能"
3. 添加 OneClip 并启用
4. 重启 OneClip 应用

### Q: 无法复制文件

**A: 需要完全磁盘访问权限：**

1. 打开"系统设置" → "隐私与安全性"
2. 选择"完全磁盘访问"
3. 添加 OneClip 并启用

## 功能使用

### Q: 状态栏图标消失了

**A: 可能的原因和解决方法：**

- 检查设置中"显示菜单栏图标"是否开启
- 重启 OneClip 应用
- 检查系统状态栏设置

### Q: 历史记录没有保存

**A: 检查以下设置：**

- 确认剪贴板监控功能已开启
- 检查是否设置了内容过滤规则
- 验证辅助功能权限是否正确授予

### Q: 搜索功能不准确

**A: 搜索优化建议：**

- 使用关键词而非完整句子
- 尝试不同的关键词组合
- 使用类型筛选缩小范围

## 性能问题

### Q: 应用占用内存过高

**A: 内存优化方法：**

- 减少历史记录保存数量
- 定期清理历史记录
- 关闭不需要的功能

### Q: 快捷键响应缓慢

**A: 性能优化建议：**

- 检查系统资源使用情况
- 减少历史记录数量
- 重启应用

## 数据管理

### Q: 如何备份历史记录

**A: OneClip 使用 SQLite 存储数据：**

- 数据文件位于 `~/Library/Application Support/OneClip/`
- 可以复制整个文件夹进行备份
- 支持自定义存储位置
- 支持 Syncthing 等云同步方式

### Q: 如何清空所有历史记录

**A: 清空方法：**

- 在主界面右键选择"清空历史"
- 或在设置中找到清理选项
- 会有确认对话框防止误操作

## 系统兼容性

### Q: 支持哪些 macOS 版本

**A: 系统要求：**

- macOS 12.0 及以上
- 推荐使用 Apple Silicon（M 系列芯片）
- Intel 处理器也支持

### Q: 与其他剪贴板工具冲突

**A: 避免冲突的方法：**

- 关闭其他剪贴板管理工具
- 检查快捷键是否重复
- 确保只运行一个剪贴板工具

## 更新和维护

### Q: 如何更新到最新版本

**A: 更新方法：**

**Homebrew 用户：**
```bash
brew upgrade --cask oneclip
```

**手动安装用户：**

- 从 GitHub Releases 下载最新版本
- 替换 Applications 文件夹中的应用

### Q: 如何完全卸载 OneClip

**A: 卸载步骤：**

1. 退出 OneClip 应用
2. 删除 Applications 文件夹中的 OneClip.app
3. 删除数据文件：`~/Library/Application Support/OneClip/`
4. 删除设置文件：`~/Library/Preferences/com.oneclip.*`

**Homebrew 用户：**
```bash
brew uninstall --cask oneclip
```

## AI 功能

### Q: 如何使用 AI 功能？

**A: OneClip 支持本地 AI 和在线 AI 服务：**

**本地 AI（Ollama）：**

1. 安装 [Ollama](https://ollama.ai/)
2. 下载所需模型（如 `ollama pull llama2`）
3. 在 OneClip 设置中配置 Ollama 连接

**在线 AI 服务：**

1. 在设置中选择 AI 服务提供商（智谱清言、通义千问等）
2. 输入 API Key
3. 配置模型参数

### Q: 如何使用 OCR 功能？

**A: OneClip 支持多种 OCR 方式：**

- **图片 OCR**：右键点击图片 → OCR 识别
- **截图 OCR**：使用 OCR 全局快捷键截取屏幕区域
- **静默 OCR**：后台识别，不弹出窗口

## 许可证

### Q: 如何获取许可证？

**A: 购买方式：**

- 官网购买：[https://oneclip.cloud/purchase](https://oneclip.cloud/purchase)
- 使用优惠码：`OneClip2025`（10￥减免）

**激活方式：**

1. 打开 OneClip 设置 → 激活
2. 输入许可证密钥
3. 点击激活

**试用政策：**

- 免费 7 天试用完整功能
- 试用期结束后仍可使用基础功能

## 需要更多帮助？

如果以上解决方案无法解决您的问题：

- 📧 邮件：[vip@oneclip.cloud](mailto:vip@oneclip.cloud)
- 👥 QQ 群：[1060157293](https://qm.qq.com/q/xiImGHVMcM)

查看 [联系我们](../about/contact.md) 页面获取更多联系方式。