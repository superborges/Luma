import XCTest
@testable import Luma

final class BatchSchedulerTests: XCTestCase {

    /// 静态工厂避免在 `@Sendable` 闭包中捕获非 Sendable 的 self。
    static func sampleResult() -> GroupScoreResult {
        GroupScoreResult(
            perPhoto: [
                PerPhotoScore(
                    index: 1,
                    scores: PhotoScores(composition: 70, exposure: 70, color: 70, sharpness: 70, story: 70),
                    overall: 70,
                    comment: "",
                    recommended: false
                )
            ],
            groupBest: [],
            groupComment: "",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50)
        )
    }

    func testRunHonorsConcurrencyLimit() async {
        // 用 actor 计数同时在 flight 的任务数；确认峰值 <= 限制
        let counter = ConcurrentPeakCounter()
        let scheduler = BatchScheduler(maxConcurrency: 2, maxRetries: 0)
        let tasks: [ScoringTask] = (0..<6).map { i in
            ScoringTask(
                groupID: UUID(),
                groupName: "g\(i)",
                work: { @Sendable in
                    await counter.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await counter.leave()
                    return (Self.sampleResult(), "model")
                }
            )
        }
        await scheduler.run(tasks: tasks) { _, _, _ in }
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 2)
    }

    func testCallbackInvokedOncePerTaskWithSuccessOrFailure() async {
        let scheduler = BatchScheduler(maxConcurrency: 4, maxRetries: 0)
        let id1 = UUID(), id2 = UUID()
        let tasks: [ScoringTask] = [
            ScoringTask(groupID: id1, groupName: "ok", work: { @Sendable in (Self.sampleResult(), "m") }),
            ScoringTask(groupID: id2, groupName: "fail", work: { @Sendable in throw LumaError.networkFailed("boom") })
        ]
        let collector = ResultCollector()
        await scheduler.run(tasks: tasks) { id, _, result in
            await collector.add(id: id, success: (try? result.get()) != nil)
        }
        let entries = await collector.entries
        XCTAssertEqual(entries.count, 2)
        let dict = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.success) })
        XCTAssertEqual(dict[id1], true)
        XCTAssertEqual(dict[id2], false)
    }

    func testNoRetryOn401() async {
        let attempts = AttemptCounter()
        let task = ScoringTask(
            groupID: UUID(),
            groupName: "401",
            work: { @Sendable in
                _ = await attempts.increment()
                throw LumaError.aiProvider(code: 401, message: "invalid key")
            }
        )
        let result = await BatchScheduler.runWithRetry(task: task, maxRetries: 3)
        let attemptCount = await attempts.value
        switch result {
        case .success: XCTFail("应失败")
        case .failure: XCTAssertEqual(attemptCount, 1, "401 不应重试")
        }
    }

    func testCancellationStopsTaskImmediately() async {
        let scheduler = BatchScheduler(maxConcurrency: 1, maxRetries: 0)
        let started = AttemptCounter()
        let tasks: [ScoringTask] = (0..<5).map { i in
            ScoringTask(
                groupID: UUID(),
                groupName: "g\(i)",
                work: { @Sendable in
                    _ = await started.increment()
                    try? await Task.sleep(for: .milliseconds(200))
                    return (Self.sampleResult(), "m")
                }
            )
        }
        let runTask = Task { @Sendable in
            await scheduler.run(tasks: tasks) { _, _, _ in }
        }
        try? await Task.sleep(for: .milliseconds(50))
        runTask.cancel()
        await runTask.value
        let totalStarted = await started.value
        // 因为 maxConcurrency=1，cancel 时最多只跑了 1 个；后续任务应被取消
        XCTAssertLessThanOrEqual(totalStarted, 2)
    }
}

// MARK: - Helpers

private actor ConcurrentPeakCounter {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current = max(0, current - 1)
    }
}

private actor ResultCollector {
    struct Entry: Equatable {
        let id: UUID
        let success: Bool
    }

    private(set) var entries: [Entry] = []

    func add(id: UUID, success: Bool) {
        entries.append(Entry(id: id, success: success))
    }
}

private actor AttemptCounter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
