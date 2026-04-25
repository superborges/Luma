import Photos
import XCTest
@testable import Luma

final class PhotosImportPlanTests: XCTestCase {
    // MARK: - DatePreset.resolvedRange

    func testDatePresetLast7RangeEndsAtNow() {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = 2026
        c.month = 4
        c.day = 15
        c.hour = 12
        guard let now = cal.date(from: c) else {
            return XCTFail("fixture date")
        }
        guard let range = PhotosImportPlan.DatePreset.last7.resolvedRange(now: now) else {
            return XCTFail("expected range")
        }
        XCTAssertEqual(range.upperBound, now)
        let expectedStart = cal.date(byAdding: .day, value: -7, to: now)
        XCTAssertEqual(range.lowerBound, expectedStart)
    }

    func testDatePresetAllTimeIsNil() {
        XCTAssertNil(PhotosImportPlan.DatePreset.allTime.resolvedRange(now: .now))
    }

    func testDatePresetCustomSwapsReversedBounds() {
        let a = Date(timeIntervalSince1970: 1_000)
        let b = Date(timeIntervalSince1970: 2_000)
        let range = PhotosImportPlan.DatePreset.custom(start: b, end: a).resolvedRange(now: .now)
        XCTAssertEqual(range?.lowerBound, a)
        XCTAssertEqual(range?.upperBound, b)
    }

    // MARK: - makeDefault

    func testMakeDefaultHasExpectedSemDefaults() {
        let p = PhotosImportPlan.makeDefault()
        if case .last30 = p.datePreset {} else { XCTFail() }
        XCTAssertNil(p.smartAlbum)
        XCTAssertEqual(p.mediaTypeFilter, .all)
        XCTAssertEqual(p.limit, 500)
        XCTAssertTrue(p.dedupeAgainstCurrentProject)
    }

    // MARK: - displayName

    func testDisplayNameIncludesBaseAndLimit() {
        let p = PhotosImportPlan.makeDefault()
        XCTAssertTrue(p.displayName.contains("Mac · 照片 App"))
        XCTAssertTrue(p.displayName.contains("最近 30 天"))
        XCTAssertTrue(p.displayName.contains("500"))
    }

    func testDisplayNameWithSmartAlbumUsesPlannerTitle() {
        var p = PhotosImportPlan.makeDefault()
        p.smartAlbum = .favorites
        XCTAssertTrue(p.displayName.contains("收藏"), "应来自 PhotosImportPlanner.smartAlbums 标题")
    }

    func testDisplayNameWithUserAlbumWhenNoSmartAlbum() {
        var p = PhotosImportPlan.makeDefault()
        p.userAlbumTitle = "旅行"
        XCTAssertTrue(p.displayName.contains("旅行"))
    }

    func testDisplayNameAppendsNonAllMediaFilter() {
        var p = PhotosImportPlan.makeDefault()
        p.mediaTypeFilter = .staticOnly
        XCTAssertTrue(p.displayName.contains("仅静态"))
    }

    // MARK: - photoKitSubtype bridge

    func testPhotoKitSubtypeMapsAllSmartAlbums() {
        XCTAssertEqual(photoKitSubtype(for: .recentlyAdded), .smartAlbumRecentlyAdded)
        XCTAssertEqual(photoKitSubtype(for: .favorites), .smartAlbumFavorites)
        XCTAssertEqual(photoKitSubtype(for: .screenshots), .smartAlbumScreenshots)
        XCTAssertEqual(photoKitSubtype(for: .selfPortraits), .smartAlbumSelfPortraits)
        XCTAssertEqual(photoKitSubtype(for: .livePhotos), .smartAlbumLivePhotos)
        XCTAssertEqual(photoKitSubtype(for: .bursts), .smartAlbumBursts)
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
