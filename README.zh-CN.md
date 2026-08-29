# Clipboard Ripple — 带 Dock 动效的 macOS 剪贴板管理器

[English](README.md) | [简体中文](README.zh-CN.md)

一款小巧、完全免费、本地优先的 macOS 剪贴板历史工具，带有类似 macOS Dock 的顺滑放大动效。

[![Clipboard Ripple 的 macOS 界面](docs/marketing/reddit/01-hero.png)](docs/marketing/reddit/clipboard-ripple-motion-preview.mov)

<p align="center">
  <a href="docs/marketing/reddit/clipboard-ripple-motion-preview.mov">▶ 观看 14 秒、60 fps 动效预览</a>
</p>

## 亮点

- **Dock 式动效：** 鼠标经过时间线时，当前卡片与相邻卡片会顺滑放大、抬起并让出空间。
- **快速找回：** 按内容、来源应用或类型搜索。
- **操作简单：** 单击选择，双击粘贴，也可以全程使用键盘。
- **Pinboards：** 固定常用内容，随时取用。
- **完全免费且小巧：** 无订阅、广告、分析统计或追踪；下载约 3.4 MB。
- **中英双语：** 完整界面支持 English 与简体中文。
- **原生轻量：** 只使用 SwiftUI、AppKit、SwiftData 与系统框架。

## 极简设计

<p>
  <img src="docs/marketing/reddit/02-free-and-tiny.png" alt="Clipboard Ripple 完全免费，下载约 3.4 MB" width="49%">
  <img src="docs/marketing/reddit/03-simple-by-design.png" alt="Clipboard Ripple 极简、快速、原生并支持中英双语" width="49%">
</p>

<p align="center">
  <img src="docs/marketing/reddit/04-why-github.png" alt="为什么 Clipboard Ripple 通过 GitHub 而不是 App Store 分发" width="72%">
</p>

## 下载

[下载 Clipboard Ripple v0.2.0](https://github.com/zGzARY/ClipboardRipple/releases/tag/v0.2.0)。当前 GitHub 版本未经公证；如果 macOS 首次启动时阻止打开，请右键点击应用并选择 **打开**。

## 使用

1. 复制文本、链接、图片、文件或颜色。
2. 按 `⇧⌘V` 打开 Clipboard Ripple。
3. 选择卡片后按 `Return` 复制回来，或双击直接粘贴。

## 隐私

剪贴板历史只保存在你的 Mac 上。Clipboard Ripple 没有网络访问、分析统计或云同步；你可以排除指定应用，自动粘贴也可以完全关闭。

## 构建

Clipboard Ripple 需要 macOS 14 或更高版本。

```sh
xcodebuild -project ClipboardRipple.xcodeproj -scheme ClipboardRipple -configuration Debug build
xcodebuild -project ClipboardRipple.xcodeproj -scheme ClipboardRipple -configuration Debug test
```

Release 签名与本地安装说明见 [SIGNING.md](SIGNING.md)。

## 许可证

Clipboard Ripple 使用 [GNU General Public License v3.0](LICENSE)（`GPL-3.0-only`）。
