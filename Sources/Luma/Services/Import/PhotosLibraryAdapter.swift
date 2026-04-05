import CoreGraphics
import Foundation

struct PhotosLibraryAdapter: ImportSourceAdapter {
    var displayName: String {
        "Photos Library"
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.unavailable)
            continuation.finish()
        }
    }

    func enumerate() async throws -> [DiscoveredItem] {
        throw LumaError.notImplemented("Photos library import")
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        nil
    }

    func copyPreview(_ item: DiscoveredItem, to: URL) async throws {
        throw LumaError.notImplemented("Photos library preview copy")
    }

    func copyOriginal(_ item: DiscoveredItem, to: URL) async throws {
        throw LumaError.notImplemented("Photos library original copy")
    }

    func copyAuxiliary(_ item: DiscoveredItem, to: URL) async throws {
        throw LumaError.notImplemented("Photos library auxiliary copy")
    }
}
