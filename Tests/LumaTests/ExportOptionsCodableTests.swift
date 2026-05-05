import XCTest
@testable import Luma

final class ExportOptionsCodableTests: XCTestCase {
    func testJSONRoundTrip() throws {
        var original = ExportOptions(
            destination: .lightroom,
            createAlbumPerGroup: false,
            mergeRawAndJpeg: true,
            preserveLivePhoto: false,
            includeAICommentAsDescription: true,
            lrAutoImportFolder: URL(fileURLWithPath: "/tmp/lr", isDirectory: true),
            writeXmpSidecar: false,
            writeEditSuggestionsToXmp: true,
            folderTemplate: .byRating,
            outputPath: URL(fileURLWithPath: "/out/p", isDirectory: true),
            rejectedHandling: .discard,
            photosCleanupStrategy: .deleteRejectedOriginals,
            photosCleanupDryRun: true
        )
        let tag = UUID()
        original.onlyAssetIDs = [tag]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportOptions.self, from: data)

        XCTAssertEqual(decoded.destination, original.destination)
        XCTAssertEqual(decoded.createAlbumPerGroup, original.createAlbumPerGroup)
        XCTAssertEqual(decoded.mergeRawAndJpeg, original.mergeRawAndJpeg)
        XCTAssertEqual(decoded.preserveLivePhoto, original.preserveLivePhoto)
        XCTAssertEqual(decoded.includeAICommentAsDescription, original.includeAICommentAsDescription)
        XCTAssertEqual(decoded.lrAutoImportFolder, original.lrAutoImportFolder)
        XCTAssertEqual(decoded.writeXmpSidecar, original.writeXmpSidecar)
        XCTAssertEqual(decoded.writeEditSuggestionsToXmp, original.writeEditSuggestionsToXmp)
        XCTAssertEqual(decoded.folderTemplate, original.folderTemplate)
        XCTAssertEqual(decoded.outputPath, original.outputPath)
        XCTAssertEqual(decoded.rejectedHandling, original.rejectedHandling)
        XCTAssertEqual(decoded.photosCleanupStrategy, original.photosCleanupStrategy)
        XCTAssertEqual(decoded.photosCleanupDryRun, original.photosCleanupDryRun)
        XCTAssertNil(decoded.onlyAssetIDs, "onlyAssetIDs 不参与编解码，反序列化后恒为 nil")
    }

    func testDefaultOptionsRoundTrip() throws {
        let data = try JSONEncoder().encode(ExportOptions.default)
        let decoded = try JSONDecoder().decode(ExportOptions.self, from: data)
        XCTAssertEqual(decoded.destination, ExportOptions.default.destination)
        XCTAssertEqual(decoded.photosCleanupStrategy, .keepOriginals)
        XCTAssertEqual(decoded.photosCleanupDryRun, false)
    }
}
