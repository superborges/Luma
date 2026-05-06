import Foundation
import os

struct MacPhotosIndexProgress: Sendable {
    let indexed: Int
    let total: Int
    var isComplete: Bool { indexed >= total }
}

@MainActor
final class MacPhotosManager {

    private let provider: PhotoLibraryProvider
    private let assetManager: AssetManager
    private let assetSourceManager: AssetSourceManager
    private let db: LumaDatabase

    private static let logger = Logger(subsystem: "Luma", category: "MacPhotosManager")
    private static let sourceDisplayName = "Mac Photos"

    private static let disconnectedKey = "Luma.macPhotos.isDisconnectedByUser"

    private(set) var authorizationStatus: PhotoAuthorizationStatus = .notDetermined
    private(set) var isDisconnectedByUser: Bool {
        didSet { UserDefaults.standard.set(isDisconnectedByUser, forKey: Self.disconnectedKey) }
    }
    private(set) var isIndexing = false
    private(set) var indexProgress: MacPhotosIndexProgress?
    private(set) var lastSyncDate: Date?
    private(set) var totalIndexedCount: Int = 0

    init(
        provider: PhotoLibraryProvider,
        assetManager: AssetManager,
        assetSourceManager: AssetSourceManager,
        db: LumaDatabase
    ) {
        self.provider = provider
        self.assetManager = assetManager
        self.assetSourceManager = assetSourceManager
        self.db = db
        self.isDisconnectedByUser = UserDefaults.standard.bool(forKey: Self.disconnectedKey)
        self.authorizationStatus = provider.currentAuthorizationStatus()
    }

    var isConnected: Bool {
        !isDisconnectedByUser && (authorizationStatus == .authorized || authorizationStatus == .limited)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> PhotoAuthorizationStatus {
        let status = await provider.requestAuthorization()
        authorizationStatus = status
        return status
    }

    // MARK: - Connect / Disconnect

    func connect() async throws {
        isDisconnectedByUser = false
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw LumaError.importFailed("Mac Photos 授权被拒绝（状态：\(status.rawValue)）")
        }

        try ensureMacPhotosSource()
        await performFullIndex()
    }

    func disconnect() {
        isDisconnectedByUser = true
        isIndexing = false
        indexProgress = nil
        Self.logger.info("Mac Photos disconnected by user (data retained)")
    }

    /// Called at boot to restore state from persisted DB data.
    func restoreIndexedCount(_ count: Int) {
        totalIndexedCount = count
    }

    // MARK: - Manual Refresh

    func refreshIndex() async {
        guard isConnected else { return }
        await performFullIndex()
    }

    // MARK: - Full Index

    func performFullIndex() async {
        guard !isIndexing else { return }
        isIndexing = true
        indexProgress = MacPhotosIndexProgress(indexed: 0, total: 0)

        Self.logger.info("Starting Mac Photos full index...")
        let snapshots = await provider.enumerateAssets()
        let total = snapshots.count

        indexProgress = MacPhotosIndexProgress(indexed: 0, total: total)

        let source = try? getOrCreateMacPhotosSource()
        let sourceId = source?.id
        let batchSize = 500
        var indexed = 0

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = snapshots[batchStart..<batchEnd]

            for snapshot in batch {
                do {
                    try indexOneAsset(snapshot, sourceId: sourceId)
                    indexed += 1
                } catch {
                    Self.logger.warning("Failed to index asset \(snapshot.localIdentifier): \(error.localizedDescription)")
                }
            }

            indexProgress = MacPhotosIndexProgress(indexed: indexed, total: total)

            if batchEnd < total {
                await Task.yield()
            }
        }

        totalIndexedCount = indexed
        lastSyncDate = Date()
        isIndexing = false
        indexProgress = MacPhotosIndexProgress(indexed: indexed, total: total)

        Self.logger.info("Mac Photos index completed: \(indexed)/\(total) assets indexed")
    }

    // MARK: - Collections

    func fetchCollections() async -> [PHCollectionSnapshot] {
        await provider.fetchCollections()
    }

    func assetIdentifiers(in collectionId: String) async -> [String] {
        await provider.assetIdentifiers(in: collectionId)
    }

    // MARK: - Private

    private func indexOneAsset(_ snapshot: PHAssetSnapshot, sourceId: UUID?) throws {
        let hasAnyMeta = snapshot.pixelWidth > 0 || snapshot.pixelHeight > 0
            || snapshot.latitude != nil
        var metadata: EXIFData?
        if hasAnyMeta {
            let coord: Coordinate?
            if let lat = snapshot.latitude, let lon = snapshot.longitude {
                coord = Coordinate(latitude: lat, longitude: lon)
            } else {
                coord = nil
            }
            metadata = EXIFData(
                captureDate: snapshot.creationDate ?? .distantPast,
                gpsCoordinate: coord,
                focalLength: nil,
                aperture: nil,
                shutterSpeed: nil,
                iso: nil,
                cameraModel: nil,
                lensModel: nil,
                imageWidth: snapshot.pixelWidth,
                imageHeight: snapshot.pixelHeight
            )
        }

        let displayName: String
        if let date = snapshot.creationDate {
            let formatter = Self.dateFormatter
            displayName = "IMG_\(formatter.string(from: date))"
        } else {
            displayName = snapshot.localIdentifier
        }

        _ = try assetManager.createOrReuseMasterAsset(
            baseName: displayName,
            mediaType: snapshot.mediaType,
            sourceKind: .macPhotos,
            storageMode: .externalReference,
            sourceId: sourceId,
            externalIdentifier: snapshot.localIdentifier,
            contentHash: nil,
            originalURL: nil,
            metadata: metadata
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    private func ensureMacPhotosSource() throws {
        _ = try getOrCreateMacPhotosSource()
    }

    private func getOrCreateMacPhotosSource() throws -> AssetSource {
        if let existing = try assetSourceManager.fetchByKind(.macPhotos) {
            return existing
        }
        return try assetSourceManager.registerSource(
            kind: .macPhotos,
            displayName: Self.sourceDisplayName,
            rootIdentifier: "com.apple.Photos"
        )
    }
}
