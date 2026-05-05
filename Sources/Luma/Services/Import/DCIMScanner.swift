import Foundation

/// DCIM 目录扫描器，递归枚举 DCIM/ 下所有受支持的照片和视频文件。
enum DCIMScanner {

    static let previewExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]
    static let rawExtensions: Set<String> = ["arw", "cr3", "nef", "raf", "dng", "orf", "rw2"]
    static let videoExtensions: Set<String> = ["mov"]

    struct ScannedFile: Hashable {
        let url: URL
        let baseKey: String
        let modifiedAt: Date
        let category: Category
    }

    enum Category: Hashable, Sendable {
        case preview
        case raw(ext: String)
        case video
    }

    /// 快速汇总信息（用于导入前预览弹窗）。
    struct Summary: Sendable {
        let photoCount: Int
        let videoCount: Int
        /// RAW 格式分布（如 ["ARW": 12, "CR3": 3]）。
        let rawFormatDistribution: [String: Int]

        var isEmpty: Bool { photoCount == 0 && videoCount == 0 }
    }

    /// 递归扫描 DCIM 目录，返回所有受支持的文件。
    static func scan(dcimRoot: URL) throws -> [ScannedFile] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: dcimRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw LumaError.importFailed("无法枚举 \(dcimRoot.path)")
        }

        var files: [ScannedFile] = []

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            let baseKey = url.deletingPathExtension().lastPathComponent.lowercased()
            let modifiedAt = values.contentModificationDate ?? .distantPast

            let category: Category?
            if previewExtensions.contains(ext) {
                category = .preview
            } else if rawExtensions.contains(ext) {
                category = .raw(ext: ext.uppercased())
            } else if videoExtensions.contains(ext) {
                category = .video
            } else {
                category = nil
            }

            if let category {
                files.append(ScannedFile(url: url, baseKey: baseKey, modifiedAt: modifiedAt, category: category))
            }
        }

        return files
    }

    /// 快速统计 DCIM 目录中的文件概况（不做完整配对，用于弹窗预览）。
    static func quickSummary(dcimRoot: URL) -> Summary {
        guard let files = try? scan(dcimRoot: dcimRoot) else {
            return Summary(photoCount: 0, videoCount: 0, rawFormatDistribution: [:])
        }

        var rawFormats: [String: Int] = [:]
        var previewBaseKeys: Set<String> = []
        var rawBaseKeys: Set<String> = []
        var videoCount = 0

        for file in files {
            switch file.category {
            case .preview:
                previewBaseKeys.insert(file.baseKey)
            case .raw(let ext):
                rawFormats[ext, default: 0] += 1
                rawBaseKeys.insert(file.baseKey)
            case .video:
                videoCount += 1
            }
        }

        let uniquePhotoKeys = previewBaseKeys.union(rawBaseKeys)

        return Summary(
            photoCount: uniquePhotoKeys.count,
            videoCount: videoCount,
            rawFormatDistribution: rawFormats
        )
    }
}
