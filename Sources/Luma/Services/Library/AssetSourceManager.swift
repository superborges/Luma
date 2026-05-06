import Foundation
import GRDB

final class AssetSourceManager: Sendable {
    private let db: LumaDatabase

    init(db: LumaDatabase) {
        self.db = db
    }

    func registerSource(
        kind: AssetSourceKind,
        displayName: String,
        rootIdentifier: String?
    ) throws -> AssetSource {
        let now = Date().timeIntervalSinceReferenceDate
        let capabilities = Self.defaultCapabilities(for: kind)
        let record = AssetSourceRecord(
            id: UUID().uuidString,
            kind: kind.rawValue,
            displayName: displayName,
            rootIdentifier: rootIdentifier,
            isMutable: capabilities.isMutable,
            supportsDelete: capabilities.supportsDelete,
            supportsAlbumWrite: capabilities.supportsAlbumWrite,
            supportsOriginalAccess: capabilities.supportsOriginalAccess,
            createdAt: now,
            updatedAt: now
        )
        try db.dbQueue.write { db in
            try record.insert(db)
        }
        guard let source = AssetSource(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct AssetSource from newly created record")
        }
        return source
    }

    func fetchSource(id: UUID) throws -> AssetSource? {
        let record = try db.dbQueue.read { db in
            try AssetSourceRecord.fetchOne(db, key: id.uuidString)
        }
        return record.flatMap { AssetSource(record: $0) }
    }

    func fetchByKind(_ kind: AssetSourceKind) throws -> AssetSource? {
        let record = try db.dbQueue.read { db in
            try AssetSourceRecord.filter(Column("kind") == kind.rawValue).fetchOne(db)
        }
        return record.flatMap { AssetSource(record: $0) }
    }

    func listSources() throws -> [AssetSource] {
        let records = try db.dbQueue.read { db in
            try AssetSourceRecord.fetchAll(db)
        }
        return records.compactMap { AssetSource(record: $0) }
    }

    func deleteSource(id: UUID) throws {
        _ = try db.dbQueue.write { db in
            try AssetSourceRecord.deleteOne(db, key: id.uuidString)
        }
    }

    // MARK: - Capabilities

    private struct SourceCapabilities {
        let isMutable: Bool
        let supportsDelete: Bool
        let supportsAlbumWrite: Bool
        let supportsOriginalAccess: Bool
    }

    private static func defaultCapabilities(for kind: AssetSourceKind) -> SourceCapabilities {
        switch kind {
        case .sdCard:
            return SourceCapabilities(
                isMutable: false, supportsDelete: false,
                supportsAlbumWrite: false, supportsOriginalAccess: true
            )
        case .localFolder:
            return SourceCapabilities(
                isMutable: false, supportsDelete: false,
                supportsAlbumWrite: false, supportsOriginalAccess: true
            )
        case .macPhotos:
            return SourceCapabilities(
                isMutable: true, supportsDelete: false,
                supportsAlbumWrite: true, supportsOriginalAccess: false
            )
        }
    }
}
