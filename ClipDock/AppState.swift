import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    private enum DefaultsKey {
        static let retentionDays = "retentionDays"
        static let excludedBundleIdentifiers = "excludedBundleIdentifiers"
        static let shortcutDefinition = "shortcutDefinition"
        static let pasteBehavior = "pasteBehavior"
        static let showsShortcutHints = "showsShortcutHints"
        static let clipboardClassificationVersion = "clipboardClassificationVersion"
        static let currentClipboardClassificationVersion = 1
    }

    @Published private(set) var records: [ClipboardRecord] = []
    @Published private(set) var pinboards: [PinboardRecord] = []
    @Published var searchText = "" {
        didSet { selectedIndex = 0 }
    }
    @Published var selectedPinboardID: UUID? {
        didSet { selectedIndex = 0 }
    }
    @Published var isCreatingPinboard = false
    @Published var selectedIndex = 0
    @Published var isPaused = false
    @Published var notice: String?
    @Published var searchFocusGeneration = 0
    @Published private(set) var selectionRevealGeneration = 0
    @Published var retentionDays: Int {
        didSet {
            let clamped = min(max(retentionDays, 1), 30)
            if retentionDays != clamped {
                retentionDays = clamped
                return
            }
            defaults.set(retentionDays, forKey: DefaultsKey.retentionDays)
            try? store.cleanup(retentionDays: retentionDays)
            refresh()
        }
    }
    @Published var excludedBundleIdentifiers: [String] {
        didSet {
            excludedBundleIdentifiers = Array(Set(excludedBundleIdentifiers)).sorted()
            defaults.set(excludedBundleIdentifiers, forKey: DefaultsKey.excludedBundleIdentifiers)
            onPrivacyRulesChanged?(Set(excludedBundleIdentifiers))
        }
    }
    @Published var shortcutDefinition: GlobalShortcutDefinition {
        didSet {
            defaults.set(shortcutDefinition.rawValue, forKey: DefaultsKey.shortcutDefinition)
            onShortcutChanged?(shortcutDefinition)
        }
    }
    @Published var pasteBehavior: PasteBehavior {
        didSet {
            defaults.set(pasteBehavior.rawValue, forKey: DefaultsKey.pasteBehavior)
        }
    }
    @Published var showsShortcutHints: Bool {
        didSet {
            defaults.set(showsShortcutHints, forKey: DefaultsKey.showsShortcutHints)
        }
    }

    var onPasteRequested: ((ClipboardRecord, Bool) -> Void)?
    var onAutomaticPasteRequested: ((ClipboardRecord, Bool) -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onPrivacyRulesChanged: ((Set<String>) -> Void)?
    var onShortcutChanged: ((GlobalShortcutDefinition) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    private let store: HistoryStore
    private let defaults: UserDefaults

    init(store: HistoryStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let storedDays = defaults.integer(forKey: DefaultsKey.retentionDays)
        retentionDays = storedDays == 0 ? 1 : min(max(storedDays, 1), 30)
        excludedBundleIdentifiers = defaults.stringArray(
            forKey: DefaultsKey.excludedBundleIdentifiers
        ) ?? []
        let shortcutRawValue = defaults.string(forKey: DefaultsKey.shortcutDefinition)
        shortcutDefinition = GlobalShortcutDefinition(rawValue: shortcutRawValue ?? "") ?? .shiftCommandV
        let pasteBehaviorRawValue = defaults.string(forKey: DefaultsKey.pasteBehavior)
        pasteBehavior = PasteBehavior(rawValue: pasteBehaviorRawValue ?? "") ?? .copyToClipboard
        showsShortcutHints = defaults.object(forKey: DefaultsKey.showsShortcutHints) == nil ||
            defaults.bool(forKey: DefaultsKey.showsShortcutHints)

        try? store.cleanup(retentionDays: retentionDays)
        try? store.compactSearchableText()
        if defaults.integer(forKey: DefaultsKey.clipboardClassificationVersion) <
            DefaultsKey.currentClipboardClassificationVersion,
           (try? store.reclassifyLegacyLinks()) != nil {
            defaults.set(
                DefaultsKey.currentClipboardClassificationVersion,
                forKey: DefaultsKey.clipboardClassificationVersion
            )
        }
        if store.fetchPinboards().isEmpty {
            try? store.createPinboard(name: "收藏", colorHex: "FFB020")
        }
        refresh()
    }

    var filteredRecords: [ClipboardRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedPinboardID != nil || !query.isEmpty else { return records }
        return records.filter { record in
            let boardMatches = selectedPinboardID.map { record.pinboardIDs.contains($0) } ?? true
            guard boardMatches else { return false }
            guard !query.isEmpty else { return true }
            return record.title.localizedCaseInsensitiveContains(query) ||
                record.searchableText.localizedCaseInsensitiveContains(query) ||
                (record.sourceApplicationName?.localizedCaseInsensitiveContains(query) ?? false) ||
                record.kind.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedRecord: ClipboardRecord? {
        let results = filteredRecords
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    func refresh() {
        records = store.fetchRecords()
        pinboards = store.fetchPinboards()
        selectedIndex = min(selectedIndex, max(filteredRecords.count - 1, 0))
    }

    func receive(_ captured: CapturedClipboardContent, from application: NSRunningApplication?) {
        do {
            _ = try store.upsert(captured, sourceApplication: application)
            notice = nil
            refresh()
        } catch {
            notice = "保存失败：\(error.localizedDescription)"
        }
    }

    func moveSelection(by delta: Int) {
        let count = filteredRecords.count
        guard count > 0 else { selectedIndex = 0; return }
        let nextIndex = min(max(selectedIndex + delta, 0), count - 1)
        guard nextIndex != selectedIndex else { return }
        selectedIndex = nextIndex
        selectionRevealGeneration &+= 1
    }

    func select(index: Int) {
        guard filteredRecords.indices.contains(index) else { return }
        selectedIndex = index
    }

    func pasteSelected(asPlainText: Bool = false) {
        guard let selectedRecord else { return }
        onPasteRequested?(selectedRecord, asPlainText)
    }

    func paste(index: Int, asPlainText: Bool = false) {
        select(index: index)
        pasteSelected(asPlainText: asPlainText)
    }

    func automaticallyPaste(index: Int, asPlainText: Bool = false) {
        select(index: index)
        guard let selectedRecord else { return }
        onAutomaticPasteRequested?(selectedRecord, asPlainText)
    }

    func deleteSelected() {
        guard let selectedRecord else { return }
        do {
            try store.delete(selectedRecord)
            refresh()
        } catch {
            notice = "删除失败：\(error.localizedDescription)"
        }
    }

    func createPinboard(name: String, colorHex: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        do {
            try store.createPinboard(name: cleanName, colorHex: colorHex)
            refresh()
        } catch {
            notice = "无法创建 Pinboard：\(error.localizedDescription)"
        }
    }

    func deletePinboard(_ pinboard: PinboardRecord) {
        do {
            if selectedPinboardID == pinboard.id { selectedPinboardID = nil }
            try store.deletePinboard(pinboard)
            refresh()
        } catch {
            notice = "无法删除 Pinboard：\(error.localizedDescription)"
        }
    }

    func togglePin(_ record: ClipboardRecord, pinboardID: UUID) {
        var ids = record.pinboardIDs
        if ids.contains(pinboardID) {
            ids.removeAll { $0 == pinboardID }
        } else {
            ids.append(pinboardID)
        }
        record.pinboardIDs = ids
        do {
            try store.save()
            refresh()
        } catch {
            notice = "固定失败：\(error.localizedDescription)"
        }
    }

    func clearUnpinnedHistory() {
        do {
            try store.clearUnpinnedHistory()
            refresh()
        } catch {
            notice = "清理失败：\(error.localizedDescription)"
        }
    }

    func togglePaused() {
        isPaused.toggle()
        onPauseChanged?(isPaused)
    }

    func requestSearchFocus() {
        searchFocusGeneration += 1
    }

    func addExcludedApplication(bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              !excludedBundleIdentifiers.contains(bundleIdentifier)
        else { return }
        excludedBundleIdentifiers.append(bundleIdentifier)
    }

    func removeExcludedApplication(bundleIdentifier: String) {
        excludedBundleIdentifiers.removeAll { $0 == bundleIdentifier }
    }
}
