import Foundation

// MARK: - Strategy

/// 三档评分策略：决定本次批量评分调用云端的强度。
enum ScoringStrategy: String, Codable, Hashable, CaseIterable, Sendable {
    /// 仅本地 Core ML，不发任何云端请求（与 V1 当前行为一致）。
    case local
    /// primary 全量评分 + premiumFallback 仅对 overall ≥ 70 的 Top 20% 精评。
    case balanced
    /// primary 全量 + premiumFallback 全量精评 + 修图建议。
    case best

    var displayName: String {
        switch self {
        case .local: return "省钱（仅本地）"
        case .balanced: return "均衡"
        case .best: return "最佳质量"
        }
    }

    var description: String {
        switch self {
        case .local: return "不调用云端模型，使用本地 Core ML 已识别的废片标签。"
        case .balanced: return "先用便宜模型给所有照片打分，再用贵模型对 Top 20% 做精评。"
        case .best: return "贵模型对全量照片精评，并生成修图建议。"
        }
    }
}

// MARK: - Status

/// 一次批量评分的整体状态，写入 session 元数据。
enum ScoringStatus: String, Codable, Hashable, Sendable {
    case idle
    case running
    case paused
    case completed
    case failed
}

/// 单组评分的执行状态。失败的组可单独重试。
enum GroupScoringStatus: String, Codable, Hashable, Sendable {
    case pending
    case running
    case completed
    case failed
}

// MARK: - Job persistence

/// 持久化的批量评分任务，落盘为 `<projectDir>/scoring_job.json`，支持断点续传。
struct ScoringJob: Codable, Hashable, Sendable {
    let id: UUID
    let strategy: ScoringStrategy
    /// primary 模型 ID（运行时通过 ModelConfigStore 解析具体配置）。
    let primaryModelID: UUID
    /// premiumFallback 模型 ID；策略为 `.local` 时为 nil。
    let premiumModelID: UUID?
    var startedAt: Date
    var totalGroups: Int
    var status: ScoringStatus
    var pausedReason: String?

    /// 每组的执行状态。键 = `PhotoGroup.id`。
    var groupStatuses: [UUID: GroupScoringStatus]

    /// 累计 token 与 USD（来自 BudgetTracker）。
    var budget: BudgetSnapshot

    /// 完成的组数（status == .completed）。
    var completedGroups: Int {
        groupStatuses.values.filter { $0 == .completed }.count
    }

    /// 失败的组数（status == .failed）。
    var failedGroups: Int {
        groupStatuses.values.filter { $0 == .failed }.count
    }

    /// 待处理的组数（status == .pending 或 .running）。
    var remainingGroups: Int {
        groupStatuses.values.filter { $0 == .pending || $0 == .running }.count
    }
}

// MARK: - Budget

/// 当前批次累计 token 与 USD 的快照。BudgetTracker 内部状态的 immutable 拷贝。
struct BudgetSnapshot: Codable, Hashable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var usd: Double
    var thresholdUSD: Double

    static let zero = BudgetSnapshot(inputTokens: 0, outputTokens: 0, usd: 0, thresholdUSD: 5.0)

    var exceededThreshold: Bool { usd >= thresholdUSD }

    var prettyUSD: String {
        // 显示时保留 2-4 位小数；超过 1 美元仅保留 2 位。
        if usd >= 1 {
            return String(format: "$%.2f", usd)
        } else if usd >= 0.01 {
            return String(format: "$%.3f", usd)
        } else {
            return String(format: "$%.4f", usd)
        }
    }
}

// MARK: - Progress event

/// BatchScheduler 通过 AsyncStream 推送的进度事件。
struct ScoringProgressEvent: Codable, Hashable, Sendable {
    let jobID: UUID
    let totalGroups: Int
    let completedGroups: Int
    let failedGroups: Int
    let currentGroupName: String?
    let currentModelDisplayName: String?
    let budget: BudgetSnapshot
    let status: ScoringStatus
    let message: String?

    var progressFraction: Double {
        guard totalGroups > 0 else { return 0 }
        return Double(completedGroups) / Double(totalGroups)
    }
}
