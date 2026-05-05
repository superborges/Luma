import XCTest
@testable import Luma

/// MockProvider：根据 ModelConfig + apiKey 生成可预设的 stub Provider，验证 Coordinator 编排。
private struct StubProvider: VisionModelProvider {
    let id: String
    let displayName: String
    let apiProtocol: APIProtocol
    let onScore: @Sendable (GroupContext, Int) async throws -> GroupScoreResult

    func scoreGroup(images: [ProviderImagePayload], context: GroupContext) async throws -> GroupScoreResult {
        try await onScore(context, images.count)
    }

    func detailedAnalysis(image: ProviderImagePayload, context: PhotoContext) async throws -> DetailedAnalysisResult {
        throw LumaError.notImplemented("Stub")
    }

    func testConnection() async throws -> Bool { true }
}

private struct StubFactory: ProviderFactory {
    let onScore: @Sendable (GroupContext, Int) async throws -> GroupScoreResult

    func makeProvider(config: ModelConfig, apiKey: String) -> any VisionModelProvider {
        StubProvider(
            id: config.id.uuidString,
            displayName: config.name,
            apiProtocol: config.apiProtocol,
            onScore: onScore
        )
    }
}

@MainActor
final class CloudScoringCoordinatorTests: XCTestCase {

    func testStartFailsWhenNoActiveModelConfigured() async throws {
        let store = InMemoryModelConfigStore()
        let coord = CloudScoringCoordinator(
            providerFactory: StubFactory(onScore: { _, _ in throw LumaError.unsupported("n/a") }),
            modelConfigStore: store,
            jobStore: InMemoryScoringJobStore()
        )
        try await TestFixtures.withTemporaryDirectory(prefix: "Coord") { dir in
            do {
                try await coord.start(
                    strategy: .balanced,
                    groups: [makeGroup()],
                    assets: [],
                    in: dir,
                    thresholdUSD: 5,
                    onGroupResult: { _, _, _ in }
                )
                XCTFail("应抛错")
            } catch let LumaError.configurationInvalid(message) {
                XCTAssertTrue(message.contains("primary"))
            } catch {
                XCTFail("错误类型不对：\(error)")
            }
        }
    }

    func testStartFailsForLocalStrategy() async throws {
        let store = InMemoryModelConfigStore()
        let coord = CloudScoringCoordinator(
            providerFactory: StubFactory(onScore: { _, _ in throw LumaError.unsupported("n/a") }),
            modelConfigStore: store,
            jobStore: InMemoryScoringJobStore()
        )
        try await TestFixtures.withTemporaryDirectory(prefix: "Coord") { dir in
            do {
                try await coord.start(
                    strategy: .local,
                    groups: [makeGroup()],
                    assets: [],
                    in: dir,
                    thresholdUSD: 5,
                    onGroupResult: { _, _, _ in }
                )
                XCTFail("应抛错")
            } catch let LumaError.unsupported(message) {
                XCTAssertTrue(message.contains("ScoringStrategy.local"))
            } catch {
                XCTFail("错误类型不对：\(error)")
            }
        }
    }

    func testApplyGroupScoreResultUpdatesAssetsAndGroup() async throws {
        let store = ProjectStore()
        let asset1 = TestFixtures.makeAsset(baseName: "A", captureDate: TestFixtures.makeDate(hour: 9))
        let asset2 = TestFixtures.makeAsset(baseName: "B", captureDate: TestFixtures.makeDate(hour: 10))
        let asset3 = TestFixtures.makeAsset(baseName: "C", captureDate: TestFixtures.makeDate(hour: 11))
        let group = TestFixtures.makeGroup(name: "Test", assets: [asset1, asset2, asset3])
        TestFixtures.seedStore(store, assets: [asset1, asset2, asset3], groups: [group])

        let result = GroupScoreResult(
            perPhoto: [
                PerPhotoScore(
                    index: 1,
                    scores: PhotoScores(composition: 80, exposure: 70, color: 75, sharpness: 85, story: 60),
                    overall: 74,
                    comment: "构图不错",
                    recommended: true
                ),
                PerPhotoScore(
                    index: 2,
                    scores: PhotoScores(composition: 60, exposure: 50, color: 55, sharpness: 65, story: 40),
                    overall: 54,
                    comment: "一般",
                    recommended: false
                )
            ],
            groupBest: [1],
            groupComment: "整组主题清晰",
            usage: TokenUsage(inputTokens: 1000, outputTokens: 200)
        )

        let modelConfig = ModelConfig(
            name: "Gemini Flash",
            apiProtocol: .googleGemini,
            endpoint: "https://generativelanguage.googleapis.com",
            modelID: "gemini-2.0-flash"
        )

        await store.applyGroupScoreResult(groupID: group.id, result: result, providerConfig: modelConfig)

        let updatedAsset1 = store.assets.first(where: { $0.id == asset1.id })
        XCTAssertEqual(updatedAsset1?.aiScore?.overall, 74)
        XCTAssertEqual(updatedAsset1?.aiScore?.recommended, true)
        XCTAssertTrue(updatedAsset1?.aiScore?.provider.hasPrefix("cloud:") == true)

        let updatedAsset2 = store.assets.first(where: { $0.id == asset2.id })
        XCTAssertEqual(updatedAsset2?.aiScore?.overall, 54)

        // 第 3 张未在 perPhoto 中，应保持 nil
        let updatedAsset3 = store.assets.first(where: { $0.id == asset3.id })
        XCTAssertNil(updatedAsset3?.aiScore)

        // group_best=[1] → 推荐第一张 asset
        let updatedGroup = store.currentSession?.groups.first(where: { $0.id == group.id })
        XCTAssertEqual(updatedGroup?.recommendedAssets, [asset1.id])
        XCTAssertEqual(updatedGroup?.groupComment, "整组主题清晰")
    }

    // MARK: - Helpers

    private func makeGroup() -> PhotoGroup {
        PhotoGroup(
            id: UUID(),
            name: "g",
            assets: [],
            subGroups: [],
            timeRange: Date()...Date(),
            location: nil,
            groupComment: nil,
            recommendedAssets: []
        )
    }
}
