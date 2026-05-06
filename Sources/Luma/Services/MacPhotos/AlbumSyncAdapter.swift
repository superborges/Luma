import Foundation

protocol AlbumSyncAdapter: Sendable {
    var displayName: String { get }
    func createAlbum(name: String, assets: [MasterAsset]) async throws -> ExternalAlbumRef
    func updateAlbum(_ ref: ExternalAlbumRef, assets: [MasterAsset]) async throws
    func removeAssets(_ assets: [MasterAsset], from ref: ExternalAlbumRef) async throws
    func validateAccess(_ ref: ExternalAlbumRef) async throws -> Bool
}

enum AlbumSyncStatus: Sendable {
    case notSynced
    case syncing
    case synced
    case stale
}
