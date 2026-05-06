import CoreGraphics
import Foundation

struct FolderSourceAdapter: AssetSourceAdapter {
    let source: AssetSource
    let rootFolder: URL
    let storageMode: AssetStorageMode

    var displayName: String { source.displayName }

    init(source: AssetSource, rootFolder: URL, storageMode: AssetStorageMode) {
        self.source = source
        self.rootFolder = rootFolder
        self.storageMode = storageMode
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.finish()
        }
    }

    func enumerateAssets(options: SourceEnumerationOptions) async throws -> [DiscoveredAsset] {
        let folder = rootFolder
        let mode = storageMode

        let items = try await Task.detached(priority: .userInitiated) {
            try MediaFileScanner.scan(rootFolder: folder, source: .folder(path: folder.path))
        }.value

        return items.compactMap { item in
            if let filter = options.mediaTypeFilter, !filter.contains(item.mediaType) { return nil }
            if let excludes = options.excludeIdentifiers, excludes.contains(item.baseName) { return nil }
            if let dateRange = options.dateRange,
               !dateRange.contains(item.metadata.captureDate) { return nil }

            let representativeURL = item.previewFile ?? item.rawFile
            let hashHint = representativeURL.flatMap { try? AssetManager.computeContentHash(fileURL: $0) }

            return DiscoveredAsset(
                baseName: item.baseName,
                sourceKind: .localFolder,
                previewFileURL: item.previewFile,
                rawFileURL: item.rawFile,
                auxiliaryFileURL: item.auxiliaryFile,
                metadata: item.metadata,
                mediaType: item.mediaType,
                suggestedStorageMode: mode,
                contentHashHint: hashHint
            )
        }
    }

    func fetchThumbnail(_ asset: DiscoveredAsset, size: CGSize) async throws -> CGImage? {
        guard let url = asset.previewFileURL ?? asset.rawFileURL else { return nil }
        return EXIFParser.makeThumbnail(from: url, maxPixelSize: Int(max(size.width, size.height)))
    }

    func fetchPreview(_ asset: DiscoveredAsset) async throws -> URL? {
        asset.previewFileURL
    }

    func fetchOriginal(_ asset: DiscoveredAsset) async throws -> URL? {
        asset.rawFileURL
    }

    func supports(_ capability: SourceCapability) -> Bool {
        switch capability {
        case .read, .fetchOriginal, .fetchThumbnail:
            return true
        case .copyToManagedStorage:
            return storageMode == .managed
        case .writeAlbum, .deleteAsset:
            return false
        }
    }
}
