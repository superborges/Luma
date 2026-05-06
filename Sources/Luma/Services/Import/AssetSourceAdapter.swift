import CoreGraphics
import Foundation

enum SourceCapability: String, Hashable, Sendable {
    case read
    case writeAlbum
    case deleteAsset
    case fetchOriginal
    case fetchThumbnail
    case copyToManagedStorage
}

struct SourceEnumerationOptions: Sendable {
    var dateRange: ClosedRange<Date>?
    var mediaTypeFilter: Set<MediaType>?
    var excludeIdentifiers: Set<String>?

    init(
        dateRange: ClosedRange<Date>? = nil,
        mediaTypeFilter: Set<MediaType>? = nil,
        excludeIdentifiers: Set<String>? = nil
    ) {
        self.dateRange = dateRange
        self.mediaTypeFilter = mediaTypeFilter
        self.excludeIdentifiers = excludeIdentifiers
    }
}

protocol AssetSourceAdapter: Sendable {
    var source: AssetSource { get }
    var displayName: String { get }
    func enumerateAssets(options: SourceEnumerationOptions) async throws -> [DiscoveredAsset]
    func fetchThumbnail(_ asset: DiscoveredAsset, size: CGSize) async throws -> CGImage?
    func fetchPreview(_ asset: DiscoveredAsset) async throws -> URL?
    func fetchOriginal(_ asset: DiscoveredAsset) async throws -> URL?
    func supports(_ capability: SourceCapability) -> Bool
    var connectionState: AsyncStream<ConnectionState> { get }
}
