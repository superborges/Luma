import XCTest
@testable import Luma

final class SessionPipelineTests: XCTestCase {
    func testEmptySessionPipelineIsMostlyPending() {
        let session = Session(
            id: UUID(),
            name: "E",
            createdAt: .now,
            updatedAt: .now,
            location: nil,
            tags: [],
            coverAssetID: nil,
            assets: [],
            groups: [],
            importSessions: [],
            editingSessions: [],
            exportJobs: []
        )
        let p = session.pipelineStatus
        XCTAssertEqual(p.ingest.status, .pending)
        XCTAssertEqual(p.group.status, .pending)
        XCTAssertEqual(p.score.status, .pending)
        XCTAssertEqual(p.cull.status, .pending)
        XCTAssertEqual(p.editing.status, .pending)
        XCTAssertEqual(p.export.status, .pending)
    }

    func testMigratedSessionWithScoredPickedAssetShowsCompletedIngestGroupScoreCull() {
        let a = TestFixtures.makeAsset(
            baseName: "A",
            captureDate: TestFixtures.makeDate(hour: 8),
            aiScore: TestFixtures.makeAIScore(overall: 80),
            userDecision: .picked
        )
        let g = TestFixtures.makeGroup(name: "G", assets: [a])
        let session = Session.migratedFromLegacy(
            id: UUID(),
            name: "M",
            createdAt: .now,
            assets: [a],
            groups: [g]
        )
        let p = session.pipelineStatus
        XCTAssertEqual(p.ingest.status, .completed)
        XCTAssertEqual(p.group.status, .completed)
        XCTAssertEqual(p.score.status, .completed)
        XCTAssertEqual(p.cull.status, .completed)
    }

    func testSessionStageStatesFromPipelineHasSixStagesInOrder() {
        let a = TestFixtures.makeAsset(
            baseName: "A",
            captureDate: .now,
            userDecision: .pending
        )
        let g = TestFixtures.makeGroup(name: "G", assets: [a])
        let session = Session.migratedFromLegacy(
            id: UUID(),
            name: "M",
            createdAt: .now,
            assets: [a],
            groups: [g]
        )
        let states = session.sessionStageStatesFromPipeline()
        XCTAssertEqual(states.map(\.stage), [
            .ingest, .group, .score, .cull, .editing, .export
        ])
    }
}
