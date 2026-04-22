import AppKit
import CoreGraphics
import Foundation
@preconcurrency import Photos

/// 从 Mac · 照片 App 读取本地缓存版本的 PHAsset 作为导入源。
///
/// 设计取舍（PRD v1）：
/// - **只读本地缓存版**：所有 PhotoKit 请求都会设置 `isNetworkAccessAllowed = false`，
///   不会触发 iCloud 下载，也不会撑爆磁盘。
/// - **不拉原图**：导入阶段只复制"显示版"作为 preview；原图等到导出阶段按需拉取。
/// - **resumeKey = PHAsset.localIdentifier**：用于导出回 Photos 后定位/删除原条目。
struct PhotosLibraryAdapter: ImportSourceAdapter {
    /// 用户自建相册（PHAssetCollectionType.album, .albumRegular）的 localIdentifier。
    let albumLocalIdentifier: String?
    let limit: Int
    /// 时间范围筛选（含起止），nil = 不限。
    let dateRange: ClosedRange<Date>?
    /// 智能相册类型（PhotoKit 内置），nil = 不指定。与 `albumLocalIdentifier` 互斥。
    let smartAlbumSubtype: PHAssetCollectionSubtype?
    /// 媒体类型筛选；与 planner 共用 NSPredicate 构造逻辑，确保两侧判定一致。
    let mediaTypeFilter: PhotosImportPlan.MediaTypeFilter
    /// enumerate 阶段排除的 PHAsset.localIdentifier 集合（用于去重当前 project 已存在）。
    let excludedLocalIdentifiers: Set<String>

    init(
        albumLocalIdentifier: String? = nil,
        limit: Int = 200,
        dateRange: ClosedRange<Date>? = nil,
        smartAlbumSubtype: PHAssetCollectionSubtype? = nil,
        mediaTypeFilter: PhotosImportPlan.MediaTypeFilter = .all,
        excludedLocalIdentifiers: Set<String> = []
    ) {
        self.albumLocalIdentifier = albumLocalIdentifier
        self.limit = limit
        self.dateRange = dateRange
        self.smartAlbumSubtype = smartAlbumSubtype
        self.mediaTypeFilter = mediaTypeFilter
        self.excludedLocalIdentifiers = excludedLocalIdentifiers
    }

    var displayName: String { "Mac · 照片 App" }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.finish()
        }
    }

    func enumerate() async throws -> [DiscoveredItem] {
        try await ensureAuthorization()

        let fetchOptions = makeFetchOptions(limit: limit)

        let assets: PHFetchResult<PHAsset>
        if let albumLocalIdentifier {
            let albums = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumLocalIdentifier],
                options: nil
            )
            guard let album = albums.firstObject else {
                throw LumaError.importFailed("找不到指定的相册：\(albumLocalIdentifier)")
            }
            assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        } else if let smartAlbumSubtype {
            let smartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: smartAlbumSubtype,
                options: nil
            )
            guard let album = smartAlbums.firstObject else {
                throw LumaError.importFailed("当前系统没有可用的智能相册。")
            }
            assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        } else {
            assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        }

        var candidates: [PHAsset] = []
        candidates.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            // 去重：跳过当前 project 已经导入过的 PHAsset。空集合时跳过 contains 检查避免无谓哈希。
            if !excludedLocalIdentifiers.isEmpty,
               excludedLocalIdentifiers.contains(asset.localIdentifier) {
                return
            }
            candidates.append(asset)
        }

        // PRD 约束：只读本地缓存版，跳过仅存在于 iCloud 的资产，避免暂停整个 import。
        let locallyAvailable = await filterLocallyAvailable(candidates)

        return locallyAvailable.map { Self.makeItem(from: $0) }
    }

    private func makeFetchOptions(limit: Int) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        options.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: PhotosImportPlanner.makePredicates(
                dateRange: dateRange,
                mediaTypeFilter: mediaTypeFilter
            )
        )
        return options
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        guard let asset = fetchAsset(forResumeKey: item.resumeKey) else { return nil }
        return await requestThumbnail(for: asset)
    }

    func copyPreview(_ item: DiscoveredItem, to destination: URL) async throws {
        guard let asset = fetchAsset(forResumeKey: item.resumeKey) else {
            throw LumaError.importFailed("找不到照片资产 \(item.baseName)。")
        }
        do {
            try await writeImageData(for: asset, to: destination)
        } catch let error as NSError where Self.isCloudOnlyError(error) {
            // 防御：enumerate 时已过滤云端独占资产，但用户在导入过程中可能改变缓存状态。
            // 此处吞掉错误，让该 asset 缺少 preview 文件，避免暂停整个 import；
            // 不再静默——发条 trace 出来，方便事后排查为什么后面显示层会回退到 PhotoKit/缩略图。
            RuntimeTrace.event(
                "photos_preview_skipped",
                category: "import",
                metadata: [
                    "reason": "cloud_only",
                    "resume_key": item.resumeKey,
                    "base_name": item.baseName,
                    "ns_error_code": String(error.code)
                ]
            )
        }
    }

    func copyOriginal(_ item: DiscoveredItem, to destination: URL) async throws {
        // v1：原图等到导出阶段按需拉。导入阶段不写 raw。
        _ = item; _ = destination
    }

    func copyAuxiliary(_ item: DiscoveredItem, to destination: URL) async throws {
        // v1：暂不复制 Live Photo 配对视频；导出回照片库时直接引用 PHAsset。
        _ = item; _ = destination
    }

    private func ensureAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let resolved: PHAuthorizationStatus
        if status == .notDetermined {
            resolved = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
        } else {
            resolved = status
        }
        guard resolved == .authorized || resolved == .limited else {
            throw LumaError.unsupported("Luma 没有获得「照片」访问权限。请在系统设置中允许后重试。")
        }
    }

    private func fetchAsset(forResumeKey key: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [key], options: nil).firstObject
    }

    private func requestThumbnail(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 400, height: 400),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    private func writeImageData(for asset: PHAsset, to destination: URL) async throws {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.version = .current

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error as NSError)
                } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                    continuation.resume(throwing: NSError(
                        domain: PHPhotosErrorDomain,
                        code: PHPhotosError.networkAccessRequired.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "该照片仅存在于 iCloud，本地暂无缓存。"]
                    ))
                } else {
                    continuation.resume(throwing: LumaError.importFailed("无法读取照片本地缓存。"))
                }
            }
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    /// 并发探测每个 PHAsset 是否本地可用（请求 1x1 fastFormat 缩略图，禁用网络）。
    private func filterLocallyAvailable(_ assets: [PHAsset]) async -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, PHAsset?).self) { group in
            for (index, asset) in assets.enumerated() {
                group.addTask {
                    let available = await Self.isLocallyAvailable(asset)
                    return (index, available ? asset : nil)
                }
            }
            var results = Array<PHAsset?>(repeating: nil, count: assets.count)
            for await (index, asset) in group {
                results[index] = asset
            }
            return results.compactMap { $0 }
        }
    }

    private static func isLocallyAvailable(_ asset: PHAsset) async -> Bool {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1, height: 1),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if image != nil {
                    continuation.resume(returning: true)
                } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                    continuation.resume(returning: false)
                } else if let error = info?[PHImageErrorKey] as? NSError, isCloudOnlyError(error) {
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: image != nil)
                }
            }
        }
    }

    private static func isCloudOnlyError(_ error: NSError) -> Bool {
        guard error.domain == PHPhotosErrorDomain else { return false }
        return error.code == PHPhotosError.networkAccessRequired.rawValue
    }

    private static func makeItem(from asset: PHAsset) -> DiscoveredItem {
        let identifier = asset.localIdentifier
        let captureDate = asset.creationDate ?? Date()
        let gps: Coordinate? = asset.location.map {
            Coordinate(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }
        let metadata = EXIFData(
            captureDate: captureDate,
            gpsCoordinate: gps,
            focalLength: nil,
            aperture: nil,
            shutterSpeed: nil,
            iso: nil,
            cameraModel: nil,
            lensModel: nil,
            imageWidth: asset.pixelWidth,
            imageHeight: asset.pixelHeight
        )
        let mediaType: MediaType = asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
        let token = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        let previewURL = URL(string: "luma-photos://\(token)/preview")!

        return DiscoveredItem(
            id: UUID(),
            resumeKey: identifier,
            baseName: baseName(for: asset),
            source: .photosLibrary(localIdentifier: identifier),
            previewFile: previewURL,
            rawFile: nil,
            auxiliaryFile: nil,
            depthData: false,
            metadata: metadata,
            mediaType: mediaType
        )
    }

    private static func baseName(for asset: PHAsset) -> String {
        if let resource = PHAssetResource.assetResources(for: asset).first {
            return URL(filePath: resource.originalFilename).deletingPathExtension().lastPathComponent
        }
        return "IMG_\(asset.localIdentifier.prefix(8))"
    }
}
