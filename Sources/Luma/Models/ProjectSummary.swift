import Foundation

struct ProjectSummary: Identifiable, Hashable {
    enum State: Hashable {
        case ready(assetCount: Int, groupCount: Int)
        case unavailable(reason: String)
    }

    let id: URL
    let directory: URL
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let coverImageURL: URL?
    let state: State
    let isCurrent: Bool
    /// 选片完成进度（已 picked + rejected）/ 总数；total = 0 时表示尚未导入。
    let decidedCount: Int
    let totalAssetCount: Int
    /// 至少一次成功导出过；若失败 ExportJob 也算"导出过"，按 status 区分。
    let lastExportedAt: Date?
    let exportJobCount: Int
    /// 软归档：仅在首页列表里靠后 + 弱化展示。
    let isArchived: Bool

    var assetCountDescription: String {
        switch state {
        case .ready(let assetCount, _):
            return "\(assetCount) 张"
        case .unavailable:
            return "无法读取"
        }
    }

    var groupCountDescription: String {
        switch state {
        case .ready(_, let groupCount):
            return "\(groupCount) 组"
        case .unavailable:
            return "Manifest 异常"
        }
    }

    /// Whether the session can be opened in the main workspace (Culling).
    var isOpenable: Bool {
        if case .ready = state { return true }
        return false
    }

    /// 选片是否全部决策完成。
    var isCullingComplete: Bool {
        totalAssetCount > 0 && decidedCount >= totalAssetCount
    }

    /// 决策进度比例 0~1。
    var decisionFraction: Double {
        guard totalAssetCount > 0 else { return 0 }
        return Double(decidedCount) / Double(totalAssetCount)
    }

    /// 单行状态摘要：「100 张 · 已决策 80（80%） · 已导出 2 次 · 4/19 18:12」
    var stateSummary: String {
        switch state {
        case .ready(let assetCount, let groupCount):
            var parts: [String] = ["\(assetCount) 张 · \(groupCount) 组"]
            if totalAssetCount > 0 {
                let percent = Int(decisionFraction * 100)
                parts.append("已决策 \(decidedCount)/\(totalAssetCount)（\(percent)%）")
            }
            if exportJobCount > 0 {
                parts.append("已导出 \(exportJobCount) 次")
            }
            return parts.joined(separator: " · ")
        case .unavailable(let reason):
            return "无法读取：\(reason)"
        }
    }
}

enum SessionListSort: String, CaseIterable, Identifiable {
    /// 按上次修改（updatedAt）降序，含选片或导出后的更新；默认。
    case lastModified
    /// 创建时间降序。
    case created
    /// 名称升序。
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastModified: return "最近修改"
        case .created: return "创建时间"
        case .name: return "名称"
        }
    }

    func sort(_ summaries: [ProjectSummary]) -> [ProjectSummary] {
        // 归档的永远靠后；同段内再按 sort key 排。
        summaries.sorted { lhs, rhs in
            if lhs.isArchived != rhs.isArchived {
                return !lhs.isArchived
            }
            switch self {
            case .lastModified:
                return lhs.updatedAt > rhs.updatedAt
            case .created:
                return lhs.createdAt > rhs.createdAt
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
