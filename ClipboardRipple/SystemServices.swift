import AppKit
import ApplicationServices
import Carbon
import Foundation
import ServiceManagement

enum GlobalShortcutDefinition: String, CaseIterable, Identifiable {
    case shiftCommandV
    case optionCommandV
    case controlV
    case controlOptionV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shiftCommandV: "⇧⌘V"
        case .optionCommandV: "⌥⌘V"
        case .controlV: "⌃V"
        case .controlOptionV: "⌃⌥V"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .shiftCommandV: UInt32(cmdKey | shiftKey)
        case .optionCommandV: UInt32(cmdKey | optionKey)
        case .controlV: UInt32(controlKey)
        case .controlOptionV: UInt32(controlKey | optionKey)
        }
    }
}

enum PasteBehavior: String, CaseIterable, Identifiable {
    case copyToClipboard
    case automaticPaste

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copyToClipboard: "复制到剪贴板（无需权限）"
        case .automaticPaste: "自动粘贴到前台应用"
        }
    }

    var actionName: String {
        switch self {
        case .copyToClipboard: "复制"
        case .automaticPaste: "粘贴"
        }
    }
}

private let clipboardRippleHotKeySignature: OSType = 0x4352504C // CRPL

private func clipboardRippleGlobalHotKeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == clipboardRippleHotKeySignature,
          hotKeyID.id == 1
    else { return OSStatus(eventNotHandledErr) }

    let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        service.onPressed?()
    }
    return noErr
}

@MainActor
final class GlobalShortcutService {
    var onPressed: (() -> Void)?

    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?

    func register(_ definition: GlobalShortcutDefinition) throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            clipboardRippleGlobalHotKeyHandler,
            1,
            &eventType,
            pointer,
            &handlerReference
        )
        guard handlerStatus == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(handlerStatus),
                userInfo: [NSLocalizedDescriptionKey: "无法安装全局快捷键处理器"]
            )
        }

        let identifier = EventHotKeyID(signature: clipboardRippleHotKeySignature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            definition.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registerStatus == noErr else {
            unregister()
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(registerStatus),
                userInfo: [NSLocalizedDescriptionKey: "快捷键 \(definition.displayName) 已被其他应用占用"]
            )
        }
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
        }
        hotKeyReference = nil
        handlerReference = nil
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
        }
    }
}

enum DirectPasteResult: Equatable {
    case pasted
    case copied
    case accessibilityPermissionRequired
    case failed(String)
}

@MainActor
final class DirectPasteService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func paste(
        payload: ClipboardPayload,
        asPlainText: Bool,
        behavior: PasteBehavior,
        targetApplication: NSRunningApplication?,
        monitor: PasteboardMonitor,
        completion: @escaping (DirectPasteResult) -> Void
    ) {
        guard write(payload: payload, asPlainText: asPlainText) else {
            completion(.failed("无法恢复剪贴内容"))
            return
        }
        monitor.markOwnWrite()

        guard behavior == .automaticPaste else {
            completion(.copied)
            return
        }

        guard let targetApplication,
              targetApplication.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            completion(.copied)
            return
        }

        guard isAccessibilityTrusted else {
            completion(.accessibilityPermissionRequired)
            return
        }

        targetApplication.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            else {
                completion(.failed("无法生成粘贴按键事件"))
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            completion(.pasted)
        }
    }

    private func write(payload: ClipboardPayload, asPlainText: Bool) -> Bool {
        pasteboard.clearContents()

        if asPlainText {
            guard let text = payload.preferredPlainText else { return false }
            return pasteboard.setString(text, forType: .string)
        }

        let pasteboardItems: [NSPasteboardItem] = payload.items.compactMap { source in
            let item = NSPasteboardItem()
            var wroteRepresentation = false
            for prefersRichFormat in [true, false] {
                for representation in source.representations
                where isRichTextType(representation.type) == prefersRichFormat {
                    let type = NSPasteboard.PasteboardType(representation.type)
                    if item.setData(representation.data, forType: type) {
                        wroteRepresentation = true
                    }
                }
            }
            return wroteRepresentation ? item : nil
        }
        guard !pasteboardItems.isEmpty else { return false }
        return pasteboard.writeObjects(pasteboardItems)
    }

    private func isRichTextType(_ rawType: String) -> Bool {
        rawType == NSPasteboard.PasteboardType.rtf.rawValue ||
            rawType == NSPasteboard.PasteboardType.html.rawValue ||
            rawType == NSPasteboard.PasteboardType.rtfd.rawValue ||
            rawType == "com.apple.flat-rtfd"
    }
}

extension ClipboardPayload {
    var preferredPlainText: String? {
        let preferredTypes = [
            NSPasteboard.PasteboardType.string.rawValue,
            "public.utf8-plain-text",
            "public.utf16-external-plain-text",
            NSPasteboard.PasteboardType.URL.rawValue,
            NSPasteboard.PasteboardType.fileURL.rawValue
        ]
        let values: [String] = items.compactMap { item in
            for type in preferredTypes {
                guard let representation = item.representation(for: type) else { continue }
                if let string = String(data: representation.data, encoding: .utf8) {
                    return string
                }
                if let string = String(data: representation.data, encoding: .utf16) {
                    return string
                }
            }
            return nil
        }
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }
}

@MainActor
final class LoginItemService: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status

    var isEnabled: Bool { status == .enabled }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        refresh()
    }
}
