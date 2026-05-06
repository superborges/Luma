import CoreGraphics
import Foundation

struct SDCardSourceAdapter: AssetSourceAdapter {
    let source: AssetSource
    let volumeURL: URL

    var displayName: String { source.displayName }

    init(source: AssetSource, volumeURL: URL) {
        self.source = source
        self.volumeURL = volumeURL
    }

    var connectionState: AsyncStream<ConnectionState> {
        let monitoredVolume = volumeURL
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                var previousState = SDCardAdapter.isSupportedVolume(monitoredVolume) ? ConnectionState.connected : .disconnected
                continuation.yield(previousState)

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    let currentState: ConnectionState = SDCardAdapter.isSupportedVolume(monitoredVolume) ? .connected : .disconnected
                    if currentState != previousState {
                        continuation.yield(currentState)
                        previousState = currentState
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func enumerateAssets(options: SourceEnumerationOptions) async throws -> [DiscoveredAsset] {
        guard SDCardAdapter.isSupportedVolume(volumeURL) else {
            throw LumaError.unsupported("所选目录不包含 DCIM，无法作为 SD 卡导入。")
        }

        let root = importRoot
        let volumePath = volumeURL.path

        let items = try await Task.detached(priority: .userInitiated) {
            let files = try DCIMScanner.scan(dcimRoot: root)
            return RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: volumePath))
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
                sourceKind: .sdCard,
                previewFileURL: item.previewFile,
                rawFileURL: item.rawFile,
                auxiliaryFileURL: item.auxiliaryFile,
                metadata: item.metadata,
                mediaType: item.mediaType,
                suggestedStorageMode: .managed,
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
        case .read, .fetchOriginal, .fetchThumbnail, .copyToManagedStorage:
            return true
        case .writeAlbum, .deleteAsset:
            return false
        }
    }

    private var importRoot: URL {
        let dcimAtRoot = volumeURL.appendingPathComponent("DCIM", isDirectory: true)
        if FileManager.default.fileExists(atPath: dcimAtRoot.path) {
            return dcimAtRoot
        }
        return volumeURL
    }
}
