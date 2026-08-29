# Clipboard Ripple — Animated Clipboard Manager for macOS

[English](README.md) | [简体中文](README.zh-CN.md)

A tiny, completely free, local-first clipboard manager for macOS with Dock-style magnification.

[![Clipboard Ripple on macOS](docs/marketing/reddit/01-hero.png)](docs/marketing/reddit/clipboard-ripple-motion-preview.mov)

<p align="center">
  <a href="docs/marketing/reddit/clipboard-ripple-motion-preview.mov">▶ Watch the 14-second, 60 fps motion preview</a>
</p>

## Highlights

- **Dock-style motion:** hover across the timeline and nearby cards smoothly grow, lift, and make room.
- **Fast recall:** search by content, source app, or type.
- **Simple actions:** click to select, double-click to paste, or use the keyboard.
- **Pinboards:** keep important clips close.
- **Completely free and tiny:** no subscription, ads, analytics, or tracking; the download is about 3.4 MB.
- **Bilingual:** the full interface supports English and Simplified Chinese.
- **Native and lightweight:** built with SwiftUI, AppKit, SwiftData, and system frameworks only.

## Simple by design

<p>
  <img src="docs/marketing/reddit/02-free-and-tiny.png" alt="Clipboard Ripple is completely free and about 3.4 MB" width="49%">
  <img src="docs/marketing/reddit/03-simple-by-design.png" alt="Clipboard Ripple is simple, fast, native, and bilingual" width="49%">
</p>

<p align="center">
  <img src="docs/marketing/reddit/04-why-github.png" alt="Why Clipboard Ripple is distributed on GitHub instead of the App Store" width="72%">
</p>

## Download

[Download Clipboard Ripple v0.2.0](https://github.com/zGzARY/ClipboardRipple/releases/tag/v0.2.0). The current GitHub build is not notarized; if macOS blocks the first launch, right-click the app and choose **Open**.

## Use

1. Copy text, links, images, files, or colors.
2. Press `⇧⌘V` to open Clipboard Ripple.
3. Choose a card, then press `Return` to copy it back or double-click to paste.

## Privacy

Clipboard history stays on your Mac. Clipboard Ripple has no network access, analytics, or cloud sync. You can exclude selected apps, and automatic paste is optional.

## Build

Clipboard Ripple requires macOS 14 or later.

```sh
xcodebuild -project ClipboardRipple.xcodeproj -scheme ClipboardRipple -configuration Debug build
xcodebuild -project ClipboardRipple.xcodeproj -scheme ClipboardRipple -configuration Debug test
```

For Release signing and local installation, see [SIGNING.md](SIGNING.md).

## License

Clipboard Ripple is licensed under the [GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).
