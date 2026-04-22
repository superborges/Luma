import Foundation
@preconcurrency import Photos

/// 把源 = `照片 App (photosLibrary)` 的 picked 原图按需拉到项目本地 raw/ 目录。
///
/// 选片阶段为"省流"只缓存了 preview；当用户把这些 picked 导出到 Folder / Lightroom 等
/// **需要原图二进制** 的目标时，必须先把原图从 PhotoKit / iCloud 拉下来再交给 Exporter。
/// 拉取阶段允许走网络（`isNetworkAccessAllowed = true`），同时把进度回调出来给 UI。
struct PhotosOriginalFetcher {
    typealias ProgressHandler = @Sendable (_ completed: Int, _ total: Int, _ currentName: String?) -> Void

    /// 把 `pickedAssets` 中源 = `.photosLibrary` 且本地尚无 `rawURL` 的资产从 PhotoKit 拉到 `rawDirectory`。
    /// 返回新填好的 `rawURL` 字典（`assetID -> URL`），调用方据此回写 `MediaAsset.rawURL`。
    static func fetchOriginals(
        for pickedAssets: [MediaAsset],
        rawDirectory: URL,
        progress: ProgressHandler? = nil
    ) async throws -> [UUID: URL] {
        let needsFetch = pickedAssets.compactMap { asset -> (MediaAsset, String)? in
            guard asset.rawURL == nil else { return nil }
            if case .photosLibrary(let id) = asset.source, !id.isEmpty {
                return (asset, id)
            }
            return nil
        }
        guard !needsFetch.isEmpty else { return [:] }

        try FileManager.default.createDirectory(
            at: rawDirectory,
            withIntermediateDirectories: true
        )

        let identifiers = needsFetch.map(\.1)
        let phAssets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var phByID: [String: PHAsset] = [:]
        phAssets.enumerateObjects { asset, _, _ in
            phByID[asset.localIdentifier] = asset
        }

        var output: [UUID: URL] = [:]
        let total = needsFetch.count
        var completed = 0

        for (asset, identifier) in needsFetch {
            guard let phAsset = phByID[identifier] else {
                completed += 1
                progress?(completed, total, asset.baseName)
                RuntimeTrace.event(
                    "photos_original_fetch_missing",
                    category: "export",
                    metadata: [
                        "asset_id": asset.id.uuidString,
                        "ph_local_identifier": identifier
                    ]
                )
                continue
            }

            let destination = rawDirectory.appendingPathComponent(originalFileName(for: phAsset, fallback: asset.baseName))
            do {
                try await writeOriginalData(for: phAsset, to: destination)
                output[asset.id] = destination
                RuntimeTrace.event(
                    "photos_original_fetched",
                    category: "export",
                    metadata: [
                        "asset_id": asset.id.uuidString,
                        "destination": destination.lastPathComponent
                    ]
                )
            } catch {
                RuntimeTrace.error(
                    "photos_original_fetch_failed",
                    category: "export",
                    metadata: [
                        "asset_id": asset.id.uuidString,
                        "message": error.localizedDescription
                    ]
                )
            }
            completed += 1
            progress?(completed, total, asset.baseName)
        }
        return output
    }

    private static func originalFileName(for asset: PHAsset, fallback: String) -> String {
        if let resource = PHAssetResource.assetResources(for: asset).first {
            return resource.originalFilename
        }
        return "\(fallback).jpg"
    }

    private static func writeOriginalData(for asset: PHAsset, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let resource = PHAssetResource.assetResources(for: asset).first { $0.type == .photo }
            ?? PHAssetResource.assetResources(for: asset).first
        guard let resource else {
            throw LumaError.importFailed("PhotoKit 资产没有可用资源。")
        }

        let manager = PHAssetResourceManager.default()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.writeData(for: resource, toFile: destination, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
