import Foundation

struct AssetSource: Identifiable, Sendable {
    let id: UUID
    var kind: AssetSourceKind
    var displayName: String
    var rootIdentifier: String?
    var isMutable: Bool
    var supportsDelete: Bool
    var supportsAlbumWrite: Bool
    var supportsOriginalAccess: Bool
    var createdAt: Date
    var updatedAt: Date

    init?(record: AssetSourceRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let k = AssetSourceKind(rawValue: record.kind) else {
            return nil
        }
        self.id = uuid
        self.kind = k
        self.displayName = record.displayName
        self.rootIdentifier = record.rootIdentifier
        self.isMutable = record.isMutable
        self.supportsDelete = record.supportsDelete
        self.supportsAlbumWrite = record.supportsAlbumWrite
        self.supportsOriginalAccess = record.supportsOriginalAccess
        self.createdAt = Date(timeIntervalSinceReferenceDate: record.createdAt)
        self.updatedAt = Date(timeIntervalSinceReferenceDate: record.updatedAt)
    }

    func toRecord() -> AssetSourceRecord {
        AssetSourceRecord(
            id: id.uuidString,
            kind: kind.rawValue,
            displayName: displayName,
            rootIdentifier: rootIdentifier,
            isMutable: isMutable,
            supportsDelete: supportsDelete,
            supportsAlbumWrite: supportsAlbumWrite,
            supportsOriginalAccess: supportsOriginalAccess,
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            updatedAt: updatedAt.timeIntervalSinceReferenceDate
        )
    }
}
