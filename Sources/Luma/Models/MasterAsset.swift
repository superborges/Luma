import Foundation

struct MasterAsset: Identifiable, Sendable {
    let id: UUID
    var sourceId: UUID?
    var sourceKind: AssetSourceKind
    var storageMode: AssetStorageMode
    var externalIdentifier: String?
    var originalURL: URL?
    var localManagedURL: URL?
    var previewURL: URL?
    var rawURL: URL?
    var livePhotoVideoURL: URL?
    var thumbnailCacheURL: URL?
    var previewCacheURL: URL?
    var fingerprint: String?
    var contentHash: String?
    var baseName: String
    var mediaType: MediaType
    var metadata: EXIFData?
    var captureDate: Date?
    var createdAt: Date
    var updatedAt: Date

    var existingImageFileURL: URL? {
        let fm = FileManager.default
        if let u = previewURL, fm.fileExists(atPath: u.path) { return u }
        if let u = rawURL, fm.fileExists(atPath: u.path) { return u }
        if let u = thumbnailCacheURL, fm.fileExists(atPath: u.path) { return u }
        return nil
    }

    init?(record: MasterAssetRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let sk = AssetSourceKind(rawValue: record.sourceKind),
              let sm = AssetStorageMode(rawValue: record.storageMode),
              let mt = MediaType(rawValue: record.mediaType) else {
            return nil
        }
        self.id = uuid
        self.sourceId = record.sourceId.flatMap { UUID(uuidString: $0) }
        self.sourceKind = sk
        self.storageMode = sm
        self.externalIdentifier = record.externalIdentifier
        self.originalURL = record.originalURL.flatMap { URL(string: $0) }
        self.localManagedURL = record.localManagedURL.flatMap { URL(string: $0) }
        self.previewURL = record.previewURL.flatMap { URL(string: $0) }
        self.rawURL = record.rawURL.flatMap { URL(string: $0) }
        self.livePhotoVideoURL = record.livePhotoVideoURL.flatMap { URL(string: $0) }
        self.thumbnailCacheURL = record.thumbnailCacheURL.flatMap { URL(string: $0) }
        self.previewCacheURL = record.previewCacheURL.flatMap { URL(string: $0) }
        self.fingerprint = record.fingerprint
        self.contentHash = record.contentHash
        self.baseName = record.baseName
        self.mediaType = mt
        self.captureDate = record.captureDate.map { Date(timeIntervalSinceReferenceDate: $0) }
        self.createdAt = Date(timeIntervalSinceReferenceDate: record.createdAt)
        self.updatedAt = Date(timeIntervalSinceReferenceDate: record.updatedAt)

        let hasAnyEXIF = record.imageWidth != nil || record.imageHeight != nil
            || record.latitude != nil || record.focalLength != nil
            || record.cameraModel != nil || record.lensModel != nil
            || record.aperture != nil || record.iso != nil
        if hasAnyEXIF {
            let coordinate: Coordinate?
            if let lat = record.latitude, let lon = record.longitude {
                coordinate = Coordinate(latitude: lat, longitude: lon)
            } else {
                coordinate = nil
            }
            self.metadata = EXIFData(
                captureDate: self.captureDate ?? .distantPast,
                gpsCoordinate: coordinate,
                focalLength: record.focalLength,
                aperture: record.aperture,
                shutterSpeed: record.shutterSpeed,
                iso: record.iso,
                cameraModel: record.cameraModel,
                lensModel: record.lensModel,
                imageWidth: record.imageWidth ?? 0,
                imageHeight: record.imageHeight ?? 0
            )
        } else {
            self.metadata = nil
        }
    }

    func toRecord() -> MasterAssetRecord {
        MasterAssetRecord(
            id: id.uuidString,
            sourceId: sourceId?.uuidString,
            sourceKind: sourceKind.rawValue,
            storageMode: storageMode.rawValue,
            externalIdentifier: externalIdentifier,
            originalURL: originalURL?.absoluteString,
            localManagedURL: localManagedURL?.absoluteString,
            previewURL: previewURL?.absoluteString,
            rawURL: rawURL?.absoluteString,
            livePhotoVideoURL: livePhotoVideoURL?.absoluteString,
            thumbnailCacheURL: thumbnailCacheURL?.absoluteString,
            previewCacheURL: previewCacheURL?.absoluteString,
            fingerprint: fingerprint,
            contentHash: contentHash,
            baseName: baseName,
            mediaType: mediaType.rawValue,
            captureDate: captureDate?.timeIntervalSinceReferenceDate,
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
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            updatedAt: updatedAt.timeIntervalSinceReferenceDate
        )
    }
}
