import Foundation
import XCTest
@testable import Luma

final class BatchSchedulerTests: XCTestCase {
    func testScoreGroupsMapsScoresRecommendationsProgressAndCosts() async throws {
        let scheduler = BatchScheduler()

        try await TestFixtures.withTemporaryDirectory { root in
            let image1 = root.appendingPathComponent("IMG_3001.JPG")
            let image2 = root.appendingPathComponent("IMG_3002.JPG")
            try TestFixtures.makeJPEG(at: image1)
            try TestFixtures.makeJPEG(at: image2)

            var asset1 = TestFixtures.makeAsset(
                baseName: "IMG_3001",
                captureDate: TestFixtures.makeDate(hour: 11),
                aiScore: nil
            )
            asset1.previewURL = image1

            var asset2 = TestFixtures.makeAsset(
                baseName: "IMG_3002",
                captureDate: TestFixtures.makeDate(hour: 11, minute: 1),
                aiScore: nil
            )
            asset2.previewURL = image2

            let rejected = TestFixtures.makeAsset(
                baseName: "IMG_3003",
                captureDate: TestFixtures.makeDate(hour: 11, minute: 2),
                issues: [.blurry]
            )

            let group = TestFixtures.makeGroup(name: "Hero Group", assets: [asset1, asset2, rejected])
            let progressRecorder = BatchProgressRecorder()
            let provider = MockVisionModelProvider(
                groupScoreHandler: { images, context in
                    XCTAssertEqual(images.count, 2)
                    XCTAssertEqual(context.groupName, "Hero Group")
                    return GroupScoreResult(
                        photoResults: [
                            ScoredPhotoResult(index: 1, score: TestFixtures.makeAIScore(provider: "mock", overall: 93, recommended: true)),
                            ScoredPhotoResult(index: 2, score: TestFixtures.makeAIScore(provider: "mock", overall: 72, recommended: false)),
                        ],
                        groupBest: [1],
                        groupComment: "Pick frame 1",
                        usage: TokenUsage(inputTokens: 120, outputTokens: 30)
                    )
                }
            )

            let result = try await scheduler.scoreGroups(
                [group],
                assetsByID: [asset1.id: asset1, asset2.id: asset2, rejected.id: rejected],
                provider: provider,
                modelConfig: TestFixtures.makeModelConfig(name: "Mock Vision", inputCost: 0.001, outputCost: 0.002),
                progress: { progress in progressRecorder.record(progress) }
            )

            let progressEvents = progressRecorder.snapshot()
            XCTAssertEqual(result.scoresByAssetID[asset1.id]?.overall, 93)
            XCTAssertEqual(result.scoresByAssetID[asset2.id]?.overall, 72)
            XCTAssertNil(result.scoresByAssetID[rejected.id])
            XCTAssertEqual(result.groupCommentsByID[group.id], "Pick frame 1")
            XCTAssertEqual(result.recommendedByGroupID[group.id], [asset1.id])
            XCTAssertEqual(result.costRecords.count, 1)
            XCTAssertEqual(try XCTUnwrap(result.costRecords.first?.cost), 0.18, accuracy: 0.0001)
            XCTAssertEqual(progressEvents.count, 1)
            XCTAssertEqual(progressEvents.first?.completedGroups, 1)
            XCTAssertEqual(progressEvents.first?.totalGroups, 1)
        }
    }

    func testAnalyzeDetailsReturnsSuggestionsAndCosts() async throws {
        let scheduler = BatchScheduler()

        try await TestFixtures.withTemporaryDirectory { root in
            let imageURL = root.appendingPathComponent("IMG_3101.JPG")
            try TestFixtures.makeJPEG(at: imageURL)

            var asset = TestFixtures.makeAsset(
                baseName: "IMG_3101",
                captureDate: TestFixtures.makeDate(hour: 12),
                aiScore: TestFixtures.makeAIScore(overall: 88, recommended: true)
            )
            asset.previewURL = imageURL

            let group = TestFixtures.makeGroup(name: "Portrait Session", assets: [asset], recommendedAssets: [asset.id])
            let provider = MockVisionModelProvider(
                detailedHandler: { image, context in
                    XCTAssertEqual(image.filename, "IMG_3101.JPG")
                    XCTAssertEqual(context.groupName, "Portrait Session")
                    XCTAssertEqual(context.initialScore, 88)
                    XCTAssertTrue(context.exifSummary.contains("f/1.8"))
                    return DetailedAnalysisResult(
                        suggestions: EditSuggestions(
                            crop: nil,
                            filterStyle: FilterSuggestion(primary: "clean", reference: "kodak", mood: "bright"),
                            adjustments: AdjustmentValues(
                                exposure: 0.2,
                                contrast: 10,
                                highlights: nil,
                                shadows: nil,
                                temperature: nil,
                                tint: nil,
                                saturation: nil,
                                vibrance: nil,
                                clarity: nil,
                                dehaze: nil
                            ),
                            hslAdjustments: nil,
                            localEdits: [LocalEdit(area: "face", action: "lift shadows")],
                            narrative: "Brighten the subject."
                        ),
                        rawResponse: "{}",
                        usage: TokenUsage(inputTokens: 80, outputTokens: 25)
                    )
                }
            )

            let result = try await scheduler.analyzeDetails(
                assetIDs: [asset.id],
                assetsByID: [asset.id: asset],
                groupsByID: [group.id: group],
                provider: provider,
                modelConfig: TestFixtures.makeModelConfig(name: "Mock Detail", inputCost: 0.0005, outputCost: 0.001)
            )

            XCTAssertEqual(result.0[asset.id]?.narrative, "Brighten the subject.")
            XCTAssertEqual(result.0[asset.id]?.localEdits?.first?.action, "lift shadows")
            XCTAssertEqual(result.1.count, 1)
            XCTAssertEqual(try XCTUnwrap(result.1.first?.cost), 0.065, accuracy: 0.0001)
        }
    }
}

private struct MockVisionModelProvider: VisionModelProvider {
    var id: String = "mock-provider"
    var displayName: String = "Mock Provider"
    var apiProtocol: APIProtocol = .openAICompatible
    var costPer100Images: Double = 0
    var groupScoreHandler: @Sendable ([ImageData], GroupContext) async throws -> GroupScoreResult
    var detailedHandler: @Sendable (ImageData, PhotoContext) async throws -> DetailedAnalysisResult

    init(
        groupScoreHandler: @escaping @Sendable ([ImageData], GroupContext) async throws -> GroupScoreResult = { _, _ in
            GroupScoreResult(photoResults: [], groupBest: [], groupComment: nil, usage: nil)
        },
        detailedHandler: @escaping @Sendable (ImageData, PhotoContext) async throws -> DetailedAnalysisResult = { _, _ in
            DetailedAnalysisResult(
                suggestions: EditSuggestions(crop: nil, filterStyle: nil, adjustments: nil, hslAdjustments: nil, localEdits: nil, narrative: ""),
                rawResponse: nil,
                usage: nil
            )
        }
    ) {
        self.groupScoreHandler = groupScoreHandler
        self.detailedHandler = detailedHandler
    }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult {
        try await groupScoreHandler(images, context)
    }

    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult {
        try await detailedHandler(image, context)
    }

    func testConnection() async throws -> Bool {
        true
    }
}

private final class BatchProgressRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "BatchProgressRecorder")
    private var progressEvents: [BatchProgress] = []

    func record(_ progress: BatchProgress) {
        queue.sync {
            progressEvents.append(progress)
        }
    }

    func snapshot() -> [BatchProgress] {
        queue.sync { progressEvents }
    }
}
