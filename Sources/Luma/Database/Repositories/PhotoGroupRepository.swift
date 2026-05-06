import Foundation
import GRDB

protocol PhotoGroupRepository: Sendable {
    func insert(_ record: PhotoGroupRecord) throws
    func update(_ record: PhotoGroupRecord) throws
    func delete(id: String) throws
    func fetchByExpedition(_ expeditionId: String) throws -> [PhotoGroupRecord]
    func addAsset(_ record: PhotoGroupAssetRecord) throws
    func removeAsset(groupId: String, assetId: String) throws
    func fetchAssetsForGroup(_ groupId: String) throws -> [PhotoGroupAssetRecord]
}

final class GRDBPhotoGroupRepository: PhotoGroupRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: PhotoGroupRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: PhotoGroupRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try PhotoGroupRecord.deleteOne(db, key: id)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [PhotoGroupRecord] {
        try dbQueue.read { db in
            try PhotoGroupRecord.filter(Column("expeditionId") == expeditionId).fetchAll(db)
        }
    }

    func addAsset(_ record: PhotoGroupAssetRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func removeAsset(groupId: String, assetId: String) throws {
        _ = try dbQueue.write { db in
            try PhotoGroupAssetRecord
                .filter(Column("groupId") == groupId && Column("assetId") == assetId)
                .deleteAll(db)
        }
    }

    func fetchAssetsForGroup(_ groupId: String) throws -> [PhotoGroupAssetRecord] {
        try dbQueue.read { db in
            try PhotoGroupAssetRecord.filter(Column("groupId") == groupId).fetchAll(db)
        }
    }
}
