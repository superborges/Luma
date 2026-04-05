import Foundation

enum MediaFileScanner {
    static func scan(rootFolder: URL, source: ImportSource) throws -> [DiscoveredItem] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootFolder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw LumaError.importFailed("Unable to enumerate \(rootFolder.path).")
        }

        struct Candidate {
            let url: URL
            let modifiedAt: Date
        }

        var previews: [String: [Candidate]] = [:]
        var raws: [String: [Candidate]] = [:]
        var videos: [String: [Candidate]] = [:]

        let previewExtensions = Set(["jpg", "jpeg", "heic", "heif"])
        let rawExtensions = Set(["arw", "cr3", "nef", "raf", "dng", "orf", "rw2"])
        let videoExtensions = Set(["mov"])

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            let baseKey = url.deletingPathExtension().lastPathComponent.lowercased()
            let candidate = Candidate(url: url, modifiedAt: values.contentModificationDate ?? .distantPast)

            if previewExtensions.contains(ext) {
                previews[baseKey, default: []].append(candidate)
            } else if rawExtensions.contains(ext) {
                raws[baseKey, default: []].append(candidate)
            } else if videoExtensions.contains(ext) {
                videos[baseKey, default: []].append(candidate)
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
