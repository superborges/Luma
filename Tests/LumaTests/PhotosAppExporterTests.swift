import XCTest
@testable import Luma

final class PhotosAppExporterTests: XCTestCase {
    func testValidateConfigurationAlwaysSucceeds() async throws {
        let exporter = PhotosAppExporter()

        let isValid = try await exporter.validateConfiguration(options: .default)

        XCTAssertTrue(isValid)
    }

    func testExportReturnsEarlyWhenNoPickedAssets() async throws {
        let exporter = PhotosAppExporter()
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8201",
            captureDate: TestFixtures.makeDate(hour: 18),
            userDecision: .pending
        )
        let group = TestFixtures.makeGroup(name: "Pending Only", assets: [asset])

        let result = try await exporter.export(assets: [asset], groups: [group], options: .default)

        XCTAssertEqual(result.exportedCount, 0)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.destinationDescription, "照片 App")
    }
}
