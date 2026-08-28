import AppKit
import SwiftUI

@main
struct ClipDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let didShowWelcomePanelKey = "didShowWelcomePanelV1"
    private static let legacyBundleIdentifier = "com.clipdeck.local"
    private static let defaultsMigrationKey = "didMigrateClipDeckDefaultsV1"

    private var state: AppState!
    private var monitor: PasteboardMonitor!
    private var shortcutService: GlobalShortcutService!
    private var directPasteService: DirectPasteService!
    private var loginItemService: LoginItemService!
    private var panelController: TimelinePanelController!
    private var settingsController: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var pauseMenuItem: NSMenuItem!
    private var launchMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard !isRunningUnitTests else { return }
        Self.migrateLegacyDefaults(
            into: .standard,
            legacyDomain: UserDefaults.standard.persistentDomain(
                forName: Self.legacyBundleIdentifier
            )
        )

        do {
            let store = try HistoryStore()
            state = AppState(store: store)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "ClipDock 无法启动"
            alert.informativeText = "无法打开本地数据库：\(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        monitor = PasteboardMonitor()
        shortcutService = GlobalShortcutService()
        directPasteService = DirectPasteService()
        loginItemService = LoginItemService()
        panelController = TimelinePanelController(state: state)
        settingsController = SettingsWindowController(
            state: state,
            loginItemService: loginItemService,
            directPasteService: directPasteService
        )

        connectServices()
        configureStatusItem()
        registerShortcut(state.shortcutDefinition)
        monitor.excludedBundleIdentifiers = Set(state.excludedBundleIdentifiers)
        monitor.start()

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.didShowWelcomePanelKey) {
            defaults.set(true, forKey: Self.didShowWelcomePanelKey)
            DispatchQueue.main.async { [weak self] in
                self?.panelController.show()
            }
        }
    }

    private var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func migrateLegacyDefaults(
        into current: UserDefaults,
        legacyDomain: [String: Any]?
    ) {
        guard !current.bool(forKey: defaultsMigrationKey) else { return }
        for (key, value) in legacyDomain ?? [:] where current.object(forKey: key) == nil {
            current.set(value, forKey: key)
        }
        current.set(true, forKey: defaultsMigrationKey)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        shortcutService?.unregister()
    }

    private func connectServices() {
        monitor.onCapture = { [weak self] captured, application in
            self?.state.receive(captured, from: application)
        }
        monitor.onSkippedContent = { [weak self] message in
            self?.state.notice = message
        }
        shortcutService.onPressed = { [weak self] in
            self?.toggleTimeline()
        }
        state.onPasteRequested = { [weak self] record, plainText in
            self?.paste(record: record, asPlainText: plainText)
        }
        state.onAutomaticPasteRequested = { [weak self] record, plainText in
            self?.paste(record: record, asPlainText: plainText, behavior: .automaticPaste)
        }
        state.onSettingsRequested = { [weak self] in
            self?.showSettings()
        }
        state.onPrivacyRulesChanged = { [weak self] bundleIdentifiers in
            self?.monitor.excludedBundleIdentifiers = bundleIdentifiers
        }
        state.onShortcutChanged = { [weak self] definition in
            self?.registerShortcut(definition)
        }
        state.onPauseChanged = { [weak self] paused in
            self?.monitor.isPaused = paused
            self?.pauseMenuItem?.state = paused ? .on : .off
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.on.square",
                accessibilityDescription: "ClipDock"
            )
            button.toolTip = "ClipDock"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "显示 ClipDock", action: #selector(showTimeline), keyEquivalent: "")
        pauseMenuItem = menu.addItem(withTitle: "暂停捕获", action: #selector(togglePause), keyEquivalent: "")
        launchMenuItem = menu.addItem(withTitle: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettingsAction), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 ClipDock", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseMenuItem.state = state.isPaused ? .on : .off
        loginItemService.refresh()
        launchMenuItem.state = loginItemService.isEnabled ? .on : .off
    }

    @objc private func showTimeline() {
        panelController.show()
    }

    private func toggleTimeline() {
        panelController.isVisible ? panelController.hide() : panelController.show()
    }

    @objc private func togglePause() {
        state.togglePaused()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try loginItemService.setEnabled(!loginItemService.isEnabled)
            state.notice = nil
        } catch {
            state.notice = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    @objc private func showSettingsAction() {
        showSettings()
    }

    private func showSettings() {
        panelController.hide()
        settingsController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func registerShortcut(_ definition: GlobalShortcutDefinition) {
        do {
            try shortcutService.register(definition)
            state.notice = nil
        } catch {
            state.notice = error.localizedDescription
        }
    }

    private func paste(
        record: ClipboardRecord,
        asPlainText: Bool,
        behavior: PasteBehavior? = nil
    ) {
        guard let payload = record.payload else {
            state.notice = "该记录已损坏，无法恢复"
            return
        }
        let target = panelController.targetApplication
        panelController.hide()
        directPasteService.paste(
            payload: payload,
            asPlainText: asPlainText,
            behavior: behavior ?? state.pasteBehavior,
            targetApplication: target,
            monitor: monitor
        ) { [weak self] result in
            switch result {
            case .pasted:
                self?.state.notice = nil
            case .copied:
                self?.state.notice = "已复制到剪贴板；请在目标应用按 ⌘V"
            case .accessibilityPermissionRequired:
                self?.state.notice = "已复制到剪贴板；自动粘贴需在设置中授权辅助功能"
            case let .failed(message):
                self?.state.notice = message
            }
        }
    }
}
