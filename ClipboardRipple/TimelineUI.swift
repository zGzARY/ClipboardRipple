@preconcurrency import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

enum CoarseRelativeTime {
    static func text(
        for date: Date,
        relativeTo now: Date = Date(),
        using strings: AppStrings
    ) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return strings.text("time.just_now")
        case ..<180: return strings.text("time.one_minute_ago")
        case ..<300: return strings.text("time.three_minutes_ago")
        case ..<600: return strings.text("time.five_minutes_ago")
        case ..<1_200: return strings.text("time.ten_minutes_ago")
        case ..<1_800: return strings.text("time.twenty_minutes_ago")
        case ..<3_600: return strings.text("time.thirty_minutes_ago")
        case ..<86_400: return strings.format("time.hours_ago", Int(seconds / 3_600))
        default:
            let days = Int(seconds / 86_400)
            return days == 1
                ? strings.text("time.one_day_ago")
                : strings.format("time.days_ago", days)
        }
    }
}

struct ClipboardRippleTransform: Equatable {
    let scale: CGFloat
    let lift: CGFloat
    let horizontalOffset: CGFloat
    let influence: CGFloat

    static let identity = ClipboardRippleTransform(
        scale: 1,
        lift: 0,
        horizontalOffset: 0,
        influence: 0
    )
}

struct ClipboardRippleEdgeTransform: Equatable {
    let scale: CGFloat
    let retreat: CGFloat
    let horizontalOffset: CGFloat
    let opacity: CGFloat
    let depth: CGFloat

    static let identity = ClipboardRippleEdgeTransform(
        scale: 1,
        retreat: 0,
        horizontalOffset: 0,
        opacity: 1,
        depth: 1
    )
}

enum ClipboardRippleMotion {
    static let cardWidth: CGFloat = 228
    static let cardHeight: CGFloat = 232
    static let cardSpacing: CGFloat = 14
    static let horizontalInset: CGFloat = 28
    static let cardTopInset: CGFloat = 48
    static let cardBottomInset: CGFloat = 10
    static let panelInset: CGFloat = 18
    static let surfaceTopInset: CGFloat = 54
    static let cardTimelineHeight = cardTopInset + cardHeight + cardBottomInset

    static func panelHeight(showsShortcutHints: Bool) -> CGFloat {
        showsShortcutHints ? 380 : 350
    }

    private static let influenceRadius: CGFloat = 600
    private static let maximumScale: CGFloat = 1.15
    private static let maximumLift: CGFloat = 12
    private static let maximumPush: CGFloat = 28
    private static let edgeTransitionWidth: CGFloat = 112
    private static let minimumEdgeScale: CGFloat = 0.86
    private static let maximumEdgeRetreat: CGFloat = 14
    private static let maximumEdgePush: CGFloat = 12

    static func centerX(for index: Int) -> CGFloat {
        horizontalInset + cardWidth / 2 + CGFloat(index) * (cardWidth + cardSpacing)
    }

    static func transform(for index: Int, pointerX: CGFloat?) -> ClipboardRippleTransform {
        transform(cardCenterX: centerX(for: index), pointerX: pointerX)
    }

    static func transform(
        cardCenterX: CGFloat,
        pointerX: CGFloat?
    ) -> ClipboardRippleTransform {
        guard let pointerX else { return .identity }
        let delta = cardCenterX - pointerX
        let distance = abs(delta)
        guard distance < influenceRadius else { return .identity }

        let progress = distance / influenceRadius
        let influence = (cos(.pi * progress) + 1) / 2
        let direction: CGFloat = delta == 0 ? 0 : (delta < 0 ? -1 : 1)
        let push = direction * maximumPush * sin(.pi * progress) * influence
        return ClipboardRippleTransform(
            scale: 1 + (maximumScale - 1) * influence,
            lift: maximumLift * influence,
            horizontalOffset: push,
            influence: influence
        )
    }

    static func edgeTransform(
        for index: Int,
        contentOffsetX: CGFloat,
        viewportWidth: CGFloat,
        reduceMotion: Bool
    ) -> ClipboardRippleEdgeTransform {
        let viewportCenter = centerX(for: index) - contentOffsetX
        return edgeTransform(
            viewportCenter: viewportCenter,
            viewportWidth: viewportWidth,
            reduceMotion: reduceMotion
        )
    }

    static func edgeTransform(
        viewportCenter: CGFloat,
        viewportWidth: CGFloat,
        reduceMotion: Bool
    ) -> ClipboardRippleEdgeTransform {
        guard viewportWidth > 0 else { return .identity }
        let distanceToNearestEdge = min(viewportCenter, viewportWidth - viewportCenter)
        let rawVisibility = min(max(distanceToNearestEdge / edgeTransitionWidth, 0), 1)
        let visibility = rawVisibility * rawVisibility * (3 - 2 * rawVisibility)
        let edgeDirection: CGFloat = viewportCenter < viewportWidth / 2 ? -1 : 1

        guard !reduceMotion else {
            return ClipboardRippleEdgeTransform(
                scale: 1,
                retreat: 0,
                horizontalOffset: 0,
                opacity: visibility,
                depth: visibility
            )
        }

        let retreatProgress = 1 - visibility
        return ClipboardRippleEdgeTransform(
            scale: minimumEdgeScale + (1 - minimumEdgeScale) * visibility,
            retreat: maximumEdgeRetreat * retreatProgress,
            horizontalOffset: edgeDirection * maximumEdgePush * retreatProgress,
            opacity: visibility,
            depth: visibility
        )
    }
}

private enum ClipboardRippleCoordinateSpace {
    static let cardTimeline = "ClipboardRipple.cardTimeline"
}

@MainActor
final class ClipboardRipplePointerState: ObservableObject {
    @Published private(set) var panelX: CGFloat?

    func update(screenX: CGFloat, panelFrame: NSRect) {
        let nextX = min(max(screenX - panelFrame.minX, 0), panelFrame.width)
        guard nextX != panelX else { return }
        panelX = nextX
    }

    func clear() {
        panelX = nil
    }
}

@MainActor
private enum CardImageCache {
    private static let sourceIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 512 * 1_024
        return cache
    }()

    private static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 6
        cache.totalCostLimit = 4 * 1_024 * 1_024
        return cache
    }()

    static func sourceIcon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        let key = bundleIdentifier as NSString
        if let cached = sourceIcons.object(forKey: key) { return cached }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }

        let source = NSWorkspace.shared.icon(forFile: applicationURL.path)
        let icon = NSImage(size: NSSize(width: 64, height: 64))
        icon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: 64, height: 64),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1
        )
        icon.unlockFocus()
        sourceIcons.setObject(icon, forKey: key, cost: 64 * 64 * 4)
        return icon
    }

    static func thumbnail(for recordID: UUID, data: Data) -> NSImage? {
        let key = recordID.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        let cost = max(1, Int(image.size.width * image.size.height * 4))
        thumbnails.setObject(image, forKey: key, cost: cost)
        return image
    }
}

struct TimelineView: View {
    @ObservedObject var state: AppState
    @ObservedObject var pointerState: ClipboardRipplePointerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            dockSurface

            VStack(spacing: 9) {
                cardTimeline
                dockControls
                if shouldShowFooter {
                    footer
                }
            }
            .padding(.horizontal, ClipboardRippleMotion.panelInset)
            .padding(.bottom, 12)

            if state.isCreatingPinboard {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { state.isCreatingPinboard = false }
                NewPinboardView(strings: state.strings) { name, color in
                    state.createPinboard(name: name, colorHex: color)
                    state.isCreatingPinboard = false
                } onCancel: {
                    state.isCreatingPinboard = false
                }
                .environment(\.locale, state.appLanguage.locale)
                .background(
                    Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
            }
        }
        .onChange(of: state.searchFocusGeneration) { _, _ in
            searchIsFocused = true
        }
        .environment(\.locale, state.appLanguage.locale)
    }

    private var dockSurface: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                Color.white.opacity(0.055)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(reduceTransparency ? 0.16 : 0.38), lineWidth: 1)
        }
        .padding(.top, ClipboardRippleMotion.surfaceTopInset)
    }

    private var dockControls: some View {
        let strings = state.strings
        return HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(strings.text("timeline.search_placeholder"), text: $state.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
            }
            .padding(.horizontal, 12)
            .frame(width: 270, height: 34)
            .background(.black.opacity(0.10), in: Capsule())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BoardChip(
                        title: strings.text("timeline.clipboard"),
                        color: .secondary,
                        symbol: "clock.arrow.circlepath",
                        selected: state.selectedPinboardID == nil
                    ) {
                        state.selectedPinboardID = nil
                    }

                    ForEach(state.pinboards) { board in
                        BoardChip(
                            title: state.pinboardDisplayName(board),
                            color: Color(hex: board.colorHex),
                            symbol: "pin.fill",
                            selected: state.selectedPinboardID == board.id
                        ) {
                            state.selectedPinboardID = board.id
                        }
                        .contextMenu {
                            Button(
                                strings.format("action.delete_named", state.pinboardDisplayName(board)),
                                role: .destructive
                            ) {
                                state.deletePinboard(board)
                            }
                        }
                    }
                }
            }

            Button {
                state.isCreatingPinboard = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.14), in: Circle())

            Button {
                state.onSettingsRequested?()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.14), in: Circle())
        }
    }

    private var cardTimeline: some View {
        let records = state.filteredRecords
        return GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: ClipboardRippleMotion.cardSpacing) {
                        if records.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                timelineCard(
                                    record: record,
                                    index: index,
                                    viewportWidth: viewport.size.width
                                )
                            }
                        }
                    }
                    .padding(.horizontal, ClipboardRippleMotion.horizontalInset)
                    .padding(.top, ClipboardRippleMotion.cardTopInset)
                    .padding(.bottom, ClipboardRippleMotion.cardBottomInset)
                }
                .scrollClipDisabled()
                .onChange(of: state.selectionRevealGeneration) { _, _ in
                    guard records.indices.contains(state.selectedIndex) else { return }
                    proxy.scrollTo(records[state.selectedIndex].id, anchor: .center)
                }
            }
        }
        .coordinateSpace(name: ClipboardRippleCoordinateSpace.cardTimeline)
        .frame(height: ClipboardRippleMotion.cardTimelineHeight)
        .compositingGroup()
        .mask(cardEdgeFeatherMask)
    }

    private func timelineCard(
        record: ClipboardRecord,
        index: Int,
        viewportWidth: CGFloat
    ) -> some View {
        GeometryReader { card in
            let viewportCenter = card.frame(
                in: .named(ClipboardRippleCoordinateSpace.cardTimeline)
            ).midX
            let transform = ClipboardRippleMotion.transform(
                cardCenterX: viewportCenter,
                pointerX: reduceMotion ? nil : dockViewportPointerX
            )
            let edgeTransform = ClipboardRippleMotion.edgeTransform(
                viewportCenter: viewportCenter,
                viewportWidth: viewportWidth,
                reduceMotion: reduceMotion
            )

            ClipboardCard(
                record: record,
                selected: index == state.selectedIndex,
                strings: state.strings
            )
                .scaleEffect(transform.scale * edgeTransform.scale, anchor: .bottom)
                .offset(
                    x: transform.horizontalOffset + edgeTransform.horizontalOffset,
                    y: -transform.lift + edgeTransform.retreat
                )
                .opacity(edgeTransform.opacity)
                .zIndex(transform.influence + edgeTransform.depth)
                .allowsHitTesting(edgeTransform.opacity > 0.12)
                .onTapGesture {
                    state.select(index: index)
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        state.automaticallyPaste(
                            index: index,
                            asPlainText: NSEvent.modifierFlags.contains(.shift)
                        )
                    }
                )
                .contextMenu {
                    Button(state.pasteBehavior.actionName(using: state.strings)) {
                        state.select(index: index)
                        state.pasteSelected()
                    }
                    Button(
                        state.strings.format(
                            "action.as_plain_text",
                            state.pasteBehavior.actionName(using: state.strings)
                        )
                    ) {
                        state.select(index: index)
                        state.pasteSelected(asPlainText: true)
                    }
                    if !state.pinboards.isEmpty {
                        Menu(state.strings.text("action.pin_to_pinboard")) {
                            ForEach(state.pinboards) { board in
                                Button {
                                    state.togglePin(record, pinboardID: board.id)
                                } label: {
                                    let pinned = record.pinboardIDs.contains(board.id)
                                    Label(
                                        state.pinboardDisplayName(board),
                                        systemImage: pinned ? "checkmark" : "pin"
                                    )
                                }
                            }
                        }
                    }
                    Divider()
                    Button(state.strings.text("action.delete"), role: .destructive) {
                        state.select(index: index)
                        state.deleteSelected()
                    }
                }
        }
        .frame(
            width: ClipboardRippleMotion.cardWidth,
            height: ClipboardRippleMotion.cardHeight
        )
        .id(record.id)
    }

    private var cardEdgeFeatherMask: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let featherStop = min(0.08, 24 / width)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: featherStop),
                    .init(color: .black, location: 1 - featherStop),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var dockViewportPointerX: CGFloat? {
        pointerState.panelX.map { $0 - ClipboardRippleMotion.panelInset }
    }

    private var emptyState: some View {
        let strings = state.strings
        return VStack(spacing: 9) {
            Image(systemName: state.searchText.isEmpty ? "square.on.square.dashed" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
            Text(
                state.searchText.isEmpty
                    ? strings.text("timeline.empty_title")
                    : strings.text("timeline.no_results_title")
            )
                .font(.headline)
            Text(
                state.searchText.isEmpty
                    ? strings.text("timeline.empty_subtitle")
                    : strings.text("timeline.no_results_subtitle")
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 190)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var footer: some View {
        HStack {
            if let notice = state.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if state.isPaused {
                Label(state.strings.text("timeline.capture_paused"), systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label(state.strings.text("timeline.saving_locally"), systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.showsShortcutHints {
                Text(footerShortcutText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var shouldShowFooter: Bool {
        state.showsShortcutHints || state.notice != nil || state.isPaused
    }

    private var footerShortcutText: String {
        let action = state.pasteBehavior.actionName(using: state.strings)
        return state.strings.format("timeline.shortcut_hint", action, action)
    }
}

private struct BoardChip: View {
    let title: String
    let color: Color
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(selected ? color.opacity(0.22) : .white.opacity(0.08), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(selected ? color.opacity(0.55) : .clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct ClipboardCard: View {
    let record: ClipboardRecord
    let selected: Bool
    let strings: AppStrings

    private var accent: Color {
        switch record.kind {
        case .text: Color(hex: "1697F6")
        case .richText: Color(hex: "F5B700")
        case .link: Color(hex: "2CCB67")
        case .image: Color(hex: "FF4655")
        case .file: Color(hex: "7A8496")
        case .color: Color(hex: "EC4F93")
        case .unknown: Color(hex: "8B63E6")
        }
    }

    private var paperColor: Color {
        switch record.kind {
        case .text: Color(hex: "FFF6C9")
        case .richText: Color(hex: "FFF1B8")
        case .link: Color(hex: "F3FFF5")
        case .image: .white
        case .file: Color(hex: "F7F8FA")
        case .color: Color(hex: "FFF0F7")
        case .unknown: Color(hex: "F5F1FF")
        }
    }

    private var sourceIcon: NSImage? {
        CardImageCache.sourceIcon(for: record.sourceBundleIdentifier)
    }

    private var detailLabel: String {
        switch record.kind {
        case .text, .richText, .link:
            strings.format("timeline.characters", record.searchableText.count)
        case .image:
            record.searchableText
        case .file:
            strings.text("content.file")
        case .color:
            strings.text("content.color")
        case .unknown:
            record.kind.displayName(using: strings)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.kind.displayName(using: strings))
                        .font(.system(size: 15, weight: .bold))
                    Text(CoarseRelativeTime.text(for: record.capturedAt, using: strings))
                        .font(.caption2)
                        .opacity(0.82)
                }
                .foregroundStyle(.white)
                Spacer()
                Group {
                    if let sourceIcon {
                        Image(nsImage: sourceIcon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: record.kind.symbolName)
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 32, height: 32)
                .padding(4)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .help(record.sourceApplicationName ?? strings.text("timeline.unknown_source"))
                .accessibilityLabel(record.sourceApplicationName ?? strings.text("timeline.unknown_source"))
            }
            .padding(.horizontal, 12)
            .frame(width: ClipboardRippleMotion.cardWidth, height: 56)
            .background(
                LinearGradient(
                    colors: [accent, accent.opacity(0.84)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .zIndex(1)

            Group {
                if let thumbnailData = record.thumbnailData,
                   let image = CardImageCache.thumbnail(for: record.id, data: thumbnailData) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            width: ClipboardRippleMotion.cardWidth,
                            height: 148
                        )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.displayTitle(using: strings))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black.opacity(0.84))
                            .lineLimit(2)
                        if record.searchableText != record.title {
                            Text(String(record.searchableText.prefix(600)))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.black.opacity(0.72))
                                .lineLimit(5)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
            }
            .frame(width: ClipboardRippleMotion.cardWidth, height: 148)
            .background(paperColor)
            .clipped()

            HStack(spacing: 6) {
                Text(record.sourceApplicationName ?? strings.text("timeline.unknown_source"))
                    .lineLimit(1)
                Spacer()
                if record.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                }
                Text(detailLabel)
            }
            .font(.caption2)
            .foregroundStyle(.black.opacity(0.55))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(paperColor)
        }
        .frame(width: ClipboardRippleMotion.cardWidth, height: ClipboardRippleMotion.cardHeight)
        .background(paperColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .black.opacity(0.06), lineWidth: selected ? 3 : 1)
        }
        .background(alignment: .bottom) {
            Capsule()
                .fill(.black.opacity(0.16))
                .frame(width: ClipboardRippleMotion.cardWidth * 0.78, height: 10)
                .blur(radius: 7)
                .offset(y: 7)
        }
    }
}

private struct NewPinboardView: View {
    let strings: AppStrings
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var selectedColor = "FFB020"
    @FocusState private var nameIsFocused: Bool

    private let colors = ["FFB020", "FF5A67", "31C66A", "2F95FF", "906BFF", "EC58B5"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(strings.text("pinboard.new"))
                .font(.title2.weight(.semibold))
            TextField(strings.text("pinboard.name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameIsFocused)
            HStack {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        selectedColor = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 27, height: 27)
                            .overlay {
                                Circle().strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button(strings.text("pinboard.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(strings.text("pinboard.create")) {
                    onCreate(name, selectedColor)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
        .onAppear { nameIsFocused = true }
    }
}

final class TimelinePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TimelinePanelController: NSObject, NSWindowDelegate {
    let panel: TimelinePanel
    private(set) var targetApplication: NSRunningApplication?

    private let state: AppState
    private let pointerState = ClipboardRipplePointerState()
    private var keyMonitor: Any?
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private var isHiding = false
    private var animationGeneration = 0

    init(state: AppState) {
        self.state = state
        panel = TimelinePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 380),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 720, height: 340)
        panel.maxSize = NSSize(width: 1_600, height: 540)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.contentViewController = NSHostingController(
            rootView: TimelineView(state: state, pointerState: pointerState)
        )
    }

    var isVisible: Bool { panel.isVisible && !isHiding }

    func show() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApplication = frontmost
        }
        state.refresh()
        let finalFrame = frameOnActiveScreen()
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)

        animationGeneration += 1
        let generation = animationGeneration
        isHiding = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? finalFrame : hiddenFrame(below: finalFrame), display: false)
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        installPointerMonitors()

        guard !reduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.82, 0.20, 1)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.panel.setFrame(finalFrame, display: true)
                self.panel.alphaValue = 1
            }
        }
    }

    func hide() {
        state.isCreatingPinboard = false
        removeKeyMonitor()
        removePointerMonitors()
        guard panel.isVisible, !isHiding else { return }

        animationGeneration += 1
        let generation = animationGeneration
        let finalFrame = panel.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            panel.orderOut(nil)
            return
        }

        isHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.40, 0, 0.80, 0.20)
            panel.animator().setFrame(hiddenFrame(below: finalFrame), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.setFrame(finalFrame, display: false)
                self.panel.alphaValue = 1
                self.isHiding = false
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidResize(_ notification: Notification) {
        updateDockPointer()
    }

    private func frameOnActiveScreen() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = activeScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let width = min(max(visibleFrame.width - 32, 720), 1_420)
        let height = min(
            ClipboardRippleMotion.panelHeight(showsShortcutHints: state.showsShortcutHints),
            visibleFrame.height - 28
        )
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + 14,
            width: width,
            height: height
        )
    }

    private func hiddenFrame(below visibleFrame: NSRect) -> NSRect {
        let midpoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let screenBottom = NSScreen.screens.first { NSMouseInRect(midpoint, $0.frame, false) }?.frame.minY
            ?? NSScreen.main?.frame.minY
            ?? visibleFrame.minY
        return NSRect(
            x: visibleFrame.minX,
            y: screenBottom - visibleFrame.height - 8,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func installPointerMonitors() {
        guard localPointerMonitor == nil, globalPointerMonitor == nil else {
            updateDockPointer()
            return
        }
        let events: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { @MainActor [weak self] event in
            self?.updateDockPointer()
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { @MainActor [weak self] _ in
            self?.updateDockPointer()
        }
        updateDockPointer()
    }

    private func removePointerMonitors() {
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
        }
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
        }
        localPointerMonitor = nil
        globalPointerMonitor = nil
        pointerState.clear()
    }

    private func updateDockPointer() {
        pointerState.update(screenX: NSEvent.mouseLocation.x, panelFrame: panel.frame)
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        guard !state.isCreatingPinboard else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            state.requestSearchFocus()
            return nil
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "," {
            state.onSettingsRequested?()
            return nil
        }

        if modifiers.contains(.command), let index = quickPasteIndex(for: event.keyCode) {
            state.paste(index: index, asPlainText: modifiers.contains(.shift))
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_LeftArrow:
            state.moveSelection(by: -1)
            return nil
        case kVK_RightArrow:
            state.moveSelection(by: 1)
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            state.pasteSelected(asPlainText: modifiers.contains(.shift))
            return nil
        case kVK_Escape:
            if state.searchText.isEmpty {
                hide()
            } else {
                state.searchText = ""
                panel.makeFirstResponder(nil)
            }
            return nil
        default:
            break
        }

        if panel.firstResponder is NSTextView {
            return event
        }

        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            state.deleteSelected()
            return nil
        default:
            return event
        }
    }

    private func quickPasteIndex(for keyCode: UInt16) -> Int? {
        let codes = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
            kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
            kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
        return codes.firstIndex(of: Int(keyCode))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
