import Foundation

private let _manifestDecoder = JSONDecoder()
private let _manifestEncoder = JSONEncoder()

enum ArchiveKind: String, Codable, Sendable {
    case video
    case lowresCopy
    case markerOnly
}

struct ArchiveManifestItem: Codable, Sendable {
    var assetId: UUID
    var originalReference: String?
    var archivePath: String?
    var frameIndex: Int?
    var decision: String
}

struct ArchiveManifest: Identifiable, Sendable {
    let id: UUID
    var expeditionId: UUID?
    var albumId: UUID?
    var generatedAt: Date
    var archiveKind: ArchiveKind
    var items: [ArchiveManifestItem]

    init?(record: ArchiveManifestRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let kind = ArchiveKind(rawValue: record.archiveKind) else {
            return nil
        }
        self.id = uuid
        self.expeditionId = record.expeditionId.flatMap { UUID(uuidString: $0) }
        self.albumId = record.albumId.flatMap { UUID(uuidString: $0) }
        self.generatedAt = Date(timeIntervalSinceReferenceDate: record.generatedAt)
        self.archiveKind = kind
        self.items = Self.decodeItems(record.itemsJSON)
    }

    init(
        id: UUID = UUID(),
        expeditionId: UUID?,
        albumId: UUID? = nil,
        generatedAt: Date = Date(),
        archiveKind: ArchiveKind,
        items: [ArchiveManifestItem]
    ) {
        self.id = id
        self.expeditionId = expeditionId
        self.albumId = albumId
        self.generatedAt = generatedAt
        self.archiveKind = archiveKind
        self.items = items
    }

    func toRecord() -> ArchiveManifestRecord {
        ArchiveManifestRecord(
            id: id.uuidString,
            expeditionId: expeditionId?.uuidString,
            albumId: albumId?.uuidString,
            generatedAt: generatedAt.timeIntervalSinceReferenceDate,
            archiveKind: archiveKind.rawValue,
            itemsJSON: Self.encodeItems(items)
        )
    }

    private static func decodeItems(_ json: String) -> [ArchiveManifestItem] {
        guard let data = json.data(using: .utf8),
              let items = try? _manifestDecoder.decode([ArchiveManifestItem].self, from: data) else {
            return []
        }
        return items
    }

    private static func encodeItems(_ items: [ArchiveManifestItem]) -> String {
        guard let data = try? _manifestEncoder.encode(items) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
