import Foundation
@preconcurrency import Photos

/// 照片导入估算器 — 按月份统计照片数和预估容量。
enum PhotosImportPlanner {

    struct Estimate: Equatable {
        let totalAssetCount: Int
        let estimatedDiskBytes: Int64
        let cloudOnlyCount: Int
        let dedupedSkippedCount: Int

        var prettyByteSize: String {
            ByteCountFormatter.string(fromByteCount: estimatedDiskBytes, countStyle: .file)
        }
    }

    /// 每月的照片统计信息。
    struct MonthStats: Equatable {
        let slot: PhotosImportPlan.MonthSlot
        let photoCount: Int
        let estimatedBytes: Int64
        let previouslyImportedCount: Int

        var prettyByteSize: String {
            ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
        }

        var isLargeMonth: Bool { photoCount >= 500 }
        var hasPreviousImport: Bool { previouslyImportedCount > 0 }
    }

    static let perAssetEstimatedDiskBytes: Int64 = 60_000 + 600_000

    /// 扫描图库，按月份统计照片数。
    /// 不标 @MainActor，在后台线程执行以避免阻塞 UI。
    ///
    /// 性能策略：不加载任何 PHAsset 对象。
    /// 1. 取最新/最旧照片的日期（各 fetchLimit=1）确定月份范围。
    /// 2. 对每个月做一次 count-only 查询（`PHFetchResult.count` 底层是 SQLite COUNT，O(1)）。
    /// 3. 已导入月份计数由调用方从自身 asset 列表算好后传入，不走 PhotoKit。
    static func monthlyStats(
        previouslyImportedByMonth: [String: Int] = [:],
        mediaTypeFilter: PhotosImportPlan.MediaTypeFilter = .all
    ) async -> [MonthStats] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let basePreds = makePredicates(dateRanges: [], mediaTypeFilter: mediaTypeFilter)

        guard let newestDate = fetchBoundaryDate(ascending: false, predicates: basePreds),
              let oldestDate = fetchBoundaryDate(ascending: true, predicates: basePreds) else {
            return []
        }

        let calendar = Calendar.current
        let months = generateMonthSlots(from: oldestDate, to: newestDate, calendar: calendar)

        var results: [MonthStats] = []
        results.reserveCapacity(months.count)

        for slot in months {
            let range = slot.dateRange
            var preds = basePreds
            preds.append(NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                range.lowerBound as NSDate,
                range.upperBound as NSDate
            ))
            let opts = PHFetchOptions()
            opts.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
            let count = PHAsset.fetchAssets(with: .image, options: opts).count
            guard count > 0 else { continue }

            let key = "\(slot.year)-\(slot.month)"
            results.append(MonthStats(
                slot: slot,
                photoCount: count,
                estimatedBytes: Int64(count) * perAssetEstimatedDiskBytes,
                previouslyImportedCount: previouslyImportedByMonth[key] ?? 0
            ))
        }

        return results.sorted { $0.slot > $1.slot }
    }

    /// 取图库中最新或最旧一张照片的 creationDate。fetchLimit=1，极快。
    private static func fetchBoundaryDate(ascending: Bool, predicates: [NSPredicate]) -> Date? {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: ascending)]
        opts.fetchLimit = 1
        opts.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return PHAsset.fetchAssets(with: .image, options: opts).firstObject?.creationDate
    }

    /// 生成 [oldest...newest] 覆盖的所有月份 slot，按时间正序。
    private static func generateMonthSlots(
        from oldest: Date,
        to newest: Date,
        calendar: Calendar
    ) -> [PhotosImportPlan.MonthSlot] {
        let startComps = calendar.dateComponents([.year, .month], from: oldest)
        let endComps = calendar.dateComponents([.year, .month], from: newest)
        guard var y = startComps.year, var m = startComps.month,
              let ey = endComps.year, let em = endComps.month else { return [] }

        var slots: [PhotosImportPlan.MonthSlot] = []
        while (y, m) <= (ey, em) {
            slots.append(.init(year: y, month: m))
            m += 1
            if m > 12 { m = 1; y += 1 }
        }
        return slots
    }

    /// 构造 PhotoKit NSPredicate。支持多月份日期范围（OR 组合）。
    static func makePredicates(
        dateRanges: [ClosedRange<Date>],
        mediaTypeFilter: PhotosImportPlan.MediaTypeFilter
    ) -> [NSPredicate] {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        ]

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

        if !dateRanges.isEmpty {
            if dateRanges.count == 1 {
                let r = dateRanges[0]
                predicates.append(NSPredicate(
                    format: "creationDate >= %@ AND creationDate <= %@",
                    r.lowerBound as NSDate,
                    r.upperBound as NSDate
                ))
            } else {
                let rangePreds = dateRanges.map { r in
                    NSPredicate(
                        format: "creationDate >= %@ AND creationDate <= %@",
                        r.lowerBound as NSDate,
                        r.upperBound as NSDate
                    )
                }
                predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: rangePreds))
            }
        }

        return predicates
    }

    /// 向后兼容：单一日期范围重载。
    static func makePredicates(
        dateRange: ClosedRange<Date>?,
        mediaTypeFilter: PhotosImportPlan.MediaTypeFilter
    ) -> [NSPredicate] {
        makePredicates(
            dateRanges: dateRange.map { [$0] } ?? [],
            mediaTypeFilter: mediaTypeFilter
        )
    }
}
