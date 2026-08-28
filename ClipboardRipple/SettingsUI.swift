import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var loginItemService: LoginItemService
    let directPasteService: DirectPasteService

    @State private var accessibilityTrusted = false
    @State private var showsClearConfirmation = false
    @State private var operationError: String?

    var body: some View {
        let strings = state.strings
        Form {
            Section(strings.text("settings.general")) {
                Picker(strings.text("settings.language"), selection: $state.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.selectionLabel).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $state.retentionDays, in: 1 ... 30) {
                    LabeledContent(strings.text("settings.history_retention")) {
                        Text(strings.format("settings.days", state.retentionDays))
                    }
                }

                Picker(strings.text("settings.shortcut"), selection: $state.shortcutDefinition) {
                    ForEach(GlobalShortcutDefinition.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }

                Toggle(strings.text("settings.launch_at_login"), isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: setLaunchAtLogin
                ))

                Toggle(strings.text("settings.show_shortcut_hints"), isOn: $state.showsShortcutHints)
            }

            Section(strings.text("settings.paste_behavior")) {
                Picker(strings.text("settings.when_selecting"), selection: $state.pasteBehavior) {
                    ForEach(PasteBehavior.allCases) { behavior in
                        Text(behavior.displayName(using: strings)).tag(behavior)
                    }
                }

                if state.pasteBehavior == .copyToClipboard {
                    Label(strings.text("settings.no_accessibility_required"), systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text(strings.text("settings.copy_mode_description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Label(
                            accessibilityTrusted
                                ? strings.text("settings.accessibility_enabled")
                                : strings.text("settings.accessibility_required"),
                            systemImage: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield"
                        )
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                        Spacer()
                        Button(
                            accessibilityTrusted
                                ? strings.text("settings.recheck")
                                : strings.text("settings.open_permission_prompt")
                        ) {
                            directPasteService.requestAccessibilityPermission()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                accessibilityTrusted = directPasteService.isAccessibilityTrusted
                            }
                        }
                    }
                    Text(strings.text("settings.accessibility_description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(strings.text("settings.privacy_exclusions")) {
                if state.excludedBundleIdentifiers.isEmpty {
                    Text(strings.text("settings.no_excluded_apps"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.excludedBundleIdentifiers, id: \.self) { identifier in
                        HStack {
                            Text(identifier)
                                .textSelection(.enabled)
                            Spacer()
                            Button(role: .destructive) {
                                state.removeExcludedApplication(bundleIdentifier: identifier)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button(strings.text("settings.choose_excluded_app")) {
                    chooseExcludedApplication()
                }
            }

            Section(strings.text("settings.local_data")) {
                Button(strings.text("settings.clear_unpinned"), role: .destructive) {
                    showsClearConfirmation = true
                }
                Text(strings.text("settings.local_data_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = operationError ?? state.notice {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(4)
        .frame(width: 570, height: 520)
        .environment(\.locale, state.appLanguage.locale)
        .onAppear {
            loginItemService.refresh()
            accessibilityTrusted = directPasteService.isAccessibilityTrusted
        }
        .alert(strings.text("settings.clear_title"), isPresented: $showsClearConfirmation) {
            Button(strings.text("pinboard.cancel"), role: .cancel) {}
            Button(strings.text("settings.clear"), role: .destructive) {
                state.clearUnpinnedHistory()
            }
        } message: {
            Text(strings.text("settings.clear_message"))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            operationError = nil
        } catch {
            loginItemService.refresh()
            operationError = state.strings.format("error.login_item_failed", error.localizedDescription)
        }
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.title = state.strings.text("settings.exclusion_panel_title")
        panel.prompt = state.strings.text("settings.exclude")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
            else { return }
            state.addExcludedApplication(bundleIdentifier: bundleIdentifier)
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let state: AppState
    private let window: NSWindow

    init(
        state: AppState,
        loginItemService: LoginItemService,
        directPasteService: DirectPasteService
    ) {
        self.state = state
        let controller = NSHostingController(
            rootView: SettingsView(
                state: state,
                loginItemService: loginItemService,
                directPasteService: directPasteService
            )
        )
        window = NSWindow(contentViewController: controller)
        window.title = state.strings.text("settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 570, height: 520))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func updateLanguage() {
        window.title = state.strings.text("settings.title")
    }
}
