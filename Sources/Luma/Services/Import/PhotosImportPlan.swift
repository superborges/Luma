import Foundation
@preconcurrency import Photos

/// PRD「Mac 照片 App」导入 picker 用户最终确认的方案。
///
/// ## 设计取舍（macOS 26 / SwiftUI 7.3 / Swift 6.2 踩坑总结）
///
/// 1. **本结构体里的字段只能用纯 Swift 类型**——不要直接持有 `PHAssetCollectionSubtype`
///    这类 ObjC bridged enum。原因：SwiftUI 7.3 / AttributeGraph 在分析依赖此 plan 的
///    view tree 类型布局时，会递归遍历每个字段的 metadata；ObjC bridged enum 的
///    protocol conformance 查表会让 `AG::LayoutDescriptor::make_layout` 无限递归并崩溃。
///    所以这里用本地 `SmartAlbum` enum 镜像 PhotoKit 的智能相册类型。
///
/// 2. **`SmartAlbum` 自身不暴露任何 PhotoKit 类型**——没有 `var photoKitSubtype:
///    PHAssetCollectionSubtype` 这种 method。桥接放在 free function `photoKitSubtype(for:)`
///    里，让 enum 的 metadata 完全干净，不与 ObjC 类型有任何 protocol witness 关联。
///
/// 3. **`Identifiable`**：`.sheet(item:)` 需要稳定 id；id 在 `presentPhotosImportPicker`
///    时生成一次，跟随 plan 的整个生命周期不变（plan 字段修改不会换 id），避免 SwiftUI
///    误把修改后的 plan 当成新 sheet 重建。
///
/// ## v2 维度（2026-04-22）
///
/// 在原有「时间预设 + 智能相册 + 上限」基础上叠加：
/// - 时间预设支持 `.custom(start, end)` 自定义区间。
/// - 相册维度可选**用户自建相册**（`userAlbumLocalIdentifier`），与时间区间 AND 叠加。
///   智能相册和用户相册互斥（同一时刻只能选其中一个，等价于 PhotoKit 一次 fetch 只能锚一个集合）。
/// - 媒体类型：全部（含 Live）/ 仅静态 / 仅 Live。
/// - 去重：跳过当前 project 内已经导入过的 PHAsset.localIdentifier。
struct PhotosImportPlan: Equatable, Identifiable {
    let id: UUID

    enum DatePreset: Equatable {
        case last7
        case last30
        case last90
        case allTime
        case custom(start: Date, end: Date)

        var label: String {
            switch self {
            case .last7: return "最近 7 天"
            case .last30: return "最近 30 天"
            case .last90: return "最近 90 天"
            case .allTime: return "不限时间"
            case .custom(let start, let end):
                let f = DateFormatter()
                f.locale = Locale(identifier: "zh_CN")
                f.dateFormat = "yyyy-MM-dd"
                return "\(f.string(from: start)) ~ \(f.string(from: end))"
            }
        }

        func resolvedRange(now: Date = .now) -> ClosedRange<Date>? {
            let calendar = Calendar.current
            switch self {
            case .last7:
                return calendar.date(byAdding: .day, value: -7, to: now).map { $0...now }
            case .last30:
                return calendar.date(byAdding: .day, value: -30, to: now).map { $0...now }
            case .last90:
                return calendar.date(byAdding: .day, value: -90, to: now).map { $0...now }
            case .allTime:
                return nil
            case .custom(let start, let end):
                let lower = min(start, end)
                let upper = max(start, end)
                return lower...upper
            }
        }
    }

    /// 与 PhotoKit `PHAssetCollectionSubtype` 一一对应的纯 Swift enum；
    /// 只罗列我们 picker 暴露给用户的子集。**故意不带任何引用 PhotoKit 类型的 method
    /// /computed property**——桥接见 `photoKitSubtype(for:)`。
    enum SmartAlbum: String, CaseIterable, Identifiable, Hashable {
        case recentlyAdded
        case favorites
        case screenshots
        case selfPortraits
        case livePhotos
        case bursts

        var id: String { rawValue }
    }

    /// 媒体类型筛选。v1 资产管线只处理 `.photo` / `.livePhoto`，不含视频。
    enum MediaTypeFilter: String, CaseIterable, Identifiable, Hashable {
        case all          // 全部图像（含 Live）
        case staticOnly   // 仅静态照片（不含 Live）
        case liveOnly     // 仅 Live Photo

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部（含 Live）"
            case .staticOnly: return "仅静态"
            case .liveOnly: return "仅 Live"
            }
        }
    }

    var datePreset: DatePreset
    var smartAlbum: SmartAlbum?
    /// 用户自建相册的 PHAssetCollection.localIdentifier；与 `smartAlbum` 互斥（picker UI 保证）。
    var userAlbumLocalIdentifier: String?
    /// 用于显示（estimate / displayName）的相册名称缓存；adapter 不依赖。
    var userAlbumTitle: String?
    var mediaTypeFilter: MediaTypeFilter
    var limit: Int
    /// 跳过当前 project 已经导入过的 PHAsset；UI 上勾选后会随 plan 传到 estimator/adapter。
    var dedupeAgainstCurrentProject: Bool

    var dateRange: ClosedRange<Date>? {
        datePreset.resolvedRange()
    }

    /// 给 PhotoKit 调用方使用的桥接值；不参与 SwiftUI 视图层。
    var smartAlbumSubtype: PHAssetCollectionSubtype? {
        smartAlbum.map(photoKitSubtype(for:))
    }

    var displayName: String {
        var parts: [String] = ["Mac · 照片 App"]
        if let smartAlbum,
           let option = PhotosImportPlanner.smartAlbums.first(where: { $0.id == smartAlbum }) {
            parts.append(option.title)
        } else if let userAlbumTitle {
            parts.append(userAlbumTitle)
        } else {
            parts.append("全部图片")
        }
        parts.append(datePreset.label)
        if mediaTypeFilter != .all {
            parts.append(mediaTypeFilter.label)
        }
        parts.append("≤ \(limit) 张")
        return parts.joined(separator: " · ")
    }

    /// 每次 picker 弹出时调一次，拿到一个全新 id 的 plan；不要做成 `static let`，否则
    /// 多次 present/dismiss 会复用同一个 id，干扰 `.sheet(item:)` 的生命周期判断。
    static func makeDefault() -> PhotosImportPlan {
        PhotosImportPlan(
            id: UUID(),
            datePreset: .last30,
            smartAlbum: nil,
            userAlbumLocalIdentifier: nil,
            userAlbumTitle: nil,
            mediaTypeFilter: .all,
            limit: 500,
            dedupeAgainstCurrentProject: true
        )
    }
}

/// SmartAlbum → PhotoKit 桥接。**故意写成 free function**：让 `SmartAlbum` 的 type metadata
/// 不引用 `PHAssetCollectionSubtype`，避免 SwiftUI/AttributeGraph 在分析视图依赖时把
/// ObjC bridged enum 拖进 layout 计算路径（历史已踩过坑，参见 PhotosImportPlan 注释 §1/§2）。
func photoKitSubtype(for smartAlbum: PhotosImportPlan.SmartAlbum) -> PHAssetCollectionSubtype {
    switch smartAlbum {
    case .recentlyAdded: return .smartAlbumRecentlyAdded
    case .favorites: return .smartAlbumFavorites
    case .screenshots: return .smartAlbumScreenshots
    case .selfPortraits: return .smartAlbumSelfPortraits
    case .livePhotos: return .smartAlbumLivePhotos
    case .bursts: return .smartAlbumBursts
    }
}

/// PhotosImportPicker 的输出通道。当前由 AppKit 版 picker（`AppKitPhotosImportPicker`）
/// 同步返回；历史上 SwiftUI 版本通过 `@Binding` 上报，已废弃。
enum PhotosImportPickerOutcome: Equatable {
    case cancelled
    case confirmed(PhotosImportPlan)
}
