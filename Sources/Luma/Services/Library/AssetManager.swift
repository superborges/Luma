import Foundation
import GRDB
import CryptoKit

final class AssetManager: Sendable {
    private let db: LumaDatabase
    private let assetRepo: any MasterAssetRepository
    private let expeditionAssetRepo: any ExpeditionAssetRepository

    init(
        db: LumaDatabase,
        assetRepo: any MasterAssetRepository,
        expeditionAssetRepo: any ExpeditionAssetRepository
    ) {
        self.db = db
        self.assetRepo = assetRepo
        self.expeditionAssetRepo = expeditionAssetRepo
    }

    // MARK: - Dedup & Create

    func createOrReuseMasterAsset(
        baseName: String,
        mediaType: MediaType,
        sourceKind: AssetSourceKind,
        storageMode: AssetStorageMode,
        sourceId: UUID?,
        externalIdentifier: String?,
        contentHash: String?,
        originalURL: URL?,
        metadata: EXIFData?
    ) throws -> MasterAsset {
        let record: MasterAssetRecord = try db.dbQueue.write { db in
            // 1. Mac Photos dedup by externalIdentifier
            if let extId = externalIdentifier,
               let existing = try MasterAssetRecord.filter(Column("externalIdentifier") == extId).fetchOne(db) {
                return existing
            }
            // 2. Dedup by content hash
            if let hash = contentHash,
               let existing = try MasterAssetRecord.filter(Column("contentHash") == hash).fetchOne(db) {
                return existing
            }
            // 3. Dedup by originalURL (referenced folders)
            if let url = originalURL,
               let existing = try MasterAssetRecord.filter(Column("originalURL") == url.absoluteString).fetchOne(db) {
                return existing
            }
            // 4. Create new — inside same write transaction
            let now = Date().timeIntervalSinceReferenceDate
            var newRecord = MasterAssetRecord(
                id: UUID().uuidString,
                sourceId: sourceId?.uuidString,
                sourceKind: sourceKind.rawValue,
                storageMode: storageMode.rawValue,
                externalIdentifier: externalIdentifier,
                originalURL: originalURL?.absoluteString,
                localManagedURL: nil,
                previewURL: nil,
                rawURL: nil,
                livePhotoVideoURL: nil,
                thumbnailCacheURL: nil,
                previewCacheURL: nil,
                fingerprint: nil,
                contentHash: contentHash,
                baseName: baseName,
                mediaType: mediaType.rawValue,
                captureDate: metadata?.captureDate.timeIntervalSinceReferenceDate,
                latitude: metadata?.gpsCoordinate?.latitude,
                longitude: metadata?.gpsCoordinate?.longitude,
                focalLength: metadata?.focalLength,
                aperture: metadata?.aperture,
                shutterSpeed: metadata?.shutterSpeed,
                iso: metadata?.iso,
                cameraModel: metadata?.cameraModel,
                lensModel: metadata?.lensModel,
                imageWidth: metadata?.imageWidth,
                imageHeight: metadata?.imageHeight,
                createdAt: now,
                updatedAt: now
            )
            try newRecord.insert(db)
            return newRecord
        }
        guard let asset = MasterAsset(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct MasterAsset from record")
        }
        return asset
    }

    // MARK: - Expedition ↔ Asset

    func addAssetToExpedition(
        assetId: UUID,
        expeditionId: UUID,
        addedBy: AssetAddedBy
    ) throws -> ExpeditionAsset {
        let expIdStr = expeditionId.uuidString
        let assetIdStr = assetId.uuidString

        let existing = try db.dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expIdStr && Column("assetId") == assetIdStr)
                .fetchOne(db)
        }
        if let existing {
            guard let asset = ExpeditionAsset(record: existing) else {
                throw LumaError.persistenceFailed("Failed to construct ExpeditionAsset from existing record")
            }
            return asset
        }

        let now = Date().timeIntervalSinceReferenceDate
        let record = ExpeditionAssetRecord(
            id: UUID().uuidString,
            expeditionId: expIdStr,
            assetId: assetIdStr,
            addedAt: now,
            addedBy: addedBy.rawValue,
            localOrder: 0,
            decision: Decision.pending.rawValue,
            rating: nil,
            colorLabel: nil,
            isRecommended: false,
            isBestInGroup: false,
            isUserOverride: false,
            isArchived: false,
            isHiddenInExpedition: false,
            updatedAt: now
        )
        try expeditionAssetRepo.insert(record)
        guard let asset = ExpeditionAsset(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct ExpeditionAsset from newly created record")
        }
        return asset
    }

    @discardableResult
    func addAssetToExpedition(
        expeditionId: UUID,
        assetId: UUID,
        addedBy: AssetAddedBy,
        decision: Decision,
        rating: Int?,
        isRecommended: Bool
    ) throws -> ExpeditionAsset {
        let expIdStr = expeditionId.uuidString
        let assetIdStr = assetId.uuidString

        let existing = try db.dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expIdStr && Column("assetId") == assetIdStr)
                .fetchOne(db)
        }
        if let existing {
            guard let asset = ExpeditionAsset(record: existing) else {
                throw LumaError.persistenceFailed("Failed to construct ExpeditionAsset from existing record")
            }
            return asset
        }

        let now = Date().timeIntervalSinceReferenceDate
        let record = ExpeditionAssetRecord(
            id: UUID().uuidString,
            expeditionId: expIdStr,
            assetId: assetIdStr,
            addedAt: now,
            addedBy: addedBy.rawValue,
            localOrder: 0,
            decision: decision.rawValue,
            rating: rating,
            colorLabel: nil,
            isRecommended: isRecommended,
            isBestInGroup: false,
            isUserOverride: false,
            isArchived: false,
            isHiddenInExpedition: false,
            updatedAt: now
        )
        try expeditionAssetRepo.insert(record)
        guard let asset = ExpeditionAsset(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct ExpeditionAsset from newly created record")
        }
        return asset
    }

    func removeAssetFromExpedition(assetId: UUID, expeditionId: UUID) throws {
        _ = try db.dbQueue.write { db in
            try ExpeditionAssetRecord
                .filter(
                    Column("expeditionId") == expeditionId.uuidString
                        && Column("assetId") == assetId.uuidString
                )
                .deleteAll(db)
        }
    }

    // MARK: - Decision & Rating

    func setDecision(
        expeditionId: UUID,
        assetId: UUID,
        decision: Decision,
        isUserOverride: Bool = false
    ) throws {
        try db.dbQueue.write { db in
            guard var record = try ExpeditionAssetRecord
                .filter(
                    Column("expeditionId") == expeditionId.uuidString
                        && Column("assetId") == assetId.uuidString
                )
                .fetchOne(db) else { return }
            record.decision = decision.rawValue
            record.isUserOverride = isUserOverride
            record.updatedAt = Date().timeIntervalSinceReferenceDate
            try record.update(db)
        }
    }

    func setRating(expeditionId: UUID, assetId: UUID, rating: Int?) throws {
        try db.dbQueue.write { db in
            guard var record = try ExpeditionAssetRecord
                .filter(
                    Column("expeditionId") == expeditionId.uuidString
                        && Column("assetId") == assetId.uuidString
                )
                .fetchOne(db) else { return }
            record.rating = rating
            record.updatedAt = Date().timeIntervalSinceReferenceDate
            try record.update(db)
        }
    }

    func setRecommendation(expeditionId: UUID, assetId: UUID, isRecommended: Bool) throws {
        try db.dbQueue.write { db in
            guard var record = try ExpeditionAssetRecord
                .filter(
                    Column("expeditionId") == expeditionId.uuidString
                        && Column("assetId") == assetId.uuidString
                )
                .fetchOne(db) else { return }
            record.isRecommended = isRecommended
            record.updatedAt = Date().timeIntervalSinceReferenceDate
            try record.update(db)
        }
    }

    // MARK: - Queries

    func fetchAssetsForExpedition(
        expeditionId: UUID,
        decision: Decision? = nil
    ) throws -> [MasterAsset] {
        let expIdStr = expeditionId.uuidString
        let expAssetRecords: [ExpeditionAssetRecord]
        if let decision {
            expAssetRecords = try expeditionAssetRepo.fetchByExpeditionAndDecision(
                expIdStr, decision: decision.rawValue
            )
        } else {
            expAssetRecords = try expeditionAssetRepo.fetchByExpedition(expIdStr)
        }

        let assetIds = expAssetRecords.map(\.assetId)
        guard !assetIds.isEmpty else { return [] }

        let records = try db.dbQueue.read { db in
            try MasterAssetRecord.filter(assetIds.contains(Column("id"))).fetchAll(db)
        }
        return records.compactMap { MasterAsset(record: $0) }
    }

    func fetchExpeditionAsset(
        expeditionId: UUID,
        assetId: UUID
    ) throws -> ExpeditionAsset? {
        let record = try db.dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(
                    Column("expeditionId") == expeditionId.uuidString
                        && Column("assetId") == assetId.uuidString
                )
                .fetchOne(db)
        }
        return record.flatMap { ExpeditionAsset(record: $0) }
    }

    func fetchAllMasterAssets(limit: Int = 100, offset: Int = 0) throws -> [MasterAsset] {
        let records = try db.dbQueue.read { db in
            try MasterAssetRecord
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
        return records.compactMap { MasterAsset(record: $0) }
    }

    // MARK: - Update

    func updateMasterAsset(_ asset: MasterAsset) throws {
        var record = asset.toRecord()
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try assetRepo.update(record)
    }

    // MARK: - Content Hash

    static func computeContentHash(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let prefix = data.prefix(4096)
        let fileSize = data.count
        var hasher = SHA256()
        hasher.update(data: prefix)
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined() + "_\(fileSize)"
    }
}
