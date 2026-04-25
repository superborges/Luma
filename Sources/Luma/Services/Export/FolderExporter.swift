import Foundation

struct FolderExporter: ExportDestinationAdapter {
    var displayName: String {
        "Folder"
    }

    func validateConfiguration(options: ExportOptions) async throws -> Bool {
        options.outputPath != nil
    }

    func export(assets: [MediaAsset], groups: [PhotoGroup], options: ExportOptions) async throws -> ExportResult {
        guard let outputPath = options.outputPath else {
            throw LumaError.unsupported("Folder export requires an output path.")
        }

        let pickedAssets = assets.filter { $0.userDecision == .picked }
        // 同一资产若出现在多组，保留在 `groups` 中**最先**出现的那组（flatMap 顺序）。
        let groupLookup = Dictionary(
            groups.flatMap { group in group.assets.map { ($0, group) } },
            uniquingKeysWith: { first, _ in first }
        )

        var exportedCount = 0
        var skippedCount = 0
        var failures: [ExportFailure] = []

        for asset in pickedAssets {
            // 仅按 ID 过滤"仅重试失败项"；nil 表示导全部 picked。
            if let only = options.onlyAssetIDs, !only.contains(asset.id) {
                skippedCount += 1
                continue
            }
            guard let sourceURL = asset.rawURL ?? asset.previewURL else {
                failures.append(ExportFailure(
                    assetID: asset.id,
                    fileName: asset.baseName,
                    reason: "找不到原图或预览文件"
                ))
                continue
            }

            do {
                let group = groupLookup[asset.id]
                let destinationFolder = try destinationDirectory(
                    for: asset,
                    group: group,
                    root: outputPath,
                    template: options.folderTemplate
                )
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

                let destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                if options.writeXmpSidecar {
                    try XMPWriter.writeSidecar(
                        for: asset,
                        group: group,
                        nextTo: destinationURL,
                        includeEditSuggestions: options.writeEditSuggestionsToXmp
                    )
                }

                exportedCount += 1
            } catch {
                failures.append(ExportFailure(
                    assetID: asset.id,
                    fileName: sourceURL.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }

        return ExportResult(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            destinationDescription: outputPath.path,
            failures: failures,
            albumDescription: nil,
            destinationURL: outputPath
        )
    }

    private func destinationDirectory(
        for asset: MediaAsset,
        group: PhotoGroup?,
        root: URL,
        template: FolderTemplate
    ) throws -> URL {
        switch template {
        case .byDate:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return root.appendingPathComponent(formatter.string(from: asset.metadata.captureDate), isDirectory: true)
        case .byGroup:
            let name = AppDirectories.sanitizePathComponent(group?.name ?? "Ungrouped")
            return root.appendingPathComponent(name, isDirectory: true)
        case .byRating:
            let rating = starRating(for: asset)
            return root.appendingPathComponent("\(rating)star", isDirectory: true)
        }
    }

    private func starRating(for asset: MediaAsset) -> Int {
        if let userRating = asset.userRating {
            return min(max(userRating, 1), 5)
        }

        let overall = asset.aiScore?.overall ?? 0
        switch overall {
        case 90...:
            return 5
        case 75..<90:
            return 4
        case 60..<75:
            return 3
        case 45..<60:
            return 2
        default:
            return 1
        }
    }
}
