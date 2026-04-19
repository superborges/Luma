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
    let coverImageURL: URL?
    let state: State
    let isCurrent: Bool

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

    /// Whether the expedition can be opened in the main workspace (Culling).
    var isOpenable: Bool {
        if case .ready = state { return true }
        return false
    }
}
