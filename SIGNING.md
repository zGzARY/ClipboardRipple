# ClipDock Personal Team signing

The currently installed `/Applications/ClipDock.app` is a local ad-hoc Release build. It runs locally, but it has no Team ID. A stable Apple Development signature requires a Personal Team identity in Xcode.

## Current host state (2026-08-28)

- macOS: 27.0 (26A5421a)
- Installed Xcode command-line tools: Xcode 16.4 (16F6)
- Xcode GUI launch result: `kLSIncompatibleApplicationVersionErr`
- Available code-signing identities: `0 valid identities found`

Install an Xcode release compatible with macOS 27 before continuing. Do not remove the working command-line Xcode until the replacement has opened successfully.

## Sign with a Personal Team

1. Open the compatible Xcode and sign in under **Xcode → Settings → Accounts**.
2. Open `ClipDock.xcodeproj`.
3. Select the **ClipDock** target and open **Signing & Capabilities**.
4. Enable **Automatically manage signing** and select the Personal Team.
5. If Xcode reports that `com.clipdock.local` is unavailable, choose a unique reverse-DNS bundle identifier and keep it stable thereafter.
6. Build the **Release** configuration for **My Mac**.
7. Quit the running ClipDock, replace `/Applications/ClipDock.app` with the signed Release product, and launch it once from `/Applications`.
8. In **System Settings → Privacy & Security → Accessibility**, remove any obsolete ClipDock entry and enable the newly signed `/Applications/ClipDock.app` entry.

## Verification

```sh
security find-identity -v -p codesigning
codesign --verify --deep --strict --verbose=2 /Applications/ClipDock.app
codesign -dv --verbose=4 /Applications/ClipDock.app 2>&1
```

The final `codesign` output must show a non-empty `TeamIdentifier` and must not show `Signature=adhoc`.
