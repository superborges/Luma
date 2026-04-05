import XCTest
@testable import Luma

final class TraceSummaryCLITests: XCTestCase {
    func testRunWritesMarkdownAndJSONSummaries() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "TraceSummary") { root in
            let traceURL = root.appendingPathComponent("runtime.jsonl")
            let markdownURL = root.appendingPathComponent("trace-summary.md")
            let jsonURL = root.appendingPathComponent("trace-summary.json")

            let lines = [
                #"{"sequence":1,"timestamp":"2026-04-05T00:00:00Z","sessionID":"session-1","level":"info","category":"app","name":"session_started","metadata":{"latest_trace_file":"/tmp/runtime-latest.jsonl"}}"#,
                #"{"sequence":2,"timestamp":"2026-04-05T00:00:01Z","sessionID":"session-1","level":"metric","category":"interaction","name":"group_selected","metadata":{"duration_ms":"30.00","group_id":"group-1"}}"#,
                #"{"sequence":3,"timestamp":"2026-04-05T00:00:02Z","sessionID":"session-1","level":"metric","category":"state","name":"derived_state_rebuilt","metadata":{"duration_ms":"15.00","selected_group_id":"group-1"}}"#,
                #"{"sequence":4,"timestamp":"2026-04-05T00:00:03Z","sessionID":"session-1","level":"metric","category":"viewer","name":"single_image_loaded","metadata":{"duration_ms":"95.00","asset_id":"asset-1"}}"#,
                #"{"sequence":5,"timestamp":"2026-04-05T00:00:04Z","sessionID":"session-1","level":"error","category":"import","name":"import_paused","metadata":{"message":"device disconnected"}}"#
            ]
            try lines.joined(separator: "\n").appending("\n").write(to: traceURL, atomically: true, encoding: .utf8)

            try TraceSummaryCLI.run(
                .init(
                    traceURL: traceURL,
                    markdownURL: markdownURL,
                    jsonURL: jsonURL,
                    topLimit: 5
                )
            )

            let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
            let json = try String(contentsOf: jsonURL, encoding: .utf8)

            XCTAssertTrue(markdown.contains("Trace Summary"))
            XCTAssertTrue(markdown.contains("Hotspot Budgets"))
            XCTAssertTrue(markdown.contains("Slow Chains"))
            XCTAssertTrue(markdown.contains("group_selected"))
            XCTAssertTrue(markdown.contains("derived_state_rebuilt"))
            XCTAssertTrue(markdown.contains("single_image_loaded"))
            XCTAssertTrue(markdown.contains("over-budget"))
            XCTAssertTrue(markdown.contains("device disconnected"))
            XCTAssertTrue(json.contains("\"recordCount\" : 5"))
            XCTAssertTrue(json.contains("\"parseFailureCount\" : 0"))
            XCTAssertTrue(json.contains("\"breachCount\""))
        }
    }
}
