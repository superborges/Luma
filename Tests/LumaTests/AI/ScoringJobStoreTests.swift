import XCTest
@testable import Luma

final class ScoringJobStoreTests: XCTestCase {

    private func makeJob(totalGroups: Int = 3) -> ScoringJob {
        let groupIDs = (0..<totalGroups).map { _ in UUID() }
        return ScoringJob(
            id: UUID(),
            strategy: .balanced,
            primaryModelID: UUID(),
            premiumModelID: nil,
            startedAt: .now,
            totalGroups: totalGroups,
            status: .running,
            pausedReason: nil,
            groupStatuses: Dictionary(uniqueKeysWithValues: groupIDs.map { ($0, .pending) }),
            budget: BudgetSnapshot(inputTokens: 0, outputTokens: 0, usd: 0, thresholdUSD: 5.0)
        )
    }

    func testFileStoreRoundTrip() throws {
        try TestFixtures.withTemporaryDirectory(prefix: "ScoringJob") { dir in
            let store = FileScoringJobStore()
            let job = makeJob()
            try store.save(job, in: dir)

            let loaded = try store.load(in: dir)
            XCTAssertEqual(loaded?.id, job.id)
            XCTAssertEqual(loaded?.totalGroups, job.totalGroups)
            XCTAssertEqual(loaded?.status, .running)

            try store.clear(in: dir)
            XCTAssertNil(try store.load(in: dir))
        }
    }

    func testFileStoreSurvivesOverwrite() throws {
        try TestFixtures.withTemporaryDirectory(prefix: "ScoringJob") { dir in
            let store = FileScoringJobStore()
            var job = makeJob()
            try store.save(job, in: dir)

            // 标记一组完成、状态变 completed
            if let firstID = job.groupStatuses.keys.first {
                job.groupStatuses[firstID] = .completed
            }
            job.status = .completed
            try store.save(job, in: dir)

            let loaded = try store.load(in: dir)
            XCTAssertEqual(loaded?.status, .completed)
            XCTAssertEqual(loaded?.completedGroups, 1)
        }
    }

    func testInMemoryStoreIsolatesPerDirectory() throws {
        let store = InMemoryScoringJobStore()
        let dirA = URL(fileURLWithPath: "/tmp/luma-test-A")
        let dirB = URL(fileURLWithPath: "/tmp/luma-test-B")
        try store.save(makeJob(totalGroups: 1), in: dirA)
        try store.save(makeJob(totalGroups: 5), in: dirB)
        XCTAssertEqual(try store.load(in: dirA)?.totalGroups, 1)
        XCTAssertEqual(try store.load(in: dirB)?.totalGroups, 5)
        try store.clear(in: dirA)
        XCTAssertNil(try store.load(in: dirA))
        XCTAssertEqual(try store.load(in: dirB)?.totalGroups, 5)
    }
}
