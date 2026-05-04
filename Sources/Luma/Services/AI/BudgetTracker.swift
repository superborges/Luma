import Foundation

/// 当前批次评分的费用追踪。线程安全。
///
/// 设计取舍：
/// - actor 而非 class + lock：UI 与 BatchScheduler 同时读写，actor 保证串行访问
/// - 阈值检查在每组 add 后即时计算并通过 `superThresholdStream` 通知；
///   不阻塞调用方，便于 Coordinator 决定暂停时机
/// - `snapshot()` 是不可变值类型；UI 只消费 snapshot，不持有 actor
actor BudgetTracker {
    private(set) var inputTokens: Int = 0
    private(set) var outputTokens: Int = 0
    private(set) var usd: Double = 0
    private(set) var thresholdUSD: Double

    /// 当 `usd >= thresholdUSD` 跨过阈值时（仅首次跨过触发一次）发出 BudgetSnapshot。
    private let thresholdContinuation: AsyncStream<BudgetSnapshot>.Continuation
    let thresholdCrossedStream: AsyncStream<BudgetSnapshot>

    private var thresholdCrossed: Bool = false

    init(thresholdUSD: Double = 5.0) {
        self.thresholdUSD = max(0, thresholdUSD)
        var continuationRef: AsyncStream<BudgetSnapshot>.Continuation!
        self.thresholdCrossedStream = AsyncStream { continuationRef = $0 }
        self.thresholdContinuation = continuationRef
    }

    deinit {
        thresholdContinuation.finish()
    }

    /// 累加一次调用消耗。返回最新 snapshot。
    @discardableResult
    func add(usage: TokenUsage, cost: Double) -> BudgetSnapshot {
        inputTokens += max(0, usage.inputTokens)
        outputTokens += max(0, usage.outputTokens)
        usd += max(0, cost)
        let snap = currentSnapshot()
        if !thresholdCrossed, snap.exceededThreshold {
            thresholdCrossed = true
            thresholdContinuation.yield(snap)
        }
        return snap
    }

    /// 仅外部观察。
    func snapshot() -> BudgetSnapshot { currentSnapshot() }

    /// 修改阈值；若已超阈值则立即发出一次（防止 UI 在阈值变化后错过）。
    func updateThreshold(_ newValue: Double) {
        thresholdUSD = max(0, newValue)
        let snap = currentSnapshot()
        if snap.exceededThreshold && !thresholdCrossed {
            thresholdCrossed = true
            thresholdContinuation.yield(snap)
        }
    }

    /// 重置全部状态（仅用于新批次开始）。
    func reset() {
        inputTokens = 0
        outputTokens = 0
        usd = 0
        thresholdCrossed = false
    }

    /// 用 saved snapshot 恢复累计花费（断点续传场景）。
    ///
    /// 注意：**不**恢复 `thresholdUSD`，保留构造时传入的新阈值。
    /// `handleBudgetExceeded` 里保存的 snapshot 携带的是旧阈值，
    /// 如果恢复过来会把用户在"调整阈值并继续"时设置的新阈值覆盖掉。
    func restore(from snapshot: BudgetSnapshot) {
        inputTokens = max(0, snapshot.inputTokens)
        outputTokens = max(0, snapshot.outputTokens)
        usd = max(0, snapshot.usd)
        // thresholdUSD 保持 init 传入的值，不从磁盘覆盖
        thresholdCrossed = usd >= thresholdUSD
    }

    private func currentSnapshot() -> BudgetSnapshot {
        BudgetSnapshot(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            usd: usd,
            thresholdUSD: thresholdUSD
        )
    }
}
