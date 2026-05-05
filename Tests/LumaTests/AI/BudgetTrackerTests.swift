import XCTest
@testable import Luma

final class BudgetTrackerTests: XCTestCase {

    func testAddAccumulatesTokensAndCost() async {
        let tracker = BudgetTracker(thresholdUSD: 10.0)
        _ = await tracker.add(usage: TokenUsage(inputTokens: 1000, outputTokens: 500), cost: 0.005)
        let snap = await tracker.add(usage: TokenUsage(inputTokens: 2000, outputTokens: 800), cost: 0.012)
        XCTAssertEqual(snap.inputTokens, 3000)
        XCTAssertEqual(snap.outputTokens, 1300)
        XCTAssertEqual(snap.usd, 0.017, accuracy: 1e-9)
        XCTAssertEqual(snap.thresholdUSD, 10.0)
        XCTAssertFalse(snap.exceededThreshold)
    }

    func testCrossesThresholdEmitsExactlyOnce() async {
        let tracker = BudgetTracker(thresholdUSD: 0.10)
        // 启动后台监听
        let stream = await tracker.thresholdCrossedStream
        let listener = Task<[BudgetSnapshot], Never> {
            var collected: [BudgetSnapshot] = []
            for await snap in stream {
                collected.append(snap)
                if collected.count >= 1 { break }
            }
            return collected
        }
        _ = await tracker.add(usage: .zero, cost: 0.05)
        _ = await tracker.add(usage: .zero, cost: 0.10) // 现在 0.15 > 0.10，跨过阈值
        _ = await tracker.add(usage: .zero, cost: 0.05) // 不应再触发

        // 给监听任务一个机会 yield
        try? await Task.sleep(for: .milliseconds(50))
        listener.cancel()
        let received = await listener.value
        XCTAssertEqual(received.count, 1)
        XCTAssertGreaterThanOrEqual(received[0].usd, 0.10)
    }

    func testRestoreFromSnapshotKeepsThresholdState() async {
        let tracker = BudgetTracker()
        let saved = BudgetSnapshot(inputTokens: 100, outputTokens: 50, usd: 6.5, thresholdUSD: 5.0)
        await tracker.restore(from: saved)
        let snap = await tracker.snapshot()
        XCTAssertEqual(snap.usd, 6.5)
        XCTAssertEqual(snap.thresholdUSD, 5.0)
        XCTAssertTrue(snap.exceededThreshold)
    }

    func testTokenUsageCostCalculation() {
        let usage = TokenUsage(inputTokens: 1_500_000, outputTokens: 200_000)
        // $0.075/1M input, $0.30/1M output
        let cost = usage.cost(inputUSDPerMillion: 0.075, outputUSDPerMillion: 0.30)
        XCTAssertEqual(cost, 1.5 * 0.075 + 0.2 * 0.30, accuracy: 1e-9)
    }
}
