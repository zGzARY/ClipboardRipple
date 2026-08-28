import AppKit
import Carbon
import UniformTypeIdentifiers
import XCTest
@testable import ClipboardRipple

@MainActor
final class ClipboardRippleTests: XCTestCase {
    func testLegacyDefaultsMigrateWithoutOverwritingClipboardRippleValues() throws {
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(30, forKey: "retentionDays")

        AppDelegate.migrateLegacyDefaults(
            into: defaults,
            legacyDomains: [
                [
                    "retentionDays": 1,
                    "shortcutDefinition": "controlV",
                ],
                [
                    "shortcutDefinition": "commandV",
                    "showsShortcutHints": false,
                ],
            ]
        )

        XCTAssertEqual(defaults.integer(forKey: "retentionDays"), 30)
        XCTAssertEqual(defaults.string(forKey: "shortcutDefinition"), "controlV")
        XCTAssertFalse(defaults.bool(forKey: "showsShortcutHints"))
        XCTAssertTrue(defaults.bool(forKey: "didMigrateClipboardRippleDefaultsV1"))
    }

    func testLegacyStoreFilesMigrateAtomicallyAndKeepRollbackCopy() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ClipboardRippleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let legacyURL = baseURL.appendingPathComponent("ClipDeck", isDirectory: true)
        let legacySupport = legacyURL.appendingPathComponent(".ClipDeck_SUPPORT", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        try FileManager.default.createDirectory(
            at: legacySupport,
            withIntermediateDirectories: true
        )
        let marker = Data("history".utf8)
        for name in ["ClipDeck.store", "ClipDeck.store-wal", "ClipDeck.store-shm"] {
            try marker.write(to: legacyURL.appendingPathComponent(name))
        }
        try marker.write(to: legacySupport.appendingPathComponent("image"))

        try HistoryStore.migrateLegacyStoreIfNeeded(in: baseURL)

        let migratedURL = baseURL.appendingPathComponent("ClipboardRipple", isDirectory: true)
        XCTAssertEqual(
            try Data(contentsOf: migratedURL.appendingPathComponent("ClipboardRipple.store")),
            marker
        )
        XCTAssertEqual(
            try Data(contentsOf: migratedURL.appendingPathComponent(".ClipboardRipple_SUPPORT/image")),
            marker
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testClipDockStoreMigratesToClipboardRippleBeforeClipDeckFallback() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ClipboardRippleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let clipDockURL = baseURL.appendingPathComponent("ClipDock", isDirectory: true)
        let clipDeckURL = baseURL.appendingPathComponent("ClipDeck", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        try FileManager.default.createDirectory(at: clipDockURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: clipDeckURL, withIntermediateDirectories: true)
        try Data("clipdock".utf8).write(to: clipDockURL.appendingPathComponent("ClipDock.store"))
        try Data("clipdeck".utf8).write(to: clipDeckURL.appendingPathComponent("ClipDeck.store"))

        try HistoryStore.migrateLegacyStoreIfNeeded(in: baseURL)

        let migratedStore = baseURL
            .appendingPathComponent("ClipboardRipple", isDirectory: true)
            .appendingPathComponent("ClipboardRipple.store")
        XCTAssertEqual(try Data(contentsOf: migratedStore), Data("clipdock".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clipDockURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clipDeckURL.path))
    }

    func testPlainTextCaptureAndRoundTrip() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Clipboard Ripple 测试文本", forType: .string))

        let captured = try ClipboardPayload.capture(from: pasteboard)

        XCTAssertEqual(captured.kind, .text)
        XCTAssertEqual(captured.title, "Clipboard Ripple 测试文本")
        XCTAssertEqual(captured.payload.preferredPlainText, "Clipboard Ripple 测试文本")
        XCTAssertEqual(
            try ClipboardPayload.decoded(from: captured.payload.encoded()),
            captured.payload
        )
    }

    func testLargeTextKeepsFullPayloadButLimitsSearchPreview() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let text = String(repeating: "轻", count: 25_000)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))

        let captured = try ClipboardPayload.capture(from: pasteboard)

        XCTAssertEqual(captured.payload.preferredPlainText, text)
        XCTAssertEqual(captured.searchableText.count, 20_000)
    }

    func testMultilineEndpointTextIsRichTextNotLink() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let text = "Endpoint: NOT_EVALUABLE_SEENHCC_GSE156625_MONLY_INTERFACE.\nFrozen interface mass was below the required threshold."
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))

        let captured = try ClipboardPayload.capture(from: pasteboard)

        XCTAssertEqual(captured.kind, .richText)
        XCTAssertEqual(captured.title, "Endpoint: NOT_EVALUABLE_SEENHCC_GSE156625_MONLY_INTERFACE.")
    }

    func testStandaloneURLRemainsLink() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("https://example.com/path", forType: .string))

        XCTAssertEqual(try ClipboardPayload.capture(from: pasteboard).kind, .link)
    }

    func testLegacySearchTextIsCompactedWithoutChangingPayload() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let text = String(repeating: "旧", count: 25_000)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
        let record = try store.upsert(ClipboardPayload.capture(from: pasteboard), sourceApplication: nil)
        record.searchableText = text
        try store.save()

        try store.compactSearchableText()

        XCTAssertEqual(record.searchableText.count, 20_000)
        XCTAssertEqual(record.payload?.preferredPlainText, text)
    }

    func testImagePreviewIsLimitedToRetinaCardSize() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 1_000, height: 800))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let imageData = try XCTUnwrap(image.tiffRepresentation)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(imageData, forType: .tiff))

        let captured = try ClipboardPayload.capture(from: pasteboard)
        let previewData = try XCTUnwrap(captured.thumbnailData)
        let preview = try XCTUnwrap(NSImage(data: previewData))

        XCTAssertLessThanOrEqual(preview.size.width, 456)
        XCTAssertLessThanOrEqual(preview.size.height, 296)
    }

    func testJPEGImageCaptureAndClipboardRoundTrip() throws {
        let sourcePasteboard = NSPasteboard.withUniqueName()
        let destinationPasteboard = NSPasteboard.withUniqueName()
        defer {
            sourcePasteboard.releaseGlobally()
            destinationPasteboard.releaseGlobally()
        }

        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let jpegData = try XCTUnwrap(
            bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        )
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        sourcePasteboard.clearContents()
        XCTAssertTrue(sourcePasteboard.setData(jpegData, forType: jpegType))

        let captured = try ClipboardPayload.capture(from: sourcePasteboard)
        XCTAssertEqual(captured.kind, .image)
        let monitor = PasteboardMonitor(pasteboard: destinationPasteboard)
        let service = DirectPasteService(pasteboard: destinationPasteboard)
        var result: DirectPasteResult?

        service.paste(
            payload: captured.payload,
            asPlainText: false,
            behavior: .copyToClipboard,
            targetApplication: nil,
            monitor: monitor
        ) { result = $0 }

        XCTAssertEqual(result, .copied)
        let restoredData = try XCTUnwrap(destinationPasteboard.data(forType: jpegType))
        XCTAssertNotNil(NSImage(data: restoredData))
    }

    func testFormattedPasteDeclaresHTMLBeforePlainText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let plainData = Data("formatted text".utf8)
        let htmlData = Data("<b>formatted text</b>".utf8)
        let payload = ClipboardPayload(items: [
            ClipboardPayloadItem(representations: [
                ClipboardRepresentation(
                    type: NSPasteboard.PasteboardType.string.rawValue,
                    data: plainData
                ),
                ClipboardRepresentation(
                    type: NSPasteboard.PasteboardType.html.rawValue,
                    data: htmlData
                ),
            ]),
        ])
        let monitor = PasteboardMonitor(pasteboard: pasteboard)
        let service = DirectPasteService(pasteboard: pasteboard)
        var result: DirectPasteResult?

        service.paste(
            payload: payload,
            asPlainText: false,
            behavior: .copyToClipboard,
            targetApplication: nil,
            monitor: monitor
        ) { result = $0 }

        XCTAssertEqual(result, .copied)
        let types = try XCTUnwrap(pasteboard.pasteboardItems?.first?.types)
        XCTAssertLessThan(
            try XCTUnwrap(types.firstIndex(of: .html)),
            try XCTUnwrap(types.firstIndex(of: .string))
        )
        XCTAssertEqual(pasteboard.data(forType: .html), htmlData)
        XCTAssertEqual(pasteboard.data(forType: .string), plainData)
    }

    func testCoarseRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let strings = AppStrings(language: .english)
        let cases: [(TimeInterval, String)] = [
            (10, "just now"),
            (60, "1 min ago"),
            (180, "3 min ago"),
            (300, "5 min ago"),
            (600, "10 min ago"),
            (1_200, "20 min ago"),
            (1_800, "30 min ago"),
            (3_600, "1 h ago"),
            (10_800, "3 h ago"),
            (86_400, "1 day ago"),
            (172_800, "2 days ago")
        ]

        for (age, expected) in cases {
            XCTAssertEqual(
                CoarseRelativeTime.text(
                    for: now.addingTimeInterval(-age),
                    relativeTo: now,
                    using: strings
                ),
                expected
            )
        }
    }

    func testCoarseRelativeTimeUsesSelectedLanguage() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let chinese = AppStrings(language: .simplifiedChinese)

        XCTAssertEqual(
            CoarseRelativeTime.text(
                for: now.addingTimeInterval(-1_200),
                relativeTo: now,
                using: chinese
            ),
            "20 分钟前"
        )
        XCTAssertEqual(
            CoarseRelativeTime.text(
                for: now.addingTimeInterval(-172_800),
                relativeTo: now,
                using: chinese
            ),
            "2 天前"
        )
    }

    func testShortcutHintsControlPanelHeight() {
        XCTAssertEqual(ClipboardRippleMotion.panelHeight(showsShortcutHints: true), 380)
        XCTAssertEqual(ClipboardRippleMotion.panelHeight(showsShortcutHints: false), 350)
        XCTAssertEqual(
            ClipboardRippleMotion.cardTimelineHeight,
            ClipboardRippleMotion.cardTopInset + ClipboardRippleMotion.cardHeight + ClipboardRippleMotion.cardBottomInset
        )
    }

    func testShortcutHintsDefaultOnAndPersistOff() throws {
        let store = try HistoryStore(inMemory: true)
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialState = AppState(store: store, defaults: defaults)
        XCTAssertTrue(initialState.showsShortcutHints)
        initialState.showsShortcutHints = false

        let restoredState = AppState(store: store, defaults: defaults)
        XCTAssertFalse(restoredState.showsShortcutHints)
    }

    func testClipboardRippleMotionIsIdleWithoutPointer() {
        XCTAssertEqual(ClipboardRippleMotion.transform(for: 0, pointerX: nil), .identity)
    }

    func testClipboardRippleMotionPeaksAtHoveredCardCenter() {
        let center = ClipboardRippleMotion.centerX(for: 2)
        let transform = ClipboardRippleMotion.transform(for: 2, pointerX: center)

        XCTAssertEqual(transform.scale, 1.15, accuracy: 0.000_1)
        XCTAssertEqual(transform.lift, 12, accuracy: 0.000_1)
        XCTAssertEqual(transform.horizontalOffset, 0, accuracy: 0.000_1)
        XCTAssertEqual(transform.influence, 1, accuracy: 0.000_1)
    }

    func testClipboardRippleMotionMagnifiesNeighborsSymmetrically() {
        let pointerX = ClipboardRippleMotion.centerX(for: 2)
        let left = ClipboardRippleMotion.transform(for: 1, pointerX: pointerX)
        let right = ClipboardRippleMotion.transform(for: 3, pointerX: pointerX)

        XCTAssertGreaterThan(left.scale, 1)
        XCTAssertLessThan(left.scale, 1.15)
        XCTAssertEqual(left.scale, right.scale, accuracy: 0.000_1)
        XCTAssertEqual(left.lift, right.lift, accuracy: 0.000_1)
        XCTAssertEqual(left.horizontalOffset, -right.horizontalOffset, accuracy: 0.000_1)
        XCTAssertLessThan(left.horizontalOffset, 0)
        XCTAssertGreaterThan(right.horizontalOffset, 0)
    }

    func testClipboardRippleMotionDoesNotAffectDistantCards() {
        let pointerX = ClipboardRippleMotion.centerX(for: 0)
        XCTAssertEqual(ClipboardRippleMotion.transform(for: 3, pointerX: pointerX), .identity)
    }

    func testClipboardRipplePanelPointerTracksScrollOffset() {
        XCTAssertEqual(
            ClipboardRippleMotion.contentPointerX(panelPointerX: 420, contentOffsetX: 180),
            582
        )
        XCTAssertNil(ClipboardRippleMotion.contentPointerX(panelPointerX: nil, contentOffsetX: 180))
    }

    func testClipboardRipplePointerProjectsWholeScreenToPanelEdges() {
        let pointer = ClipboardRipplePointerState()
        let panelFrame = NSRect(x: 200, y: 100, width: 1_000, height: 460)

        pointer.update(screenX: 700, panelFrame: panelFrame)
        XCTAssertEqual(pointer.panelX, 500)
        pointer.update(screenX: 100, panelFrame: panelFrame)
        XCTAssertEqual(pointer.panelX, 0)
        pointer.update(screenX: 1_400, panelFrame: panelFrame)
        XCTAssertEqual(pointer.panelX, 1_000)
        pointer.clear()
        XCTAssertNil(pointer.panelX)
    }

    func testPrivatePasteboardMarkerIsIgnored() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.declareTypes([
            .string,
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        ], owner: nil)
        pasteboard.setString("secret", forType: .string)
        pasteboard.setData(Data([1]), forType: .init("org.nspasteboard.ConcealedType"))

        XCTAssertTrue(
            PrivacyFilter.shouldIgnore(
                pasteboard: pasteboard,
                sourceBundleIdentifier: "example.password-manager",
                excludedBundleIdentifiers: []
            )
        )
    }

    func testExcludedApplicationIsIgnored() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("ordinary text", forType: .string)

        XCTAssertTrue(
            PrivacyFilter.shouldIgnore(
                pasteboard: pasteboard,
                sourceBundleIdentifier: "example.private",
                excludedBundleIdentifiers: ["example.private"]
            )
        )
    }

    func testHistoryDeduplicatesAndRefreshesTimestamp() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("same value", forType: .string)
        let captured = try ClipboardPayload.capture(from: pasteboard)

        let first = try store.upsert(captured, sourceApplication: nil)
        first.capturedAt = Date(timeIntervalSince1970: 10)
        try store.save()
        let second = try store.upsert(captured, sourceApplication: nil)

        XCTAssertEqual(store.fetchRecords().count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertGreaterThan(second.capturedAt, Date(timeIntervalSince1970: 10))
    }

    func testImageCapturesAreKeptAsSeparateHistoryEntries() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 80, height: 50))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff))
        let captured = try ClipboardPayload.capture(from: pasteboard)

        let first = try store.upsert(captured, sourceApplication: .current)
        let second = try store.upsert(captured, sourceApplication: .current)

        XCTAssertEqual(store.fetchRecords().count, 2)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testLegacyFalseLinkRecordIsReclassified() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Endpoint: NOT_EVALUABLE\nFrozen interface mass", forType: .string))
        let record = try store.upsert(
            ClipboardPayload.capture(from: pasteboard),
            sourceApplication: nil
        )
        record.kindRawValue = ClipboardContentKind.link.rawValue
        try store.save()

        XCTAssertEqual(try store.reclassifyLegacyLinks(), 1)
        XCTAssertEqual(record.kind, .richText)
        XCTAssertEqual(try store.reclassifyLegacyLinks(), 0)
    }

    func testSourceApplicationMetadataSupportsIconLookup() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        let sourceApplication = try XCTUnwrap(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.finder"
            ).first
        )
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("source metadata", forType: .string)

        let record = try store.upsert(
            ClipboardPayload.capture(from: pasteboard),
            sourceApplication: sourceApplication
        )

        XCTAssertEqual(record.sourceBundleIdentifier, "com.apple.finder")
        XCTAssertEqual(record.sourceApplicationName, sourceApplication.localizedName)
        let bundleIdentifier = try XCTUnwrap(record.sourceBundleIdentifier)
        let applicationURL = try XCTUnwrap(
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        )
        XCTAssertTrue(NSWorkspace.shared.icon(forFile: applicationURL.path).isValid)
    }

    func testRetentionDeletesOnlyUnpinnedRecords() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("expired", forType: .string)
        let expired = try store.upsert(ClipboardPayload.capture(from: pasteboard), sourceApplication: nil)
        expired.capturedAt = Date(timeIntervalSinceNow: -3 * 86_400)
        try store.save()

        pasteboard.clearContents()
        pasteboard.setString("pinned", forType: .string)
        let pinned = try store.upsert(ClipboardPayload.capture(from: pasteboard), sourceApplication: nil)
        pinned.capturedAt = Date(timeIntervalSinceNow: -3 * 86_400)
        pinned.pinboardIDs = [UUID()]
        try store.save()

        try store.cleanup(retentionDays: 1)

        let remaining = store.fetchRecords()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "pinned")
    }

    func testRetentionClampsThroughAppState() throws {
        let store = try HistoryStore(inMemory: true)
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(store: store, defaults: defaults)

        state.retentionDays = 0
        XCTAssertEqual(state.retentionDays, 1)
        state.retentionDays = 31
        XCTAssertEqual(state.retentionDays, 30)
    }

    func testControlVIsAvailableAsDisplayShortcut() {
        XCTAssertTrue(GlobalShortcutDefinition.allCases.contains(.controlV))
        XCTAssertEqual(GlobalShortcutDefinition.controlV.displayName, "⌃V")
        XCTAssertEqual(GlobalShortcutDefinition.controlV.carbonModifiers, UInt32(controlKey))
    }

    func testPasteBehaviorDefaultsToPermissionFreeCopyMode() throws {
        let store = try HistoryStore(inMemory: true)
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(store: store, defaults: defaults)

        XCTAssertEqual(state.pasteBehavior, .copyToClipboard)
        state.appLanguage = .simplifiedChinese
        XCTAssertEqual(
            state.pasteBehavior.displayName(using: state.strings),
            "复制到剪贴板（无需权限）"
        )
    }

    func testLanguageDefaultsFromSystemAndPersistsUserChoice() throws {
        let store = try HistoryStore(inMemory: true)
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            AppLanguage.resolved(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguage.resolved(defaults: defaults, preferredLanguages: ["fr-FR"]),
            .english
        )

        let state = AppState(store: store, defaults: defaults)
        state.appLanguage = .simplifiedChinese
        let restored = AppState(store: store, defaults: defaults)
        XCTAssertEqual(restored.appLanguage, .simplifiedChinese)
    }

    func testLocalizationTablesHaveMatchingKeys() throws {
        func table(for language: AppLanguage) throws -> [String: String] {
            let url = try XCTUnwrap(
                Bundle.main.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: language.rawValue
                )
            )
            return try XCTUnwrap(
                NSDictionary(contentsOf: url) as? [String: String]
            )
        }

        let english = try table(for: .english)
        let chinese = try table(for: .simplifiedChinese)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        XCTAssertFalse(english.isEmpty)
        XCTAssertFalse(english.contains { $0.key == $0.value })
        XCTAssertFalse(chinese.contains { $0.key == $0.value })
    }

    func testBuiltInPinboardNameSwitchesLanguagesWithoutRenamingUserData() throws {
        let store = try HistoryStore(inMemory: true)
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)

        let state = AppState(store: store, defaults: defaults)
        let builtIn = try XCTUnwrap(state.pinboards.first)
        XCTAssertEqual(state.pinboardDisplayName(builtIn), "Favorites")

        state.appLanguage = .simplifiedChinese
        XCTAssertEqual(state.pinboardDisplayName(builtIn), "收藏")

        state.createPinboard(name: "Research", colorHex: "2F95FF")
        let userBoard = try XCTUnwrap(state.pinboards.first { $0.name == "Research" })
        XCTAssertEqual(state.pinboardDisplayName(userBoard), "Research")
    }

    func testCopyModeRestoresClipboardWithoutAccessibility() throws {
        let sourcePasteboard = NSPasteboard.withUniqueName()
        let destinationPasteboard = NSPasteboard.withUniqueName()
        defer {
            sourcePasteboard.releaseGlobally()
            destinationPasteboard.releaseGlobally()
        }
        sourcePasteboard.clearContents()
        XCTAssertTrue(sourcePasteboard.setString("无需辅助功能", forType: .string))
        let payload = try ClipboardPayload.capture(from: sourcePasteboard).payload
        let monitor = PasteboardMonitor(pasteboard: destinationPasteboard)
        let service = DirectPasteService(pasteboard: destinationPasteboard)
        var result: DirectPasteResult?

        service.paste(
            payload: payload,
            asPlainText: false,
            behavior: .copyToClipboard,
            targetApplication: nil,
            monitor: monitor
        ) { result = $0 }

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(destinationPasteboard.string(forType: .string), "无需辅助功能")
    }

    func testAutomaticPasteRouteSelectsDoubleClickedRecord() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("first", forType: .string)
        let first = try store.upsert(ClipboardPayload.capture(from: pasteboard), sourceApplication: nil)
        first.capturedAt = Date(timeIntervalSinceNow: -2)
        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)
        let second = try store.upsert(ClipboardPayload.capture(from: pasteboard), sourceApplication: nil)
        second.capturedAt = Date(timeIntervalSinceNow: -1)
        try store.save()

        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(store: store, defaults: defaults)
        var requestedTitle: String?
        var requestedPlainText: Bool?
        state.onAutomaticPasteRequested = { record, plainText in
            requestedTitle = record.title
            requestedPlainText = plainText
        }

        state.automaticallyPaste(index: 1, asPlainText: true)

        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.selectionRevealGeneration, 0)
        XCTAssertEqual(requestedTitle, "first")
        XCTAssertEqual(requestedPlainText, true)
    }

    func testOnlyKeyboardSelectionRequestsCardReveal() throws {
        let store = try HistoryStore(inMemory: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        for text in ["first", "second"] {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            _ = try store.upsert(ClipboardPayload.capture(from: pasteboard), sourceApplication: nil)
        }
        let suiteName = "ClipboardRippleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(store: store, defaults: defaults)

        state.select(index: 1)
        XCTAssertEqual(state.selectionRevealGeneration, 0)

        state.moveSelection(by: -1)
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.selectionRevealGeneration, 1)
    }
}
