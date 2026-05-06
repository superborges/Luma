import Foundation
import CoreGraphics

@available(*, deprecated, message: "Use AssetSourceAdapter instead (V4)")
protocol ImportSourceAdapter {
    var displayName: String { get }
    func enumerate() async throws -> [DiscoveredItem]
    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage?
    func copyPreview(_ item: DiscoveredItem, to: URL) async throws
    func copyOriginal(_ item: DiscoveredItem, to: URL) async throws
    func copyAuxiliary(_ item: DiscoveredItem, to: URL) async throws
    var connectionState: AsyncStream<ConnectionState> { get }
}
