import CoreGraphics
import Foundation

struct FolderAdapter: ImportSourceAdapter {
    let rootFolder: URL

    var displayName: String {
        rootFolder.lastPathComponent
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.finish()
        }
    }

    func enumerate() async throws -> [DiscoveredItem] {
        try await Task.detached(priority: .userInitiated) {
            try buildItems()
        }.value
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        guard let url = item.previewFile ?? item.rawFile else {
            return nil
        }
        return EXIFParser.makeThumbnail(from: url, maxPixelSize: ThumbnailCache.thumbnailMaxPixelSize)
    }

    func copyPreview(_ item: DiscoveredItem, to destination: URL) async throws {
        guard let source = item.previewFile else { return }
        try copyItem(from: source, to: destination)
    }

    func copyOriginal(_ item: DiscoveredItem, to destination: URL) async throws {
        guard let source = item.rawFile else { return }
        try copyItem(from: source, to: destination)
    }

    func copyAuxiliary(_ item: DiscoveredItem, to destination: URL) async throws {
        guard let source = item.auxiliaryFile else { return }
        try copyItem(from: source, to: destination)
    }

    private func buildItems() throws -> [DiscoveredItem] {
        try MediaFileScanner.scan(rootFolder: rootFolder, source: .folder(path: rootFolder.path))
    }

    private func copyItem(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }
}
