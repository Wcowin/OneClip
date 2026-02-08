[English](README_EN.md) | [简体中文](README.md)

---

2026/02/06 Lifetime edition fixed ¥5 discount code: **OneClip2026** (last 15) | Redeem: https://oneclip.cloud/purchase/lifetime

> [!NOTE]
> Join our community:
> [OneClip QQ Group](https://qm.qq.com/q/xiImGHVMcM) | [Telegram Group](https://t.me/+I7S6R0pw5180YzRl)

> 💡 Free lifetime codes: Hundreds of free codes have been given out; more will be randomly posted here or in the QQ group | Same redeem link above

> [!NOTE]
> 🌟 Early first-edition source code is open at [src/](https://github.com/Wcowin/OneClip/tree/main/src). You can build it yourself.  
> The early version used the file system; OneClip now uses SQLite (WAL mode) for storage. You can build from source if you prefer.  
>   
> Windows version is in development. Repo: https://github.com/Wcowin/OneClip-Windows


<div align="center">
  <img src="https://picx.zhimg.com/80/v2-34b000e56d1af7ef61092dcd031dfd9a_1440w.webp?source=2c26e567" alt="OneClip Logo" width="120" height="120">
  <h1>OneClip</h1>
  <p><strong>A simple, professional clipboard manager for macOS</strong></p>
  <p>🚀 Efficient · 🎨 Modern · ⚡️ Smooth · 🔒 Secure</p>
</div>

<p align="center">
  <a href="https://github.com/Wcowin/OneClip/releases"><img src="https://img.shields.io/github/v/release/Wcowin/OneClip?style=for-the-badge&color=3b82f6" alt="Release" /></a>
  <a href="https://github.com/Wcowin/OneClip/releases"><img src="https://img.shields.io/github/downloads/Wcowin/OneClip/total?style=for-the-badge&color=22c55e" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/Homebrew-Available-orange?style=for-the-badge&logo=homebrew&logoColor=white" alt="Homebrew" />
  <img src="https://img.shields.io/badge/macOS-12%2B-0f172a?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 12+" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/Privacy-Local%20Storage-green?style=for-the-badge" alt="Privacy Local Storage" />
  <a href="https://github.com/Wcowin/OneClip/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="MIT License" /></a>
</p>


---

## Overview

OneClip is a **professional clipboard manager** built for macOS. It uses **100% SwiftUI** for smooth animations, native system integration, and low resource usage.

> 💡 **Why OneClip?**
> 
> - ✅ **Pure native**: 100% SwiftUI, no third-party UI frameworks, great performance
> - ✅ **Unique features**: Stack clipboard, drag container, scripting, AI integration, and more
> - ✅ **Privacy-first**: All data stored locally, no uploads
> - ✅ **Actively maintained**: Community-driven, quick response to feedback
> - ✅ **Free tier is powerful**: Full features, no limits, no ads, no data collection

### Core Features

- **Smart history**: Auto-save clipboard history for text, images, files
- **Full format support**: Images, video, audio, documents with metadata preserved
- **Edit text/images**: Edit and delete with undo; pin, favorite, delete
- **Stack clipboard**: `⌘+⇧+C` to open stack; `⌘+V` to paste in order; `⌘+⇧+S` to split by line
- **Quick paste panel**: `⌘+;` to open quick paste panel
- **Drag container**: `⌘+⇧+D` to open drag container for temporary files/images
- **Fast search**: `⌘+F` to search as you type, filters and highlight
- **Menu bar**: Quick access, category search, hover preview, one-click copy/paste
- **Global hotkeys**: `⌘+⇧+V` for main window (customizable)
- **Quick reply**: `⌘+⇧+R` for text/image/file templates, import/export
- **OCR**: Screen or image text recognition, OCR translation
- **Scripting**: JS scripts for automation
- **AI**: Local (Ollama/LMStudio) and cloud AI for summarization and translation
- **Sync**: iCloud/Dropbox and custom sync, backup/import/export
- **Custom storage**: Choose where to store data
- **Flexible options**: Dock icon, background mode, theme; list/card view
- **Modern UI**: macOS design, vibrancy and dark mode
- **Easy install**: Homebrew one-line install (Sparkle auto-update)
- **Finder enhancement**: Finder ⌘+X cut, ⌘+V paste to move files (free in OneClip)

![img1.png](https://cdn.nodeimage.com/i/eYSz3X0E6J8JZl3wGXF3KecrbHCFhz2O.webp)  
![img2.png](https://s1.imagehub.cc/images/2026/01/12/a26a96c52c6a0629979cffe671bf8d27.png)
![img3.png](https://i.imgant.com/v2/Zn6arLh.png)
![img4.png](https://s1.imagehub.cc/images/2026/02/06/9e116bd44476ce5d599f9d5a022fc3ce.png)



## Download & Install

### Requirements

- **macOS 12.0** or later
- **Apple Silicon & Intel** supported

### 📦 Install

**Option 1: GitHub Releases (recommended)**

1. Go to [Releases](https://github.com/Wcowin/OneClip/releases) and download the latest build
2. Drag `OneClip.app` into `Applications`
3. If you see "from an unidentified developer", see below

**Option 2: Direct download**

- [123 Pan (网盘)](https://www.123912.com/s/bXcDVv-HauG3)

**Option 3: Homebrew**

```bash
brew install --cask Wcowin/oneclip/oneclip
```

If you get errors, uninstall and reinstall:

```bash
brew uninstall --cask oneclip
```

---

#### 🔓 First launch: "Unidentified developer" or quarantine

![Permission example](https://s1.imagehub.cc/images/2025/09/29/4548190e0b2466dca56c3590ed15f880.png)  

**Method 1: Terminal (recommended)**

```bash
sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
```  

![终端执行示例](https://s1.imagehub.cc/images/2025/09/15/25681c4221ff1bf29ee7c511e28e2654.png)

**Method 2: System Settings**

1. Open **System Settings** → **Privacy & Security**
2. Find the OneClip message
3. Click **Open Anyway**

![System Settings example](https://s1.imagehub.cc/images/2025/09/29/3ac62762dc125b32cba708eca3ba2144.png)


**Method 3: Helper tool**

- Use [macOS Helper](https://pan.quark.cn/s/f2302b6789b0) to fix in one click

> 💡 **Still having issues?**
> - Tutorial: https://mp.weixin.qq.com/s/qjSx09tqNq1KfVug2WtQFg
> - Contact: vip@oneclip.cloud



## 🎬 Demos

> **Video tutorials**
> - Bilibili: https://space.bilibili.com/1407028951/lists/5012369?type=series

### Feature overview

#### 1️⃣ Main window – quick history access

- Press `⌘+⇧+V` to open
- List/card view
- Real-time search and filters
- Click to paste into the active app

#### 2️⃣ Stack clipboard – batch copy/paste

- `⌘+⇧+C` to open stack
- Add multiple items to the stack
- `⌘+V` to paste in order (default)
- Great for forms and batch editing

#### 3️⃣ Quick reply – text templates

- `⌘+⇧+R` to open
- Text, image, file templates
- Per-template shortcuts
- Import/export config

#### 4️⃣ Drag container – temporary file storage

- `⌘+⇧+D` to open
- Store files and images temporarily
- Drag out to other apps
- Useful for organizing and batch uploads

#### 5️⃣ Menu bar – minimal quick access

- Click menu bar icon for recent items
- Hover to preview
- Drag support
- Quick paste

#### 6️⃣ Quick paste panel

- `⌘+;` to open
- Paste recent content quickly

## Tech & Architecture

### Stack

- Swift 5.9+
- SwiftUI (100% native)
- SQLite + WAL (persistence)
- Carbon Framework (global hotkeys)
- Accessibility API (permissions)
- Sparkle (auto-update)
- Xcode 15+

### Architecture

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

### Core components

| Component | Role |
|-----------|------|
| **ClipboardManager** | Clipboard monitoring and data |
| **SettingsManager** | User preferences |
| **WindowManager** | Window state and display |
| **HotkeyManager** | Global hotkeys |
| **ClipboardStore** | SQLite (WAL) persistence |
| **AIService** | AI integration |
| **SyncthingManager** | Cloud sync |

### Performance

- **Batched updates**: Fewer view redraws
- **Search debounce**: Delayed search to avoid per-keystroke updates
- **Precomputed indexes**: Fast filtering by type
- **Adaptive monitoring**: Adjusts based on activity
- **Lazy loading**: Load images/files on demand
- **Memory pressure**: Auto-release caches when needed

### Permissions

On first launch, OneClip may request:

1. **Accessibility** (required)
   - System Settings → Privacy & Security → Accessibility
   - Add and enable OneClip

2. **Full Disk Access** (optional, for file operations)
   - System Settings → Privacy & Security → Full Disk Access
   - Add and enable OneClip

## Usage

### Basics

1. **Launch**: Double-click `OneClip.app`; icon appears in menu bar.
2. **Quick access**: `⌘+⇧+V` for main window; click menu bar icon to paste.
3. **Quick reply**: `⌘+⇧+R` to open; click a template to paste.
4. **Manage content**: Copy anything to save to history; search and browse in main window; click to paste.

### Advanced (evolving)

#### Smart categories

- **Built-in**: Text, image, file, link, code, etc.
- **Custom**: Create your own rules
- **Colors**: Different colors per category

#### Search

- **Live search**: Results as you type
- **Highlight**: Matches highlighted
- **History**: (TODO) Saved search history

#### Settings

- **Appearance**: List/card, dark mode, font size
- **Storage**: History limit, auto-cleanup, large file handling
- **Privacy**: Exclude apps, filter sensitive content
- **Hotkeys**: Customize all shortcuts

#### Backup & sync

- **Local backup**: Auto/manual
- **Cloud**: Custom sync (e.g. iCloud, Dropbox)
- **Import/export**: Config and data


## Build from source (early version)

Early-edition source is open; you can build it yourself:

### Quick start

```bash
# Clone
git clone https://github.com/Wcowin/OneClip.git
cd OneClip/src

# Build
chmod +x build.sh
./build.sh

# Run
open dist/OneClip.app
```

### Requirements

- macOS 12.0+
- Xcode 15.0+

See [src/README.md](src/README.md) for details.

> ⚠️ **Note**: The open-source build is the early file-system version (MIT). The current release uses a database and has more features; it is commercial software.

## FAQ

<details>
<summary><b>Hotkeys not working?</b></summary>

**Cause**: Accessibility permission not granted.

**Fix**:
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Find OneClip and enable it
3. Restart OneClip

If it still fails:
- Remove and re-add OneClip in Accessibility
- Check for conflicts with other apps’ shortcuts
- Re-set shortcuts in OneClip settings

</details>

<details>
<summary><b>Can't copy files?</b></summary>

**Cause**: Full Disk Access not granted.

**Fix**:
1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Add and enable OneClip
3. Restart the app

</details>

<details>
<summary><b>App won't open or says damaged?</b></summary>

**Fix**:
1. Confirm macOS 12.0+
2. Remove quarantine:
   ```bash
   sudo xattr -rd com.apple.quarantine /Applications/OneClip.app
   ```
3. See [tutorial](https://mp.weixin.qq.com/s/qjSx09tqNq1KfVug2WtQFg) if needed
4. Or use [macOS Helper](https://pan.quark.cn/s/f2302b6789b0)

</details>

<details>
<summary><b>Menu bar icon missing?</b></summary>

**Possible causes**:
- Too many menu bar icons (macOS hides some)
- App crashed or didn’t start correctly

**Fix**:
1. Restart OneClip
2. Check Activity Monitor for OneClip process
3. Reduce other menu bar icons
4. Re-enable menu bar icon in settings

</details>

<details>
<summary><b>High memory usage?</b></summary>

**Suggestions**:
1. Lower history limit in settings (e.g. 500–1000)
2. Enable auto-cleanup
3. Increase detection interval
4. Exclude apps you don’t need to monitor
5. Manually clear old history from time to time

</details>

<details>
<summary><b>How to use AI?</b></summary>

**Local (Ollama)**:
1. Install [Ollama](https://ollama.ai/)
2. Pull a model (e.g. `ollama pull llama2`)
3. Configure Ollama in OneClip settings

**Cloud AI**:
1. Choose provider in settings
2. Enter API key
3. Set model parameters

</details>

<details>
<summary><b>How to get a license?</b></summary>

**Purchase**:
- https://oneclip.cloud/purchase/lifetime
- Discount code: `OneClip2026` (¥5 off)

**Activate**:
1. OneClip Settings → Activate
2. Enter license key
3. Click Activate

**Trial**:
- 7-day full-feature trial
- Basic features remain after trial

</details>


## Roadmap

### ✅ Done

- [x] Core clipboard management
- [x] Global hotkeys
- [x] Text/image/file support
- [x] Stack clipboard
- [x] Quick reply
- [x] Drag container
- [x] AI integration
- [x] Sparkle auto-update
- [x] More AI providers
- [x] Custom sync
- [x] Quick paste panel
- [x] Cloud sync
- [x] UI/UX improvements
- [x] Scripting
- [x] Password protection

### 🚧 In progress

- [ ] Ongoing performance and feature polish
- [ ] Better multi-language support

### 📋 Planned

- [ ] Plugin system
- [ ] Team/collaboration
- [ ] iOS / iPadOS / Windows clients

💡 Suggestions? [GitHub Discussions](https://github.com/Wcowin/OneClip/discussions)

## About the author

<div align="center">
  <img src="https://s1.imagehub.cc/images/2025/07/25/27c0e105ea7efbed5d046d3a8c303e9d.jpeg" alt="Wcowin" width="80" height="80" style="border-radius: 50%;">
  <h3>Wcowin</h3>
  <p>
    <a href="https://wcowin.work/blog/Mac/sunhuai/"> Blog</a> |
    <a href="https://github.com/Wcowin"> GitHub</a> |
    <a href="mailto:vip@oneclip.cloud"> Email</a>
  </p>
</div>

## Feedback & support

If you have issues or ideas:

| Channel | Link | Note |
|---------|------|------|
| 📧 **Email** | [vip@oneclip.cloud](mailto:vip@oneclip.cloud) | Any questions welcome |
| 👥 **QQ** | [1060157293](https://qm.qq.com/q/xiImGHVMcM) | User group |

![IMG_8205.jpeg](https://s2.loli.net/2025/11/08/ogDwexfyWG9142Y.jpg)

### Support the project

If OneClip helps you:

- 🌟 Star on GitHub
- 🔄 Share with others
- 📝 Write a review
- 💰 Purchase a license
- 🐛 Report bugs or suggest improvements

## Acknowledgments

- [SwiftUI](https://developer.apple.com/tutorials/swiftui) – Apple’s UI framework
- [Sparkle](https://sparkle-project.org/) – macOS auto-update
- [Syncthing](https://syncthing.net/) – File sync
- [Ollama](https://ollama.ai/) – Local AI

Thanks to all users for support and feedback! 🎉

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Wcowin/OneClip&type=date&legend=top-left)](https://www.star-history.com/#Wcowin/OneClip&type=date&legend=top-left)

---

<div align="center">
  <p><strong>OneClip — A simple, professional clipboard manager for macOS</strong></p>
  <p>Make the complex simple, and the simple elegant</p>
  <p>Made with ❤️ by <a href="https://github.com/Wcowin">Wcowin</a></p>
  <p>© 2026 Wcowin. All rights reserved.</p>
</div>
