import XCTest
@testable import Luma

final class ImportSessionStoreTests: XCTestCase {
    func testLoadRecoverableSessionsPausesRunningSessionsAndSkipsCompleted() throws {
        try TestFixtures.withTemporaryDirectory { root in
            try TestFixtures.withAppSupportRootOverride(root) {
                let projectURL = root.appendingPathComponent("Project-A", isDirectory: true)
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

                let running = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    projectDirectory: projectURL,
                    phase: .copyingPreviews,
                    status: .running
                )
                let paused = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    projectDirectory: projectURL,
                    updatedAt: TestFixtures.makeDate(hour: 9, minute: 10),
                    phase: .paused,
                    status: .paused,
                    lastError: "Cable unplugged"
                )
                let completed = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    projectDirectory: projectURL,
                    phase: .finalizing,
                    status: .completed
                )

                try ImportSessionStore.save(running)
                try ImportSessionStore.save(paused)
                try ImportSessionStore.save(completed)

                let sessions = try ImportSessionStore.loadRecoverableSessions()

                XCTAssertEqual(sessions.count, 2)
                XCTAssertFalse(sessions.contains { $0.id == completed.id })

                let resumedRunning = try XCTUnwrap(sessions.first { $0.id == running.id })
                XCTAssertEqual(resumedRunning.status, .paused)
                XCTAssertEqual(resumedRunning.phase, .paused)
                XCTAssertEqual(resumedRunning.lastError, "Luma 上次退出时导入尚未完成。")

                let preservedPaused = try XCTUnwrap(sessions.first { $0.id == paused.id })
                XCTAssertEqual(preservedPaused.status, .paused)
                XCTAssertEqual(preservedPaused.lastError, "Cable unplugged")
            }
        }
    }

    func testDeleteSessionsRemovesOnlyMatchingProjectDirectory() throws {
        try TestFixtures.withTemporaryDirectory { root in
            try TestFixtures.withAppSupportRootOverride(root) {
                let projectA = root.appendingPathComponent("Project-A", isDirectory: true)
                let projectB = root.appendingPathComponent("Project-B", isDirectory: true)
                try FileManager.default.createDirectory(at: projectA, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: projectB, withIntermediateDirectories: true)

                let sessionA = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    projectDirectory: projectA,
                    phase: .paused,
                    status: .paused
                )
                let sessionB = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                    projectDirectory: projectB,
                    phase: .paused,
                    status: .paused
                )

                try ImportSessionStore.save(sessionA)
                try ImportSessionStore.save(sessionB)

                try ImportSessionStore.deleteSessions(forProjectDirectory: projectA)
                let sessions = try ImportSessionStore.loadRecoverableSessions()

                XCTAssertEqual(sessions.map(\.id), [sessionB.id])
            }
        }
    }
}
