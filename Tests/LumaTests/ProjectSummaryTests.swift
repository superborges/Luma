import XCTest
@testable import Luma

final class ProjectSummaryTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/tmp/p1")

    func testReadyStateDescriptionsAndOpenable() {
        let s = ProjectSummary(
            id: dir,
            directory: dir,
            name: "P",
            createdAt: .now,
            updatedAt: .now,
            coverImageURL: nil,
            state: .ready(assetCount: 12, groupCount: 3),
            isCurrent: false,
            decidedCount: 8,
            totalAssetCount: 12,
            lastExportedAt: nil,
            exportJobCount: 0,
            isArchived: false
        )
        XCTAssertEqual(s.assetCountDescription, "12 张")
        XCTAssertEqual(s.groupCountDescription, "3 组")
        XCTAssertTrue(s.isOpenable)
        XCTAssertFalse(s.isCullingComplete)
        XCTAssertEqual(s.decisionFraction, 8.0 / 12.0, accuracy: 0.0001)
        XCTAssertTrue(s.stateSummary.contains("12 张"))
        XCTAssertTrue(s.stateSummary.contains("3 组"))
        XCTAssertTrue(s.stateSummary.contains("已决策 8/12"))
    }

    func testUnavailableState() {
        let s = ProjectSummary(
            id: dir,
            directory: dir,
            name: "Bad",
            createdAt: .now,
            updatedAt: .now,
            coverImageURL: nil,
            state: .unavailable(reason: "broken json"),
            isCurrent: false,
            decidedCount: 0,
            totalAssetCount: 0,
            lastExportedAt: nil,
            exportJobCount: 0,
            isArchived: false
        )
        XCTAssertEqual(s.assetCountDescription, "无法读取")
        XCTAssertEqual(s.groupCountDescription, "Manifest 异常")
        XCTAssertFalse(s.isOpenable)
        XCTAssertTrue(s.stateSummary.contains("broken json"))
    }

    func testCullingCompleteAndDecisionFractionEdgeCases() {
        let complete = ProjectSummary(
            id: dir,
            directory: dir,
            name: "X",
            createdAt: .now,
            updatedAt: .now,
            coverImageURL: nil,
            state: .ready(assetCount: 2, groupCount: 1),
            isCurrent: false,
            decidedCount: 2,
            totalAssetCount: 2,
            lastExportedAt: nil,
            exportJobCount: 1,
            isArchived: false
        )
        XCTAssertTrue(complete.isCullingComplete)
        XCTAssertEqual(complete.decisionFraction, 1.0)
        XCTAssertTrue(complete.stateSummary.contains("已导出 1 次"))

        let zeroTotal = ProjectSummary(
            id: dir,
            directory: dir,
            name: "Y",
            createdAt: .now,
            updatedAt: .now,
            coverImageURL: nil,
            state: .ready(assetCount: 0, groupCount: 0),
            isCurrent: false,
            decidedCount: 0,
            totalAssetCount: 0,
            lastExportedAt: nil,
            exportJobCount: 0,
            isArchived: false
        )
        XCTAssertFalse(zeroTotal.isCullingComplete)
        XCTAssertEqual(zeroTotal.decisionFraction, 0)
        XCTAssertFalse(zeroTotal.stateSummary.contains("已决策"))
    }

    func testSessionListSortPutsArchivedLastAndSortsInside() {
        let old = Date(timeIntervalSince1970: 1000)
        let mid = Date(timeIntervalSince1970: 2000)
        let new = Date(timeIntervalSince1970: 3000)

        let a = makeSummary(name: "Zeta", updated: new, created: mid, archived: false)
        let b = makeSummary(name: "Alpha", updated: mid, created: old, archived: false)
        let c = makeSummary(name: "Beta", updated: old, created: new, archived: true)

        let byModified = SessionListSort.lastModified.sort([b, a, c])
        XCTAssertEqual(byModified.map(\.name), ["Zeta", "Alpha", "Beta"])

        let byCreated = SessionListSort.created.sort([a, b, c])
        XCTAssertEqual(byCreated.map(\.name), ["Zeta", "Alpha", "Beta"], "unarchived by createdAt desc")

        let byName = SessionListSort.name.sort([a, b, c])
        XCTAssertEqual(byName.map(\.name), ["Alpha", "Zeta", "Beta"], "Z before Beta; archived after")
    }

    private func makeSummary(
        name: String,
        updated: Date,
        created: Date,
        archived: Bool
    ) -> ProjectSummary {
        ProjectSummary(
            id: dir.appendingPathComponent(name),
            directory: dir.appendingPathComponent(name),
            name: name,
            createdAt: created,
            updatedAt: updated,
            coverImageURL: nil,
            state: .ready(assetCount: 1, groupCount: 1),
            isCurrent: false,
            decidedCount: 0,
            totalAssetCount: 1,
            lastExportedAt: nil,
            exportJobCount: 0,
            isArchived: archived
        )
    }
}
