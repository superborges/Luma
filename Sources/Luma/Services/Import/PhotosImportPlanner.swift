import Foundation
@preconcurrency import Photos

/// PRD「新建 Import Session · Mac 照片 App」需要的辅助：
/// - 列出系统智能相册（最近添加 / 收藏 / 截图 / 自拍 / 实况照片 / 连拍）。
/// - 列出用户自建相册（按修改时间倒序，picker 弹出时一次性取）。
/// - 在用户调整时间范围 / 智能相册 / 用户相册 / 媒体类型 / 上限 / 去重开关后，**估算**总数与磁盘占用。
///
/// 估算策略说明：
/// - 真实大小因 iCloud 仅云端 / live 视频 / preview 解码尺寸而异，无法精确算。
/// - v1 使用经验值：每张 thumbnail ≈ 60 KB、preview ≈ 600 KB；不计原图（导出时按需拉）。
///   PRD 用户只需要"几百兆 / 几个 G"这一档判断，无需精度。
enum PhotosImportPlanner {
    struct SmartAlbumOption: Identifiable, Hashable {
        let id: PhotosImportPlan.SmartAlbum
        let title: String
        let systemImage: String
    }

    /// 用户相册的轻量描述。**故意不持有 `PHAssetCollection`** 引用——picker UI 只需要 ID + 标题。
    struct UserAlbumOption: Identifiable, Hashable {
        let id: String       // PHAssetCollection.localIdentifier
        let title: String
    }

    struct Estimate: Equatable {
        let totalAssetCount: Int
        let estimatedDiskBytes: Int64
        /// 含云端/不在本地的占比。仅供 UI 提示，不影响导入策略（PhotosLibraryAdapter 会过滤）。
        let cloudOnlyCount: Int
        /// 命中去重排除（已存在于当前 project）的数量。
        let dedupedSkippedCount: Int

        var prettyByteSize: String {
            ByteCountFormatter.string(fromByteCount: estimatedDiskBytes, countStyle: .file)
        }
    }

    static let perAssetEstimatedDiskBytes: Int64 = 60_000 + 600_000

    /// PRD 列出的常用智能相册组合。
    static let smartAlbums: [SmartAlbumOption] = [
        .init(id: .recentlyAdded, title: "最近添加", systemImage: "clock.arrow.circlepath"),
        .init(id: .favorites, title: "收藏", systemImage: "heart"),
        .init(id: .screenshots, title: "截图", systemImage: "camera.viewfinder"),
        .init(id: .selfPortraits, title: "自拍", systemImage: "person.crop.square"),
        .init(id: .livePhotos, title: "实况照片", systemImage: "livephoto"),
        .init(id: .bursts, title: "连拍", systemImage: "rectangle.stack"),
    ]

    /// 列出用户自建相册（`PHAssetCollectionType.album` + `.albumRegular`）。
    /// 按 `endDate`（即 PhotoKit "最近被修改"近似）倒序；endDate 缺失的排到末尾。
    /// 调用方需保证已获得 PhotoKit 读权限；权限未授予时返回空数组。
    @MainActor
    static func userAlbums() async -> [UserAlbumOption] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let options = PHFetchOptions()
        // PHAssetCollection 支持 sortDescriptors 的 key 不多；endDate 是相册最近活动的近似。
        // 无效 sort key 在某些环境下会被 PhotoKit 默默忽略；外层再做一次内存兜底排序。
        options.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: false)]

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )

        var albums: [UserAlbumOption] = []
        albums.reserveCapacity(collections.count)
        var withDate: [(UserAlbumOption, Date)] = []
        var withoutDate: [UserAlbumOption] = []

        collections.enumerateObjects { collection, _, _ in
            let title = (collection.localizedTitle?.isEmpty == false ? collection.localizedTitle! : "未命名相册")
            let option = UserAlbumOption(id: collection.localIdentifier, title: title)
            if let date = collection.endDate {
                withDate.append((option, date))
            } else {
                withoutDate.append(option)
            }
        }

        withDate.sort { $0.1 > $1.1 }
        albums.append(contentsOf: withDate.map(\.0))
        albums.append(contentsOf: withoutDate)
        return albums
    }

    /// 估算给定筛选条件下能匹配多少 PHAsset，以及大致占用。
    /// 调用方需保证已获得 PhotoKit 读权限；权限未授予时返回零估算。
    ///
    /// - Parameters:
    ///   - dateRange: 时间区间 AND 谓词；nil = 不限。
    ///   - smartAlbumSubtype: 锚定的智能相册；与 `userAlbumLocalIdentifier` 互斥（picker 保证）。
    ///   - userAlbumLocalIdentifier: 锚定的用户自建相册。
    ///   - mediaTypeFilter: 全部 / 仅静态 / 仅 Live。
    ///   - limit: PhotoKit fetchLimit；去重发生在 fetch 之后，可能让"实际可导入"小于 limit。
    ///   - excludedLocalIdentifiers: 当前 project 已经导入过的 PHAsset.localIdentifier 集合。
    @MainActor
    static func estimate(
        dateRange: ClosedRange<Date>?,
        smartAlbumSubtype: PHAssetCollectionSubtype?,
        userAlbumLocalIdentifier: String?,
        mediaTypeFilter: PhotosImportPlan.MediaTypeFilter,
        limit: Int,
        excludedLocalIdentifiers: Set<String>
    ) async -> Estimate {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return Estimate(totalAssetCount: 0, estimatedDiskBytes: 0, cloudOnlyCount: 0, dedupedSkippedCount: 0)
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        options.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: makePredicates(
                dateRange: dateRange,
                mediaTypeFilter: mediaTypeFilter
            )
        )

        let assets: PHFetchResult<PHAsset>
        if let userAlbumLocalIdentifier {
            let albums = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [userAlbumLocalIdentifier],
                options: nil
            )
            guard let album = albums.firstObject else {
                return Estimate(totalAssetCount: 0, estimatedDiskBytes: 0, cloudOnlyCount: 0, dedupedSkippedCount: 0)
            }
            assets = PHAsset.fetchAssets(in: album, options: options)
        } else if let smartAlbumSubtype {
            let smartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: smartAlbumSubtype,
                options: nil
            )
            guard let album = smartAlbums.firstObject else {
                return Estimate(totalAssetCount: 0, estimatedDiskBytes: 0, cloudOnlyCount: 0, dedupedSkippedCount: 0)
            }
            assets = PHAsset.fetchAssets(in: album, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: .image, options: options)
        }

        let total = assets.count
        var dedupeSkipped = 0
        var cloudOnly = 0

        // 去重：fetch 完一遍 enumerate；fetchLimit 已经限制总量在 limit 以内，O(n) 可接受。
        // 同时对前 sampleSize 张抽样云端率，避免大批量 fetchOptions 拿不到 isCloudPlaceholder。
        let sampleSize = min(30, total)
        for index in 0..<total {
            let asset = assets.object(at: index)
            if !excludedLocalIdentifiers.isEmpty,
               excludedLocalIdentifiers.contains(asset.localIdentifier) {
                dedupeSkipped += 1
            }
            if index < sampleSize,
               asset.value(forKey: "isCloudPlaceholder") as? Bool == true {
                cloudOnly += 1
            }
        }
        let scaledCloudOnly = sampleSize == 0 ? 0 : Int(Double(cloudOnly) / Double(sampleSize) * Double(total))
        let netCount = max(0, total - dedupeSkipped)
        let bytes = Int64(netCount) * perAssetEstimatedDiskBytes

        return Estimate(
            totalAssetCount: total,
            estimatedDiskBytes: bytes,
            cloudOnlyCount: scaledCloudOnly,
            dedupedSkippedCount: dedupeSkipped
        )
    }

    /// 共享给 adapter / planner 的 NSPredicate 构造逻辑，确保两侧对"哪些 PHAsset 算一张"判定一致。
    static func makePredicates(
        dateRange: ClosedRange<Date>?,
        mediaTypeFilter: PhotosImportPlan.MediaTypeFilter
    ) -> [NSPredicate] {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        ]

        // mediaSubtypes 是位掩码；photoLive = 1<<3 = 8。
        let liveMask = PHAssetMediaSubtype.photoLive.rawValue
        switch mediaTypeFilter {
        case .all:
            break
        case .staticOnly:
            predicates.append(NSPredicate(
                format: "(mediaSubtypes & %d) == 0",
                liveMask
            ))
        case .liveOnly:
            predicates.append(NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                liveMask
            ))
        }

        if let dateRange {
            predicates.append(NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                dateRange.lowerBound as NSDate,
                dateRange.upperBound as NSDate
            ))
        }

        return predicates
    }
}
