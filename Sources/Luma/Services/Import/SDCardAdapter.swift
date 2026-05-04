import CoreGraphics
import Foundation

struct SDCardAdapter: ImportSourceAdapter {
    let volumeURL: URL

    var displayName: String {
        volumeURL.lastPathComponent
    }

    var connectionState: AsyncStream<ConnectionState> {
        let monitoredVolume = volumeURL
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                var previousState = Self.isSupportedVolume(monitoredVolume) ? ConnectionState.connected : .disconnected
                continuation.yield(previousState)

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    let currentState: ConnectionState = Self.isSupportedVolume(monitoredVolume) ? .connected : .disconnected
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

    func enumerate() async throws -> [DiscoveredItem] {
        guard Self.isSupportedVolume(volumeURL) else {
            throw LumaError.unsupported("所选目录不包含 DCIM，无法作为 SD 卡导入。")
        }

        let root = importRoot
        let volumePath = volumeURL.path
        return try await Task.detached(priority: .userInitiated) {
            let files = try DCIMScanner.scan(dcimRoot: root)
            return RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: volumePath))
        }.value
    }

    /// 快速扫描汇总（弹窗展示用，不做完整配对）。
    func quickSummary() -> DCIMScanner.Summary {
        DCIMScanner.quickSummary(dcimRoot: importRoot)
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        guard let url = item.previewFile ?? item.rawFile else {
            return nil
        }
        return EXIFParser.makeThumbnail(from: url, maxPixelSize: ThumbnailCache.thumbnailMaxPixelSize)
    }

    func copyPreview(_ item: DiscoveredItem, to: URL) async throws {
        guard let source = item.previewFile else { return }
        try copyItem(from: source, to: to)
    }

    func copyOriginal(_ item: DiscoveredItem, to: URL) async throws {
        guard let source = item.rawFile else { return }
        try copyItem(from: source, to: to)
    }

    func copyAuxiliary(_ item: DiscoveredItem, to: URL) async throws {
        guard let source = item.auxiliaryFile else { return }
        try copyItem(from: source, to: to)
    }

    static func availableVolumes() -> [URL] {
        let volumesRoot = URL(filePath: "/Volumes", directoryHint: .isDirectory)
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: volumesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates
            .filter { isSupportedVolume($0) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func isSupportedVolume(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let dcimAtRoot = url.appendingPathComponent("DCIM", isDirectory: true)

        if fileManager.fileExists(atPath: dcimAtRoot.path) {
            return true
        }

        return url.lastPathComponent.caseInsensitiveCompare("DCIM") == .orderedSame
    }

    private var importRoot: URL {
        let dcimAtRoot = volumeURL.appendingPathComponent("DCIM", isDirectory: true)
        if FileManager.default.fileExists(atPath: dcimAtRoot.path) {
            return dcimAtRoot
        }
        return volumeURL
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
