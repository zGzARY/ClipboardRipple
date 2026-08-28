# Clipboard Ripple — 带 Dock 动效的 macOS 剪贴板管理器

[English](README.md) | [简体中文](README.zh-CN.md)

一款原生、本地优先的 macOS 剪贴板历史工具，带有类似 macOS Dock 的顺滑放大动效。

![Clipboard Ripple 的 Dock 式卡片放大时间线](docs/screenshots/clipboard-ripple-timeline.png)

## 亮点

- **Dock 式动效：** 鼠标经过时间线时，当前卡片与相邻卡片会顺滑放大、抬起并让出空间。
- **快速找回：** 按内容、来源应用或类型搜索。
- **操作简单：** 单击选择，双击粘贴，也可以全程使用键盘。
- **Pinboards：** 固定常用内容，随时取用。
- **原生轻量：** 只使用 SwiftUI、AppKit、SwiftData 与系统框架。

## 更多界面

<p>
  <img src="docs/screenshots/clipboard-ripple-search.png" alt="Clipboard Ripple 剪贴板历史搜索" width="62%">
  <img src="docs/screenshots/clipboard-ripple-settings.png" alt="Clipboard Ripple 隐私设置" width="30%">
</p>

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
