import Foundation
@preconcurrency import Photos

/// 「Mac · 照片 App」导入方案 — 基于月份的选择模型。
///
/// v2 重构：去掉相册/智能相册维度，改为纯月份选择。
/// 用户在月份网格中勾选要导入的月份，每个月份显示照片数和预估容量。
struct PhotosImportPlan: Equatable, Identifiable {
    let id: UUID

    /// 代表一个日历月。
    struct MonthSlot: Equatable, Hashable, Comparable {
        let year: Int
        let month: Int

        var label: String {
            let m = String(format: "%d", month)
            return "\(year)年\(m)月"
        }

        var dateRange: ClosedRange<Date> {
            let calendar = Calendar.current
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
            return start...end
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.year, lhs.month) < (rhs.year, rhs.month)
        }
    }

    /// 媒体类型筛选。
    enum MediaTypeFilter: String, CaseIterable, Identifiable, Hashable {
        case all
        case staticOnly
        case liveOnly

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部（含 Live）"
            case .staticOnly: return "仅静态"
            case .liveOnly: return "仅 Live"
            }
        }
    }

    var selectedMonths: [MonthSlot]
    var mediaTypeFilter: MediaTypeFilter
    var dedupeAgainstCurrentProject: Bool

    /// 每个选中月份的独立日期范围（按时间正序）。
    var dateRanges: [ClosedRange<Date>] {
        selectedMonths.sorted().map(\.dateRange)
    }

    /// 向后兼容：所有选中月份的并集范围。空选择返回 nil。
    var dateRange: ClosedRange<Date>? {
        let sorted = selectedMonths.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        return first.dateRange.lowerBound...last.dateRange.upperBound
    }

    var limit: Int { 50_000 }

    var displayName: String {
        var parts: [String] = ["Mac · 照片"]
        let sorted = selectedMonths.sorted()
        if sorted.count == 1 {
            parts.append(sorted[0].label)
        } else if sorted.count > 1 {
            parts.append("\(sorted.first!.label)–\(sorted.last!.label) · \(sorted.count)个月")
        }
        if mediaTypeFilter != .all {
            parts.append(mediaTypeFilter.label)
        }
        return parts.joined(separator: " · ")
    }

    static func makeDefault() -> PhotosImportPlan {
        PhotosImportPlan(
            id: UUID(),
            selectedMonths: [],
            mediaTypeFilter: .all,
            dedupeAgainstCurrentProject: true
        )
    }
}

/// Picker 输出。
enum PhotosImportPickerOutcome: Equatable {
    case cancelled
    case confirmed(PhotosImportPlan)
}
