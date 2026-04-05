import Foundation
import XCTest
@testable import Luma

final class VideoArchiverTests: XCTestCase {
    func testShrinkKeepGeneratesJPEGsAndManifestForRenderableAssets() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let imageURL = sourceRoot.appendingPathComponent("IMG_9001.JPG")
                try TestFixtures.makeJPEG(at: imageURL)

                var renderable = TestFixtures.makeAsset(
                    baseName: "Select: 1",
                    captureDate: TestFixtures.makeDate(hour: 19),
                    aiScore: TestFixtures.makeAIScore(overall: 94, recommended: true)
                )
                renderable.previewURL = imageURL

                let skipped = TestFixtures.makeAsset(
                    baseName: "Missing Source",
                    captureDate: TestFixtures.makeDate(hour: 19, minute: 1)
                )

                let result = try await archiver.shrinkKeep(
                    assets: [renderable, skipped],
                    batchName: "Batch: Spring / Test"
                )

                let outputJPEG = try XCTUnwrap(result.generatedFiles.first)
                let manifestURL = result.outputDirectory.appendingPathComponent("archive_manifest.json")

                XCTAssertEqual(result.generatedFiles.count, 1)
                XCTAssertTrue(result.outputDirectory.lastPathComponent == "Batch- Spring - Test")
                XCTAssertEqual(outputJPEG.lastPathComponent, "Select- 1.jpg")
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputJPEG.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

                let manifestData = try Data(contentsOf: manifestURL)
                let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
                let entries = try XCTUnwrap(manifestObject["entries"] as? [[String: Any]])

                XCTAssertEqual(manifestObject["batchName"] as? String, "Batch: Spring / Test")
                XCTAssertEqual((manifestObject["videos"] as? [Any])?.count, 0)
                XCTAssertEqual(entries.count, 1)
                XCTAssertEqual(entries.first?["originalFileName"] as? String, "IMG_9001.JPG")
                XCTAssertEqual(entries.first?["outputFileName"] as? String, "Select- 1.jpg")
                XCTAssertEqual(entries.first?["aiScore"] as? Int, 94)
                XCTAssertEqual(entries.first?["archiveMethod"] as? String, "shrinkKeep")
            }
        }
    }
}
