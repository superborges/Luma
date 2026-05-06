import Foundation

enum AlbumKind: String, Codable, Sendable {
    case manual
    case smart
    case photosBacked
}

private let _albumRuleDecoder = JSONDecoder()
private let _albumRuleEncoder = JSONEncoder()

struct LumaAlbum: Identifiable, Sendable {
    let id: UUID
    var expeditionId: UUID?
    var name: String
    var kind: AlbumKind
    var rule: SmartAlbumRule?
    var createdAt: Date
    var updatedAt: Date

    init?(record: AlbumRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let kind = AlbumKind(rawValue: record.kind) else {
            return nil
        }
        self.id = uuid
        self.expeditionId = record.expeditionId.flatMap { UUID(uuidString: $0) }
        self.name = record.name
        self.kind = kind
        self.rule = record.ruleJSON.flatMap {
            try? _albumRuleDecoder.decode(SmartAlbumRule.self, from: Data($0.utf8))
        }
        self.createdAt = Date(timeIntervalSinceReferenceDate: record.createdAt)
        self.updatedAt = Date(timeIntervalSinceReferenceDate: record.updatedAt)
    }

    func toRecord() -> AlbumRecord {
        let ruleJSON: String? = rule.flatMap {
            try? String(data: _albumRuleEncoder.encode($0), encoding: .utf8)
        }
        return AlbumRecord(
            id: id.uuidString,
            expeditionId: expeditionId?.uuidString,
            name: name,
            kind: kind.rawValue,
            ruleJSON: ruleJSON,
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            updatedAt: updatedAt.timeIntervalSinceReferenceDate
        )
    }
}

struct AlbumAsset: Identifiable, Sendable {
    let albumId: UUID
    let assetId: UUID
    var addedAt: Date
    var localOrder: Int

    var id: String { "\(albumId)-\(assetId)" }

    init?(record: AlbumAssetRecord) {
        guard let aId = UUID(uuidString: record.albumId),
              let mId = UUID(uuidString: record.assetId) else {
            return nil
        }
        self.albumId = aId
        self.assetId = mId
        self.addedAt = Date(timeIntervalSinceReferenceDate: record.addedAt)
        self.localOrder = record.localOrder
    }
}

struct ExternalAlbumRef: Sendable {
    var provider: ExternalAlbumProvider
    var localIdentifier: String
    var albumId: UUID

    init(provider: ExternalAlbumProvider, localIdentifier: String, albumId: UUID) {
        self.provider = provider
        self.localIdentifier = localIdentifier
        self.albumId = albumId
    }

    init?(record: ExternalAlbumRefRecord) {
        guard let prov = ExternalAlbumProvider(rawValue: record.provider),
              let aId = UUID(uuidString: record.albumId) else {
            return nil
        }
        self.provider = prov
        self.localIdentifier = record.localIdentifier
        self.albumId = aId
    }

    func toRecord() -> ExternalAlbumRefRecord {
        ExternalAlbumRefRecord(
            albumId: albumId.uuidString,
            provider: provider.rawValue,
            localIdentifier: localIdentifier
        )
    }
}

enum ExternalAlbumProvider: String, Codable, Sendable {
    case macPhotos
}
