import Foundation

/// 按文件 base name 匹配 RAW+JPEG 配对，生成 `DiscoveredItem` 列表。
enum RAWJPEGPairer {

    /// 将 `DCIMScanner.scan()` 的结果配对为 `DiscoveredItem` 列表。
    ///
    /// 配对规则：
    /// - 同 baseKey 的 preview（JPEG/HEIC）和 raw 文件为一组
    /// - 同 baseKey 有多个候选时取最新（modifiedAt 降序）
    /// - 仅有 RAW 无 JPEG 时，`previewFile` 为 nil，
    ///   `SDCardAdapter.fetchThumbnail` 会通过 `CGImageSourceCreateThumbnailAtIndex` 提取内嵌预览
    static func pair(
        files: [DCIMScanner.ScannedFile],
        source: ImportSource
    ) -> [DiscoveredItem] {
        var previews: [String: [DCIMScanner.ScannedFile]] = [:]
        var raws: [String: [DCIMScanner.ScannedFile]] = [:]
        var videos: [String: [DCIMScanner.ScannedFile]] = [:]

        for file in files {
            switch file.category {
            case .preview:
                previews[file.baseKey, default: []].append(file)
            case .raw:
                raws[file.baseKey, default: []].append(file)
            case .video:
                videos[file.baseKey, default: []].append(file)
            }
        }

        let allKeys = Set(previews.keys)
            .union(raws.keys)
            .union(videos.keys)

        let items = allKeys.compactMap { key -> DiscoveredItem? in
            let preview = previews[key]?.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first
            let raw = raws[key]?.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first
            let video = videos[key]?.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first

            guard let representativeURL = preview?.url ?? raw?.url ?? video?.url else {
                return nil
            }

            let metadata = EXIFParser.parse(from: representativeURL)
            let baseName = representativeURL.deletingPathExtension().lastPathComponent

            return DiscoveredItem(
                id: UUID(),
                resumeKey: key,
                baseName: baseName,
                source: source,
                previewFile: preview?.url,
                rawFile: raw?.url,
                auxiliaryFile: video?.url,
                depthData: false,
                metadata: metadata,
                mediaType: video != nil ? .livePhoto : .photo
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.metadata.captureDate == rhs.metadata.captureDate {
                return lhs.baseName.localizedCaseInsensitiveCompare(rhs.baseName) == .orderedAscending
            }
            return lhs.metadata.captureDate < rhs.metadata.captureDate
        }
    }
}
