import Foundation
import GRDB

protocol AlbumRepository: Sendable {
    func insert(_ record: AlbumRecord) throws
    func update(_ record: AlbumRecord) throws
    func delete(id: String) throws
    func fetchOne(id: String) throws -> AlbumRecord?
    func fetchByExpedition(_ expeditionId: String) throws -> [AlbumRecord]
    func fetchAll() throws -> [AlbumRecord]
    func addAsset(_ record: AlbumAssetRecord) throws
    func addAssetsBatch(_ records: [AlbumAssetRecord]) throws
    func removeAsset(albumId: String, assetId: String) throws
    func removeAssets(albumId: String, assetIds: [String]) throws
    func fetchAlbumAssets(albumId: String) throws -> [AlbumAssetRecord]
    func fetchAssetCount(albumId: String) throws -> Int
    func insertRef(_ record: ExternalAlbumRefRecord) throws
    func fetchRef(albumId: String) throws -> ExternalAlbumRefRecord?
    func deleteRef(albumId: String) throws
}

final class GRDBAlbumRepository: AlbumRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: AlbumRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: AlbumRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try AlbumRecord.deleteOne(db, key: id)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [AlbumRecord] {
        try dbQueue.read { db in
            try AlbumRecord
                .filter(Column("expeditionId") == expeditionId)
                .fetchAll(db)
        }
    }

    func fetchAll() throws -> [AlbumRecord] {
        try dbQueue.read { db in
            try AlbumRecord.fetchAll(db)
        }
    }

    func addAsset(_ record: AlbumAssetRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func fetchOne(id: String) throws -> AlbumRecord? {
        try dbQueue.read { db in
            try AlbumRecord.fetchOne(db, key: id)
        }
    }

    func addAssetsBatch(_ records: [AlbumAssetRecord]) throws {
        try dbQueue.write { db in
            for record in records {
                try record.upsert(db)
            }
        }
    }

    func removeAsset(albumId: String, assetId: String) throws {
        _ = try dbQueue.write { db in
            try AlbumAssetRecord
                .filter(Column("albumId") == albumId && Column("assetId") == assetId)
                .deleteAll(db)
        }
    }

    func removeAssets(albumId: String, assetIds: [String]) throws {
        guard !assetIds.isEmpty else { return }
        _ = try dbQueue.write { db in
            try AlbumAssetRecord
                .filter(Column("albumId") == albumId && assetIds.contains(Column("assetId")))
                .deleteAll(db)
        }
    }

    func fetchAlbumAssets(albumId: String) throws -> [AlbumAssetRecord] {
        try dbQueue.read { db in
            try AlbumAssetRecord
                .filter(Column("albumId") == albumId)
                .order(Column("localOrder").asc)
                .fetchAll(db)
        }
    }

    func fetchAssetCount(albumId: String) throws -> Int {
        try dbQueue.read { db in
            try AlbumAssetRecord
                .filter(Column("albumId") == albumId)
                .fetchCount(db)
        }
    }

    func insertRef(_ record: ExternalAlbumRefRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func fetchRef(albumId: String) throws -> ExternalAlbumRefRecord? {
        try dbQueue.read { db in
            try ExternalAlbumRefRecord.fetchOne(db, key: albumId)
        }
    }

    func deleteRef(albumId: String) throws {
        _ = try dbQueue.write { db in
            try ExternalAlbumRefRecord.deleteOne(db, key: albumId)
        }
    }
}
