import XCTest
@testable import Luma

final class RuntimeTraceTests: XCTestCase {
    func testStartSessionMirrorsEventsToLatestAndSessionArchive() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "RuntimeTrace") { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let startedAt = TestFixtures.makeDate(hour: 12)
                let store = RuntimeTraceStore(
                    sessionID: "session-under-test",
                    sessionStartedAt: startedAt,
                    isEnabled: true,
                    maxArchivedSessions: 5
                )

                await store.startSession(metadata: ["entry": "test"])
                await store.event("opened_project", category: "app", metadata: ["project": "demo"])

                let latestURLValue = await store.latestTraceFileURL()
                let sessionURLValue = await store.sessionTraceFileURL()
                let latestURL = try XCTUnwrap(latestURLValue)
                let sessionURL = try XCTUnwrap(sessionURLValue)

                let latestContents = try String(contentsOf: latestURL, encoding: .utf8)
                let sessionContents = try String(contentsOf: sessionURL, encoding: .utf8)

                XCTAssertEqual(latestContents, sessionContents)
                XCTAssertTrue(latestContents.contains("\"sequence\":1"))
                XCTAssertTrue(latestContents.contains("\"sequence\":2"))
                XCTAssertTrue(latestContents.contains("\"name\":\"session_started\""))
                XCTAssertTrue(latestContents.contains("\"name\":\"opened_project\""))
                XCTAssertTrue(latestContents.contains(latestURL.path))
                XCTAssertTrue(latestContents.contains(sessionURL.path))
            }
        }
    }

    func testStartSessionRotatesOldArchivedSessions() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "RuntimeTrace") { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sessionsRoot = try AppDirectories.runtimeTraceSessionsRoot()
                let oldNames = [
                    "20260101_010000_old-a.jsonl",
                    "20260101_020000_old-b.jsonl",
                    "20260101_030000_old-c.jsonl",
                ]

                for name in oldNames {
                    let url = sessionsRoot.appendingPathComponent(name)
                    try Data("{}".utf8).write(to: url)
                }

                let utc = TimeZone(secondsFromGMT: 0)!
                let store = RuntimeTraceStore(
                    sessionID: "current-session",
                    sessionStartedAt: TestFixtures.makeDate(
                        year: 2026,
                        month: 1,
                        day: 1,
                        hour: 4,
                        timeZone: utc
                    ),
                    isEnabled: true,
                    maxArchivedSessions: 2
                )

                await store.startSession(metadata: [:])

                let remainingFiles = try FileManager.default.contentsOfDirectory(
                    at: sessionsRoot,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .map(\.lastPathComponent)
                .sorted()

                XCTAssertEqual(
                    remainingFiles,
                    [
                        "20260101_030000_old-c.jsonl",
                        "20260101_040000_current-session.jsonl",
                    ]
                )
            }
        }
    }
}
