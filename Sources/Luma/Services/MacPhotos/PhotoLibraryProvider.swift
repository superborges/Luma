import Foundation

/// Lightweight snapshot of a PHAsset, decoupled from PhotoKit object lifecycle.
struct PHAssetSnapshot: Sendable {
    let localIdentifier: String
    let mediaType: MediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let modificationDate: Date?
    let latitude: Double?
    let longitude: Double?
    let isFavorite: Bool
    let isLocallyAvailable: Bool
}

/// Lightweight snapshot of a PHAssetCollection.
struct PHCollectionSnapshot: Sendable {
    let localIdentifier: String
    let title: String
    let estimatedAssetCount: Int
    let collectionType: CollectionKind

    enum CollectionKind: String, Sendable {
        case smartAlbum
        case userAlbum
    }
}

/// Abstraction over PhotoKit for testability.
/// All core logic depends on this protocol; tests inject `MockPhotoLibraryProvider`.
protocol PhotoLibraryProvider: Sendable {
    func currentAuthorizationStatus() -> PhotoAuthorizationStatus
    func requestAuthorization() async -> PhotoAuthorizationStatus
    func enumerateAssets() async -> [PHAssetSnapshot]
    func fetchCollections() async -> [PHCollectionSnapshot]
    func assetIdentifiers(in collectionId: String) async -> [String]
}

enum PhotoAuthorizationStatus: String, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
}
