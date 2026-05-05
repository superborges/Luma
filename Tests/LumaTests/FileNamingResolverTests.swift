import XCTest
@testable import Luma

final class FileNamingResolverTests: XCTestCase {

    private let sampleDate: Date = {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 15
        comps.hour = 14
        comps.minute = 30
        comps.second = 5
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }()

    // MARK: - original

    func testOriginalRuleReturnsUnchangedName() {
        let result = FileNamingResolver.resolvedFileName(
            originalName: "IMG_1234.jpg",
            captureDate: sampleDate,
            groupName: "Morning Walk",
            sequenceInGroup: 1,
            rule: .original,
            template: ""
        )
        XCTAssertEqual(result, "IMG_1234.jpg")
    }

    // MARK: - datePrefix

    func testDatePrefixPrependsDate() {
        let result = FileNamingResolver.resolvedFileName(
            originalName: "DSC0001.ARW",
            captureDate: sampleDate,
            groupName: "Group",
            sequenceInGroup: 0,
            rule: .datePrefix,
            template: ""
        )
        XCTAssertEqual(result, "2026-04-15_DSC0001.ARW")
    }

    // MARK: - custom

    func testCustomTemplateReplacesAllVariables() {
        let result = FileNamingResolver.resolvedFileName(
            originalName: "IMG_5678.CR3",
            captureDate: sampleDate,
            groupName: "Café Trip",
            sequenceInGroup: 42,
            rule: .custom,
            template: "{date}_{group}_{seq}_{original}"
        )
        XCTAssertTrue(result.hasPrefix("2026-04-15_"))
        XCTAssertTrue(result.contains("_0042_"))
        XCTAssertTrue(result.contains("IMG_5678"))
        XCTAssertTrue(result.hasSuffix(".CR3"))
    }

    func testCustomTemplateDatetimeVariable() {
        let result = FileNamingResolver.resolvedFileName(
            originalName: "photo.heic",
            captureDate: sampleDate,
            groupName: "G",
            sequenceInGroup: 1,
            rule: .custom,
            template: "{datetime}"
        )
        XCTAssertTrue(result.hasPrefix("2026-04-15_"))
        XCTAssertTrue(result.hasSuffix(".heic"))
    }

    func testCustomEmptyTemplateFallsBackToOriginal() {
        let result = FileNamingResolver.resolvedFileName(
            originalName: "raw.dng",
            captureDate: sampleDate,
            groupName: "G",
            sequenceInGroup: 1,
            rule: .custom,
            template: ""
        )
        XCTAssertEqual(result, "raw.dng")
    }

    func testCustomTemplateNoExtension() {
        let result = FileNamingResolver.resolvedFileName(
            originalName: "README",
            captureDate: sampleDate,
            groupName: "G",
            sequenceInGroup: 1,
            rule: .custom,
            template: "{date}_{original}"
        )
        XCTAssertEqual(result, "2026-04-15_README")
    }

    // MARK: - uniqueURL

    func testUniqueURLReturnsBaseWhenNoConflict() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNamingResolverTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("photo.jpg")
        let result = FileNamingResolver.uniqueURL(for: base, in: dir)
        XCTAssertEqual(result, base)
    }

    func testUniqueURLAppendsSuffixOnConflict() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNamingResolverTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("photo.jpg")
        try Data().write(to: base)

        let result = FileNamingResolver.uniqueURL(for: base, in: dir)
        XCTAssertEqual(result.lastPathComponent, "photo-2.jpg")
    }

    func testUniqueURLIncrementsUntilFree() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNamingResolverTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent("photo.jpg"))
        try Data().write(to: dir.appendingPathComponent("photo-2.jpg"))
        try Data().write(to: dir.appendingPathComponent("photo-3.jpg"))

        let base = dir.appendingPathComponent("photo.jpg")
        let result = FileNamingResolver.uniqueURL(for: base, in: dir)
        XCTAssertEqual(result.lastPathComponent, "photo-4.jpg")
    }

    func testUniqueURLNoExtension() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNamingResolverTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("README")
        try Data().write(to: base)

        let result = FileNamingResolver.uniqueURL(for: base, in: dir)
        XCTAssertEqual(result.lastPathComponent, "README-2")
    }
}
