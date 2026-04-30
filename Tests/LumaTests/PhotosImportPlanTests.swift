import XCTest
@testable import Luma

final class PhotosImportPlanTests: XCTestCase {
    // MARK: - MonthSlot

    func testMonthSlotLabel() {
        let slot = PhotosImportPlan.MonthSlot(year: 2026, month: 4)
        XCTAssertEqual(slot.label, "2026年4月")
    }

    func testMonthSlotDateRangeSpansFullMonth() {
        let slot = PhotosImportPlan.MonthSlot(year: 2026, month: 3)
        let range = slot.dateRange
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: range.lowerBound), 2026)
        XCTAssertEqual(cal.component(.month, from: range.lowerBound), 3)
        XCTAssertEqual(cal.component(.day, from: range.lowerBound), 1)
        XCTAssertEqual(cal.component(.month, from: range.upperBound), 3)
        XCTAssertEqual(cal.component(.day, from: range.upperBound), 31)
    }

    func testMonthSlotComparable() {
        let jan = PhotosImportPlan.MonthSlot(year: 2026, month: 1)
        let mar = PhotosImportPlan.MonthSlot(year: 2026, month: 3)
        let dec2025 = PhotosImportPlan.MonthSlot(year: 2025, month: 12)
        XCTAssertTrue(jan < mar)
        XCTAssertTrue(dec2025 < jan)
    }

    // MARK: - dateRanges / dateRange

    func testDateRangesReturnsPerMonthRanges() {
        let plan = PhotosImportPlan(
            id: UUID(),
            selectedMonths: [
                .init(year: 2026, month: 3),
                .init(year: 2026, month: 1),
            ],
            mediaTypeFilter: .all,
            dedupeAgainstCurrentProject: true
        )
        let ranges = plan.dateRanges
        XCTAssertEqual(ranges.count, 2)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: ranges[0].lowerBound), 1)
        XCTAssertEqual(cal.component(.month, from: ranges[1].lowerBound), 3)
    }

    func testDateRangeIsUnion() {
        let plan = PhotosImportPlan(
            id: UUID(),
            selectedMonths: [
                .init(year: 2026, month: 3),
                .init(year: 2026, month: 1),
            ],
            mediaTypeFilter: .all,
            dedupeAgainstCurrentProject: true
        )
        let range = plan.dateRange!
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: range.lowerBound), 1)
        XCTAssertEqual(cal.component(.month, from: range.upperBound), 3)
    }

    func testDateRangeNilWhenEmpty() {
        let plan = PhotosImportPlan.makeDefault()
        XCTAssertNil(plan.dateRange)
    }

    // MARK: - makeDefault

    func testMakeDefaultHasExpectedDefaults() {
        let p = PhotosImportPlan.makeDefault()
        XCTAssertTrue(p.selectedMonths.isEmpty)
        XCTAssertEqual(p.mediaTypeFilter, .all)
        XCTAssertTrue(p.dedupeAgainstCurrentProject)
    }

    // MARK: - displayName

    func testDisplayNameSingleMonth() {
        let p = PhotosImportPlan(
            id: UUID(),
            selectedMonths: [.init(year: 2026, month: 4)],
            mediaTypeFilter: .all,
            dedupeAgainstCurrentProject: true
        )
        XCTAssertTrue(p.displayName.contains("Mac · 照片"))
        XCTAssertTrue(p.displayName.contains("2026年4月"))
    }

    func testDisplayNameMultipleMonths() {
        let p = PhotosImportPlan(
            id: UUID(),
            selectedMonths: [.init(year: 2026, month: 1), .init(year: 2026, month: 3)],
            mediaTypeFilter: .all,
            dedupeAgainstCurrentProject: true
        )
        XCTAssertTrue(p.displayName.contains("2个月"))
    }

    func testDisplayNameAppendsNonAllMediaFilter() {
        let p = PhotosImportPlan(
            id: UUID(),
            selectedMonths: [.init(year: 2026, month: 4)],
            mediaTypeFilter: .staticOnly,
            dedupeAgainstCurrentProject: true
        )
        XCTAssertTrue(p.displayName.contains("仅静态"))
    }

    // MARK: - PhotosImportPlanner.Estimate

    func testEstimatePrettyByteSizeFormats() {
        let e = PhotosImportPlanner.Estimate(
            totalAssetCount: 3,
            estimatedDiskBytes: 1_980_000,
            cloudOnlyCount: 0,
            dedupedSkippedCount: 0
        )
        let s = e.prettyByteSize
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.rangeOfCharacter(from: .decimalDigits) != nil, "应包含数字: \(s)")
    }
}
