import XCTest
@testable import Luma

@MainActor
final class UIRegistryTests: XCTestCase {
    func testRegisterStoresAllProvidedFields() {
        let registry = UIRegistry()

        registry.register(
            id: "test.button.a",
            kind: "button",
            frame: CGRect(x: 10, y: 20, width: 80, height: 40),
            metadata: ["label": "Click"]
        )

        let info = registry.info(for: "test.button.a")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.id, "test.button.a")
        XCTAssertEqual(info?.kind, "button")
        XCTAssertEqual(info?.frameInWindow, CGRect(x: 10, y: 20, width: 80, height: 40))
        XCTAssertEqual(info?.metadata["label"], "Click")
    }

    func testRegisterTwicePreservesFirstSeenAndUpdatesFrameMetadataAndLastSeen() throws {
        let registry = UIRegistry()
        registry.register(
            id: "test.tile.b",
            kind: "tile",
            frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            metadata: ["v": "0"]
        )
        let firstSeen = try XCTUnwrap(registry.info(for: "test.tile.b")?.firstSeenAt)

        // Sleep so we can verify lastSeenAt actually advances on re-registration.
        Thread.sleep(forTimeInterval: 0.01)

        registry.register(
            id: "test.tile.b",
            kind: "tile",
            frame: CGRect(x: 5, y: 5, width: 20, height: 20),
            metadata: ["v": "1"]
        )

        let after = try XCTUnwrap(registry.info(for: "test.tile.b"))
        XCTAssertEqual(after.firstSeenAt, firstSeen, "firstSeenAt must NOT change on re-registration")
        XCTAssertGreaterThan(after.lastSeenAt, firstSeen, "lastSeenAt must advance on re-registration")
        XCTAssertEqual(after.frameInWindow, CGRect(x: 5, y: 5, width: 20, height: 20))
        XCTAssertEqual(after.metadata["v"], "1")
    }

    func testUnregisterRemovesElementButLeavesOthersIntact() {
        let registry = UIRegistry()
        registry.register(id: "stays", kind: "view", frame: .zero, metadata: [:])
        registry.register(id: "goes", kind: "view", frame: .zero, metadata: [:])

        registry.unregister(id: "goes")

        XCTAssertNil(registry.info(for: "goes"))
        XCTAssertNotNil(registry.info(for: "stays"))
    }

    func testSortedElementsReturnsByIDAscending() {
        let registry = UIRegistry()
        registry.register(id: "z.a", kind: "view", frame: .zero, metadata: [:])
        registry.register(id: "a.b", kind: "view", frame: .zero, metadata: [:])
        registry.register(id: "m.c", kind: "view", frame: .zero, metadata: [:])

        let sorted = registry.sortedElements().map(\.id)
        XCTAssertEqual(sorted, ["a.b", "m.c", "z.a"])
    }

    func testClearRemovesAllElements() {
        let registry = UIRegistry()
        registry.register(id: "x", kind: "view", frame: .zero, metadata: [:])
        registry.register(id: "y", kind: "view", frame: .zero, metadata: [:])

        registry.clear()

        XCTAssertTrue(registry.elements.isEmpty)
        XCTAssertNil(registry.info(for: "x"))
        XCTAssertNil(registry.info(for: "y"))
    }

    // MARK: - Inspector overlay 开关

    func testInspectorDefaultsToDisabled() {
        let registry = UIRegistry()
        XCTAssertFalse(registry.isInspectorEnabled)
    }

    func testToggleInspectorFlipsStateAndReturnsNewValue() {
        let registry = UIRegistry()

        let afterFirst = registry.toggleInspector(reason: "unit_test_enable")
        XCTAssertTrue(afterFirst)
        XCTAssertTrue(registry.isInspectorEnabled)

        let afterSecond = registry.toggleInspector(reason: "unit_test_disable")
        XCTAssertFalse(afterSecond)
        XCTAssertFalse(registry.isInspectorEnabled)
    }

    func testClearAlsoDisablesInspector() {
        let registry = UIRegistry()
        _ = registry.toggleInspector(reason: "unit_test")
        XCTAssertTrue(registry.isInspectorEnabled)

        registry.clear()

        XCTAssertFalse(registry.isInspectorEnabled, "clear() must reset the inspector switch too, otherwise test leakage")
    }

    // MARK: - textualReport

    func testTextualReportHasHeaderAndStableColumnOrder() {
        let registry = UIRegistry()
        registry.register(
            id: "culling.center.large_image",
            kind: "image",
            frame: CGRect(x: 12.4, y: 84, width: 600.5, height: 400),
            metadata: ["asset_id": "ABC"]
        )
        registry.register(
            id: "culling.bottom.action.pick",
            kind: "button",
            frame: CGRect(x: 320, y: 840, width: 80, height: 32),
            metadata: [:]
        )

        let report = registry.textualReport(
            contextMetadata: ["project_name": "demo"],
            now: Date(timeIntervalSince1970: 0)
        )
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertTrue(lines[0].hasPrefix("# Luma UI Inspector"), "First line should identify the tool")
        XCTAssertTrue(lines[0].contains("(2 elements)"), "Header should show element count, got: \(lines[0])")
        XCTAssertEqual(lines[1], "# project_name=demo", "Second line should render contextMetadata")
        XCTAssertTrue(lines[2].contains("id") && lines[2].contains("kind") && lines[2].contains("metadata"),
                      "Third line should be the table header, got: \(lines[2])")

        // 行按 id 字典序排列，便于 diff。
        XCTAssertTrue(lines[3].contains("culling.bottom.action.pick"))
        XCTAssertTrue(lines[4].contains("culling.center.large_image"))

        // frame 用一位小数格式化。
        XCTAssertTrue(lines[4].contains("12.4"))
        XCTAssertTrue(lines[4].contains("84.0"))
        XCTAssertTrue(lines[4].contains("600.5"))
        XCTAssertTrue(lines[4].contains("400.0"))
        // metadata 附在末尾。
        XCTAssertTrue(lines[4].contains("asset_id=ABC"))
    }

    func testTextualReportSkipsContextMetadataLineWhenEmpty() {
        let registry = UIRegistry()
        registry.register(id: "a", kind: "view", frame: .zero, metadata: [:])

        let report = registry.textualReport(now: Date(timeIntervalSince1970: 0))
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines.count, 3, "expected header + table-header + one row, got: \(report)")
        XCTAssertTrue(lines[0].hasPrefix("# Luma UI Inspector"))
        // 第二行直接是表头，不应该出现 "# ..." 上下文行。
        XCTAssertFalse(lines[1].hasPrefix("# "), "no contextMetadata line should be emitted when empty")
    }

    func testTextualReportWithEmptyRegistryStillRendersHeader() {
        let registry = UIRegistry()
        let report = registry.textualReport(now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(report.contains("(0 elements)"))
    }
}
