# Clipboard Ripple Personal Team signing

The previously installed `/Applications/ClipDock.app` is a local ad-hoc Release build. After the rename, the Release product belongs at `/Applications/Clipboard Ripple.app`. A stable Apple Development signature requires a Personal Team identity in Xcode.

## Sign with a Personal Team

1. Open the compatible Xcode and sign in under **Xcode → Settings → Accounts**.
2. Open `ClipboardRipple.xcodeproj`.
3. Select the **ClipboardRipple** target and open **Signing & Capabilities**.
4. Enable **Automatically manage signing** and select the Personal Team.
5. If Xcode reports that `com.clipboardripple.local` is unavailable, choose a unique reverse-DNS bundle identifier and keep it stable thereafter.
6. Build the **Release** configuration for **My Mac**.
7. Quit the running ClipDock or Clipboard Ripple, remove the obsolete `/Applications/ClipDock.app`, place the signed product at `/Applications/Clipboard Ripple.app`, and launch it once.
8. In **System Settings → Privacy & Security → Accessibility**, remove any obsolete ClipDock entry and enable the newly signed `/Applications/Clipboard Ripple.app` entry.

## Verification

```sh
security find-identity -v -p codesigning
codesign --verify --deep --strict --verbose=2 "/Applications/Clipboard Ripple.app"
codesign -dv --verbose=4 "/Applications/Clipboard Ripple.app" 2>&1
```

The final `codesign` output must show a non-empty `TeamIdentifier` and must not show `Signature=adhoc`.
