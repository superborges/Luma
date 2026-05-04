import XCTest
@testable import Luma

/// 测试 requestEditSuggestions 流程的关键分支：
/// - 未配置 premiumFallback 时 → failed 状态
/// - applyEditSuggestionsResult 正确写回 manifest
/// - hasPremiumFallbackModel 反映配置变化
///
/// 注：真实 Provider 调用走 `AIContractIntegrationTests`（XCTSkip 模式）。
@MainActor
final class EditSuggestionsFlowTests: XCTestCase {

    func testRequestEditSuggestionsFailsWhenNoPremiumModelConfigured() async {
        let store = ProjectStore()
        store.modelConfigStore = InMemoryModelConfigStore()

        let asset = TestFixtures.makeAsset(baseName: "X", captureDate: TestFixtures.makeDate(hour: 9))
        TestFixtures.seedStore(store, assets: [asset], groups: [])

        await store.requestEditSuggestions(for: asset.id)
        guard case let .failed(message) = store.editSuggestionsRequestStatus[asset.id] else {
            XCTFail("应失败，实为 \(String(describing: store.editSuggestionsRequestStatus[asset.id]))")
            return
        }
        XCTAssertTrue(message.contains("premiumFallback"))
    }

    func testRequestEditSuggestionsFailsWhenAssetNotFound() async {
        let store = ProjectStore()
        store.modelConfigStore = InMemoryModelConfigStore()
        await store.requestEditSuggestions(for: UUID())
        let status = store.editSuggestionsRequestStatus[UUID()]
        // 未匹配 asset 时不会写入新条目；这里主要验证不 crash
        XCTAssertNil(status)
    }

    func testApplyEditSuggestionsResultPersistsToAsset() {
        let store = ProjectStore()
        store.modelConfigStore = InMemoryModelConfigStore()

        let asset = TestFixtures.makeAsset(baseName: "X", captureDate: TestFixtures.makeDate(hour: 9))
        TestFixtures.seedStore(store, assets: [asset], groups: [])

        let result = DetailedAnalysisResult(
            crop: CropSuggestion(
                needed: true, ratio: "16:9", direction: "向右裁切", rule: "rule_of_thirds",
                top: 0.0, bottom: 1.0, left: 0.05, right: 0.95, angle: nil
            ),
            filterStyle: FilterSuggestion(primary: "warm_golden_hour", reference: "VSCO A6", mood: "温暖怀旧"),
            adjustments: AdjustmentValues(
                exposure: 0.3, contrast: 10, highlights: -20, shadows: 15,
                temperature: 300, tint: -5, saturation: 5, vibrance: 10, clarity: 5, dehaze: 0
            ),
            hsl: [HSLAdjustment(color: "orange", hue: -5, saturation: 15, luminance: 0)],
            localEdits: [LocalEdit(area: "天空", action: "压暗高光")],
            narrative: "整体氛围温暖怀旧",
            usage: TokenUsage(inputTokens: 500, outputTokens: 300)
        )

        store.applyEditSuggestionsResult(assetID: asset.id, result: result)

        let updated = store.assets.first(where: { $0.id == asset.id })
        XCTAssertEqual(updated?.editSuggestions?.crop?.ratio, "16:9")
        XCTAssertEqual(updated?.editSuggestions?.filterStyle?.primary, "warm_golden_hour")
        XCTAssertEqual(updated?.editSuggestions?.adjustments?.exposure, 0.3)
        XCTAssertEqual(updated?.editSuggestions?.hslAdjustments?.first?.color, "orange")
        XCTAssertEqual(updated?.editSuggestions?.localEdits?.first?.area, "天空")
        XCTAssertEqual(updated?.editSuggestions?.narrative, "整体氛围温暖怀旧")
    }

    func testHasPremiumFallbackModelReflectsConfig() throws {
        let store = ProjectStore()
        let mockStore = InMemoryModelConfigStore()
        store.modelConfigStore = mockStore
        XCTAssertFalse(store.hasPremiumFallbackModel)

        let primary = ModelConfig(
            name: "Primary", apiProtocol: .openAICompatible,
            endpoint: "https://example.com", modelID: "m1",
            role: .primary, isActive: true
        )
        try mockStore.saveConfigs([primary])
        XCTAssertFalse(store.hasPremiumFallbackModel, "primary 不应被识别为 premiumFallback")

        let premium = ModelConfig(
            name: "Premium", apiProtocol: .anthropicMessages,
            endpoint: "https://example.com", modelID: "m2",
            role: .premiumFallback, isActive: true
        )
        try mockStore.saveConfigs([primary, premium])
        XCTAssertTrue(store.hasPremiumFallbackModel)

        // isActive=false 时不应识别
        let inactive = ModelConfig(
            id: premium.id,
            name: premium.name, apiProtocol: premium.apiProtocol,
            endpoint: premium.endpoint, modelID: premium.modelID,
            role: .premiumFallback, isActive: false
        )
        try mockStore.saveConfigs([primary, inactive])
        XCTAssertFalse(store.hasPremiumFallbackModel)
    }
}
