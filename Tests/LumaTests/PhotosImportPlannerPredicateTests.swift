import Foundation
import Photos
import XCTest
@testable import Luma

/// `PhotosImportPlanner.makePredicates` 与 Adapter 一致：AND 组合；多月为 OR 日期分支。
/// 纯 Foundation + PhotoKit 类型常量，不触碰真实 PHPhotoLibrary。
final class PhotosImportPlannerPredicateTests: XCTestCase {

    private func compoundAND(_ predicates: [NSPredicate]) -> NSCompoundPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func assetDict(
        creationDate: Date,
        mediaSubtypes: UInt32 = 0
    ) -> [String: Any] {
        [
            "mediaType": PHAssetMediaType.image.rawValue,
            "mediaSubtypes": NSNumber(value: mediaSubtypes),
            "creationDate": creationDate,
        ]
    }

    func testEmptyDateRanges_imageOnly_andMatchesImageRow() {
        let preds = PhotosImportPlanner.makePredicates(dateRanges: [], mediaTypeFilter: .all)
        XCTAssertEqual(preds.count, 1)
        let root = compoundAND(preds)
        let d = Date()
        XCTAssertTrue(root.evaluate(with: assetDict(creationDate: d)))
        XCTAssertFalse(root.evaluate(with: assetDict(creationDate: d).merging(["mediaType": PHAssetMediaType.video.rawValue]) { _, new in new }))
    }

    func testSingleDateRange_matchesInside_notOutside() {
        let slot = PhotosImportPlan.MonthSlot(year: 2026, month: 1)
        let range = slot.dateRange
        let preds = PhotosImportPlanner.makePredicates(dateRanges: [range], mediaTypeFilter: .all)
        let root = compoundAND(preds)

        let inside = range.lowerBound.addingTimeInterval(86400)
        XCTAssertTrue(root.evaluate(with: assetDict(creationDate: inside)))

        let before = range.lowerBound.addingTimeInterval(-86400)
        XCTAssertFalse(root.evaluate(with: assetDict(creationDate: before)))
    }

    func testMultipleDateRanges_OR_matchesEitherMonth_notGapBetween() {
        let jan = PhotosImportPlan.MonthSlot(year: 2026, month: 1).dateRange
        let mar = PhotosImportPlan.MonthSlot(year: 2026, month: 3).dateRange
        let preds = PhotosImportPlanner.makePredicates(dateRanges: [jan, mar], mediaTypeFilter: .all)
        let root = compoundAND(preds)

        let febMid = PhotosImportPlan.MonthSlot(year: 2026, month: 2).dateRange.lowerBound.addingTimeInterval(86400 * 14)
        XCTAssertFalse(root.evaluate(with: assetDict(creationDate: febMid)))

        let janMid = jan.lowerBound.addingTimeInterval(86400 * 5)
        XCTAssertTrue(root.evaluate(with: assetDict(creationDate: janMid)))

        let marMid = mar.lowerBound.addingTimeInterval(86400 * 5)
        XCTAssertTrue(root.evaluate(with: assetDict(creationDate: marMid)))
    }

    func testStaticOnly_excludesLiveSubtype() {
        let slot = PhotosImportPlan.MonthSlot(year: 2026, month: 6)
        let range = slot.dateRange
        let preds = PhotosImportPlanner.makePredicates(dateRanges: [range], mediaTypeFilter: .staticOnly)
        let root = compoundAND(preds)

        let mid = range.lowerBound.addingTimeInterval(86400)
        let liveMask = UInt32(PHAssetMediaSubtype.photoLive.rawValue)

        XCTAssertTrue(root.evaluate(with: assetDict(creationDate: mid, mediaSubtypes: 0)))
        XCTAssertFalse(root.evaluate(with: assetDict(creationDate: mid, mediaSubtypes: liveMask)))
    }

    func testLiveOnly_requiresLiveSubtype() {
        let slot = PhotosImportPlan.MonthSlot(year: 2026, month: 6)
        let range = slot.dateRange
        let preds = PhotosImportPlanner.makePredicates(dateRanges: [range], mediaTypeFilter: .liveOnly)
        let root = compoundAND(preds)

        let mid = range.lowerBound.addingTimeInterval(86400)
        let liveMask = UInt32(PHAssetMediaSubtype.photoLive.rawValue)

        XCTAssertFalse(root.evaluate(with: assetDict(creationDate: mid, mediaSubtypes: 0)))
        XCTAssertTrue(root.evaluate(with: assetDict(creationDate: mid, mediaSubtypes: liveMask)))
    }

    func testSingleRangeOverload_matchesCombinedOverload() {
        let slot = PhotosImportPlan.MonthSlot(year: 2026, month: 5)
        let range = slot.dateRange
        let a = PhotosImportPlanner.makePredicates(dateRange: range, mediaTypeFilter: .staticOnly)
        let b = PhotosImportPlanner.makePredicates(dateRanges: [range], mediaTypeFilter: .staticOnly)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(
            compoundAND(a).predicateFormat,
            compoundAND(b).predicateFormat
        )
    }
}
