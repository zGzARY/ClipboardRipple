# ClipDock

[English](README.md) | [简体中文](README.zh-CN.md)

A local-first clipboard history app for macOS, with the familiar motion of the macOS Dock.

![ClipDock timeline with Dock-style card magnification](docs/screenshots/clipdock-timeline.png)

## Highlights

- **Dock-style motion:** hover across the timeline and nearby cards smoothly grow, lift, and make room.
- **Fast recall:** search by content, source app, or type.
- **Simple actions:** click to select, double-click to paste, or use the keyboard.
- **Pinboards:** keep important clips close.
- **Native and lightweight:** built with SwiftUI, AppKit, SwiftData, and system frameworks only.

## More views

<p>
  <img src="docs/screenshots/clipdock-search.png" alt="ClipDock search" width="62%">
  <img src="docs/screenshots/clipdock-settings.png" alt="ClipDock settings" width="30%">
</p>

## Use

1. Copy text, links, images, files, or colors.
2. Press `⇧⌘V` to open ClipDock.
3. Choose a card, then press `Return` to copy it back or double-click to paste.

## Privacy

Clipboard history stays on your Mac. ClipDock has no network access, analytics, or cloud sync. You can exclude selected apps, and automatic paste is optional.

## Build

ClipDock requires macOS 14 or later.

```sh
xcodebuild -project ClipDock.xcodeproj -scheme ClipDock -configuration Debug build
xcodebuild -project ClipDock.xcodeproj -scheme ClipDock -configuration Debug test
```

For Release signing and local installation, see [SIGNING.md](SIGNING.md).

## License

ClipDock is licensed under the [GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).
