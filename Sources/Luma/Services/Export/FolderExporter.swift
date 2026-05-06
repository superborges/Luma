import Foundation
import Photos

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
        var groupSequenceCounters: [UUID: Int] = [:]

        for asset in pickedAssets {
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

                let groupID = group?.id ?? UUID()
                let seq = (groupSequenceCounters[groupID] ?? 0) + 1
                groupSequenceCounters[groupID] = seq

                let resolvedName = FileNamingResolver.resolvedFileName(
                    originalName: sourceURL.lastPathComponent,
                    captureDate: asset.metadata.captureDate,
                    groupName: group?.name ?? "Ungrouped",
                    sequenceInGroup: seq,
                    rule: options.fileNamingRule,
                    template: options.customNamingTemplate
                )
                let candidateURL = destinationFolder.appendingPathComponent(resolvedName)
                let destinationURL = FileNamingResolver.uniqueURL(for: candidateURL, in: destinationFolder)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                let shouldWriteXMP = options.writeXmpSidecar || options.writeEditSuggestionsToXmp
                if shouldWriteXMP {
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

    // MARK: - MasterAsset Overload

    func export(
        masterAssets: [MasterAsset],
        groups: [PhotoGroupWithAssets],
        ratings: [UUID: Int] = [:],
        options: ExportOptions,
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async throws -> ExportResult {
        guard let outputPath = options.outputPath else {
            throw LumaError.unsupported("Folder export requires an output path.")
        }

        let groupLookup: [UUID: PhotoGroupWithAssets] = Dictionary(
            groups.flatMap { group in group.assets.map { ($0.assetId, group) } },
            uniquingKeysWith: { first, _ in first }
        )

        var exportedCount = 0
        var skippedCount = 0
        var failures: [ExportFailure] = []
        var groupSequenceCounters: [UUID: Int] = [:]
        let total = masterAssets.count

        for (index, asset) in masterAssets.enumerated() {
            onProgress?(index, total, asset.baseName)

            if let only = options.onlyAssetIDs, !only.contains(asset.id) {
                skippedCount += 1
                continue
            }

            do {
                let group = groupLookup[asset.id]
                let destFolder = try masterAssetDestinationDirectory(
                    for: asset, group: group, ratings: ratings,
                    root: outputPath, template: options.folderTemplate
                )
                try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

                let groupID = group?.id ?? UUID()
                let seq = (groupSequenceCounters[groupID] ?? 0) + 1
                groupSequenceCounters[groupID] = seq

                let sourceURL = try await resolveSourceFile(for: asset, destinationFolder: destFolder)
                let originalName = sourceURL.lastPathComponent
                let captureDate = asset.captureDate ?? .distantPast

                let resolvedName = FileNamingResolver.resolvedFileName(
                    originalName: originalName,
                    captureDate: captureDate,
                    groupName: group?.name ?? "Ungrouped",
                    sequenceInGroup: seq,
                    rule: options.fileNamingRule,
                    template: options.customNamingTemplate
                )
                let candidateURL = destFolder.appendingPathComponent(resolvedName)
                let destinationURL = FileNamingResolver.uniqueURL(for: candidateURL, in: destFolder)

                if sourceURL.deletingLastPathComponent() == destFolder {
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                } else {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                }

                if options.writeXmpSidecar {
                    let rating = ratings[asset.id] ?? masterAssetStarRating(for: asset, ratings: ratings)
                    try XMPWriter.writeSidecar(
                        for: asset,
                        groupName: group?.name,
                        rating: rating,
                        nextTo: destinationURL
                    )
                }

                exportedCount += 1
            } catch {
                failures.append(ExportFailure(
                    assetID: asset.id,
                    fileName: asset.baseName,
                    reason: error.localizedDescription
                ))
            }
        }
        onProgress?(total, total, "")

        return ExportResult(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            destinationDescription: outputPath.path,
            failures: failures,
            albumDescription: nil,
            destinationURL: outputPath
        )
    }

    private func masterAssetDestinationDirectory(
        for asset: MasterAsset,
        group: PhotoGroupWithAssets?,
        ratings: [UUID: Int],
        root: URL,
        template: FolderTemplate
    ) throws -> URL {
        switch template {
        case .byDate:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = asset.captureDate.map { formatter.string(from: $0) } ?? "Unknown-Date"
            return root.appendingPathComponent(dateStr, isDirectory: true)
        case .byGroup:
            let name = AppDirectories.sanitizePathComponent(group?.name ?? "Ungrouped")
            return root.appendingPathComponent(name, isDirectory: true)
        case .byRating:
            let rating = masterAssetStarRating(for: asset, ratings: ratings)
            return root.appendingPathComponent("\(rating)star", isDirectory: true)
        }
    }

    private func masterAssetStarRating(for asset: MasterAsset, ratings: [UUID: Int]) -> Int {
        if let provided = ratings[asset.id] {
            return min(max(provided, 1), 5)
        }
        return 3
    }

    private func resolveSourceFile(for asset: MasterAsset, destinationFolder: URL) async throws -> URL {
        if let url = asset.rawURL ?? asset.previewURL ?? asset.existingImageFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        guard asset.storageMode == .externalReference, let extId = asset.externalIdentifier else {
            throw LumaError.importFailed("找不到资产源文件：\(asset.baseName)")
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [extId], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw LumaError.importFailed("无法从「照片」获取资产：\(asset.baseName)")
        }

        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto })
                ?? resources.first else {
            throw LumaError.importFailed("无法获取图像资源：\(asset.baseName)")
        }

        let ext = resource.originalFilename.split(separator: ".").last.map(String.init) ?? "jpg"
        let tempURL = destinationFolder.appendingPathComponent("_photokit_\(asset.id.uuidString).\(ext)")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: tempURL, options: opts) { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }

        return tempURL
    }
}
