import Foundation
import GRDB

struct MasterAssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "master_assets"

    var id: String
    var sourceId: String?
    var sourceKind: String
    var storageMode: String
    var externalIdentifier: String?
    var originalURL: String?
    var localManagedURL: String?
    var previewURL: String?
    var rawURL: String?
    var livePhotoVideoURL: String?
    var thumbnailCacheURL: String?
    var previewCacheURL: String?
    var fingerprint: String?
    var contentHash: String?
    var baseName: String
    var mediaType: String
    var captureDate: Double?
    var latitude: Double?
    var longitude: Double?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var cameraModel: String?
    var lensModel: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var createdAt: Double
    var updatedAt: Double
}
