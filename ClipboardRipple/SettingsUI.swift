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
        Form {
            Section("常规") {
                Stepper(value: $state.retentionDays, in: 1 ... 30) {
                    LabeledContent("历史保留") {
                        Text("\(state.retentionDays) 天")
                    }
                }

                Picker("显示快捷键", selection: $state.shortcutDefinition) {
                    ForEach(GlobalShortcutDefinition.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }

                Toggle("登录时启动", isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: setLaunchAtLogin
                ))

                Toggle("显示底部按键提示", isOn: $state.showsShortcutHints)
            }

            Section("粘贴行为") {
                Picker("选择项目时", selection: $state.pasteBehavior) {
                    ForEach(PasteBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }

                if state.pasteBehavior == .copyToClipboard {
                    Label("此模式无需辅助功能授权", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Clipboard Ripple 会正常记录、搜索并恢复剪贴内容。选择项目后，请在目标应用按 ⌘V。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Label(
                            accessibilityTrusted ? "自动粘贴权限已启用" : "自动粘贴需要辅助功能权限",
                            systemImage: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield"
                        )
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                        Spacer()
                        Button(accessibilityTrusted ? "重新检查" : "打开授权提示") {
                            directPasteService.requestAccessibilityPermission()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                accessibilityTrusted = directPasteService.isAccessibilityTrusted
                            }
                        }
                    }
                    Text("该权限仅用于向前台应用发送一次 ⌘V；不授权不影响其他功能。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("隐私排除") {
                if state.excludedBundleIdentifiers.isEmpty {
                    Text("尚未排除应用。带有 confidential 或 transient 标记的内容仍会自动忽略。")
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
                Button("选择要排除的应用…") {
                    chooseExcludedApplication()
                }
            }

            Section("本地数据") {
                Button("清除未固定的历史…", role: .destructive) {
                    showsClearConfirmation = true
                }
                Text("Pinboards 中固定的项目不会被删除。Clipboard Ripple 不上传剪贴内容。")
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
        .onAppear {
            loginItemService.refresh()
            accessibilityTrusted = directPasteService.isAccessibilityTrusted
        }
        .alert("清除剪贴历史？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                state.clearUnpinnedHistory()
            }
        } message: {
            Text("这会删除所有未固定的本地历史记录，无法撤销。")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            operationError = nil
        } catch {
            loginItemService.refresh()
            operationError = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择不保存剪贴内容的应用"
        panel.prompt = "排除"
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
    private let window: NSWindow

    init(
        state: AppState,
        loginItemService: LoginItemService,
        directPasteService: DirectPasteService
    ) {
        let controller = NSHostingController(
            rootView: SettingsView(
                state: state,
                loginItemService: loginItemService,
                directPasteService: directPasteService
            )
        )
        window = NSWindow(contentViewController: controller)
        window.title = "Clipboard Ripple 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 570, height: 520))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
