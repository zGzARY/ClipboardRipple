import AppKit
import Foundation
import SwiftData

enum ClipboardContentKind: String, Codable {
    case text
    case richText
    case link
    case image
    case file
    case color
    case unknown

    var displayName: String {
        switch self {
        case .text: "文本"
        case .richText: "富文本"
        case .link: "链接"
        case .image: "图片"
        case .file: "文件"
        case .color: "颜色"
        case .unknown: "内容"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        case .unknown: "square.on.square"
        }
    }
}

struct ClipboardRepresentation: Codable, Equatable {
    let type: String
    let data: Data
}

struct ClipboardPayloadItem: Codable, Equatable {
    let representations: [ClipboardRepresentation]

    func representation(for rawType: String) -> ClipboardRepresentation? {
        representations.first { $0.type == rawType }
    }
}

struct ClipboardPayload: Codable, Equatable {
    let items: [ClipboardPayloadItem]

    func encoded() throws -> Data {
        try PropertyListEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> ClipboardPayload {
        try PropertyListDecoder().decode(ClipboardPayload.self, from: data)
    }
}

struct CapturedClipboardContent {
    let payload: ClipboardPayload
    let kind: ClipboardContentKind
    let title: String
    let searchableText: String
    let thumbnailData: Data?
    let fingerprint: String
}

@Model
final class ClipboardRecord {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var title: String
    var kindRawValue: String
    var searchableText: String
    var fingerprint: String
    var sourceBundleIdentifier: String?
    var sourceApplicationName: String?
    @Attribute(.externalStorage) var payloadData: Data
    @Attribute(.externalStorage) var thumbnailData: Data?
    var pinboardIDsData: Data

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        title: String,
        kind: ClipboardContentKind,
        searchableText: String,
        fingerprint: String,
        sourceBundleIdentifier: String?,
        sourceApplicationName: String?,
        payloadData: Data,
        thumbnailData: Data?,
        pinboardIDs: [UUID] = []
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.title = title
        self.kindRawValue = kind.rawValue
        self.searchableText = searchableText
        self.fingerprint = fingerprint
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
        self.payloadData = payloadData
        self.thumbnailData = thumbnailData
        self.pinboardIDsData = (try? JSONEncoder().encode(pinboardIDs)) ?? Data()
    }

    var kind: ClipboardContentKind {
        ClipboardContentKind(rawValue: kindRawValue) ?? .unknown
    }

    var payload: ClipboardPayload? {
        try? ClipboardPayload.decoded(from: payloadData)
    }

    var pinboardIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: pinboardIDsData)) ?? [] }
        set { pinboardIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var isPinned: Bool { !pinboardIDs.isEmpty }
}

@Model
final class PinboardRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

extension NSImage {
    func clipboardRipplePNGData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
