import Foundation
import XCTest
@testable import Luma

@MainActor
final class ProjectStoreCloudScoringTests: XCTestCase {
    func testStartCloudScoringAppliesScoresCommentsSuggestionsAndCosts() async {
        let asset1 = TestFixtures.makeAsset(baseName: "IMG_6001", captureDate: TestFixtures.makeDate(hour: 16))
        let asset2 = TestFixtures.makeAsset(baseName: "IMG_6002", captureDate: TestFixtures.makeDate(hour: 16, minute: 1))
        let group = TestFixtures.makeGroup(name: "Cloud Group", assets: [asset1, asset2])

        let scored1 = TestFixtures.makeAIScore(provider: "mock-cloud", overall: 96, recommended: true, comment: "Best frame")
        let scored2 = TestFixtures.makeAIScore(provider: "mock-cloud", overall: 72, recommended: false, comment: "Backup")
        let suggestion = EditSuggestions(
            crop: nil,
            filterStyle: FilterSuggestion(primary: "clean", reference: "fuji", mood: "bright"),
            adjustments: AdjustmentValues(exposure: 0.15, contrast: 8, highlights: nil, shadows: nil, temperature: nil, tint: nil, saturation: nil, vibrance: nil, clarity: nil, dehaze: nil),
            hslAdjustments: nil,
            localEdits: [LocalEdit(area: "subject", action: "lift shadows")],
            narrative: "Refine the hero frame."
        )

        let scheduler = MockBatchScheduler(
            groupResult: BatchSchedulerResult(
                scoresByAssetID: [asset1.id: scored1, asset2.id: scored2],
                groupCommentsByID: [group.id: "Pick the first frame"],
                recommendedByGroupID: [group.id: [asset1.id]],
                costRecords: [
                    CostRecord(id: UUID(), modelName: "Primary Model", inputTokens: 100, outputTokens: 20, cost: 0.12, timestamp: .now)
                ]
            ),
            detailSuggestions: [asset1.id: suggestion],
            detailCosts: [
                CostRecord(id: UUID(), modelName: "Premium Model", inputTokens: 80, outputTokens: 25, cost: 0.09, timestamp: .now)
            ]
        )

        let store = ProjectStore(
            enableImportMonitoring: false,
            visionProviderFactory: { _ in StoreVisionProviderStub() },
            batchSchedulerFactory: { scheduler }
        )
        TestFixtures.seedStore(store, assets: [asset1, asset2], groups: [group])
        store.modelConfigs = [
            TestFixtures.makeModelConfig(name: "Primary Model"),
            ModelConfig(
                id: UUID(),
                name: "Premium Model",
                apiProtocol: .openAICompatible,
                endpoint: "http://localhost:11434/v1",
                apiKeyReference: nil,
                modelId: "premium-model",
                isActive: true,
                role: .premiumFallback,
                maxConcurrency: 2,
                costPerInputToken: 0.001,
                costPerOutputToken: 0.002,
                calibrationOffset: 0
            ),
        ]
        store.aiScoringStrategy = .balanced
        store.aiBudgetLimit = 10

        await store.startCloudScoring()

        XCTAssertFalse(store.isCloudScoring)
        XCTAssertNil(store.cloudScoringStatus)
        XCTAssertNil(store.lastErrorMessage)
        XCTAssertEqual(store.assets.first(where: { $0.id == asset1.id })?.aiScore?.overall, 96)
        XCTAssertEqual(store.assets.first(where: { $0.id == asset2.id })?.aiScore?.overall, 72)
        XCTAssertEqual(store.assets.first(where: { $0.id == asset1.id })?.editSuggestions?.narrative, "Refine the hero frame.")
        XCTAssertEqual(store.groups.first?.groupComment, "Pick the first frame")
        XCTAssertEqual(store.groups.first?.recommendedAssets, [asset1.id])
        XCTAssertEqual(store.costTracker.records.count, 2)
        XCTAssertEqual(store.costTracker.totalCost, 0.21, accuracy: 0.0001)
        XCTAssertEqual(scheduler.detailAssetIDs, [asset1.id])
    }

    func testStartCloudScoringSetsBudgetExceededError() async {
        let asset = TestFixtures.makeAsset(baseName: "IMG_6101", captureDate: TestFixtures.makeDate(hour: 17))
        let group = TestFixtures.makeGroup(name: "Budget Group", assets: [asset])

        let scheduler = MockBatchScheduler(
            groupResult: BatchSchedulerResult(
                scoresByAssetID: [asset.id: TestFixtures.makeAIScore(provider: "mock-cloud", overall: 80, recommended: false)],
                groupCommentsByID: [:],
                recommendedByGroupID: [group.id: []],
                costRecords: [
                    CostRecord(id: UUID(), modelName: "Primary Model", inputTokens: 1000, outputTokens: 500, cost: 6.4, timestamp: .now)
                ]
            )
        )

        let store = ProjectStore(
            enableImportMonitoring: false,
            visionProviderFactory: { _ in StoreVisionProviderStub() },
            batchSchedulerFactory: { scheduler }
        )
        TestFixtures.seedStore(store, assets: [asset], groups: [group])
        store.modelConfigs = [TestFixtures.makeModelConfig(name: "Primary Model")]
        store.aiScoringStrategy = .budget
        store.aiBudgetLimit = 5.0

        await store.startCloudScoring()

        XCTAssertEqual(store.lastErrorMessage, "AI 评分已超过预算阈值 $5.00")
        XCTAssertEqual(store.costTracker.totalCost, 6.4, accuracy: 0.0001)
    }
}

private struct StoreVisionProviderStub: VisionModelProvider {
    var id: String = "store-stub"
    var displayName: String = "Store Stub"
    var apiProtocol: APIProtocol = .openAICompatible
    var costPer100Images: Double = 0

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult {
        GroupScoreResult(photoResults: [], groupBest: [], groupComment: nil, usage: nil)
    }

    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult {
        DetailedAnalysisResult(
            suggestions: EditSuggestions(crop: nil, filterStyle: nil, adjustments: nil, hslAdjustments: nil, localEdits: nil, narrative: ""),
            rawResponse: nil,
            usage: nil
        )
    }

    func testConnection() async throws -> Bool {
        true
    }
}

private final class MockBatchScheduler: BatchScheduling, @unchecked Sendable {
    let groupResult: BatchSchedulerResult
    let detailSuggestions: [UUID: EditSuggestions]
    let detailCosts: [CostRecord]
    private(set) var detailAssetIDs: [UUID] = []

    init(
        groupResult: BatchSchedulerResult,
        detailSuggestions: [UUID: EditSuggestions] = [:],
        detailCosts: [CostRecord] = []
    ) {
        self.groupResult = groupResult
        self.detailSuggestions = detailSuggestions
        self.detailCosts = detailCosts
    }

    func scoreGroups(
        _ groups: [PhotoGroup],
        assetsByID: [UUID: MediaAsset],
        provider: any VisionModelProvider,
        modelConfig: ModelConfig,
        progress: @escaping @Sendable (BatchProgress) -> Void
    ) async throws -> BatchSchedulerResult {
        if let first = groups.first {
            progress(.init(completedGroups: 1, totalGroups: groups.count, currentGroupName: first.name))
        }
        return groupResult
    }

    func analyzeDetails(
        assetIDs: [UUID],
        assetsByID: [UUID: MediaAsset],
        groupsByID: [UUID: PhotoGroup],
        provider: any VisionModelProvider,
        modelConfig: ModelConfig
    ) async throws -> ([UUID: EditSuggestions], [CostRecord]) {
        detailAssetIDs = assetIDs
        return (detailSuggestions, detailCosts)
    }
}
