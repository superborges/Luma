import XCTest
@testable import Luma

/// V2 合约集成测试：用真实 API Key 跑一次端到端 group scoring + detailed analysis。
///
/// 配置：通过环境变量传入（见 `scripts/run-v2-contract-tests.sh`）。
/// 未配置 `LUMA_V2_AI_KEY` 时整体 `XCTSkip`，CI 默认不真打 API。
///
/// 设计取舍：
/// - 不读取 ProjectStore 状态；直接构造 Provider，验证「Prompt → 真实 API → ResponseNormalizer」全链路
/// - 用 `TestFixtures.makeJPEG` 生成 128px 占位图像，仅作为多模态 payload；不验证模型语义
/// - 失败时给清晰的诊断信息（缺哪个变量 / 哪一步出错）
final class AIContractIntegrationTests: XCTestCase {

    func testEndToEndGroupScoringAndDetailedAnalysis() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["LUMA_V2_AI_KEY"], !apiKey.isEmpty else {
            throw XCTSkip("未设置 LUMA_V2_AI_KEY，跳过合约测试")
        }
        let protoString = ProcessInfo.processInfo.environment["LUMA_V2_AI_PROTOCOL"] ?? "googleGemini"
        guard let apiProtocol = APIProtocol(rawValue: protoString) else {
            XCTFail("LUMA_V2_AI_PROTOCOL 无效: \(protoString)")
            return
        }
        let endpoint = ProcessInfo.processInfo.environment["LUMA_V2_AI_ENDPOINT"]
            ?? apiProtocol.defaultEndpointPlaceholder
        let modelID = ProcessInfo.processInfo.environment["LUMA_V2_AI_MODEL_ID"]
            ?? apiProtocol.defaultModelIDPlaceholder

        let config = ModelConfig(
            name: "Contract Test",
            apiProtocol: apiProtocol,
            endpoint: endpoint,
            modelID: modelID,
            role: .primary,
            isActive: true,
            maxConcurrency: 2
        )

        let provider = DefaultProviderFactory().makeProvider(config: config, apiKey: apiKey)

        // 1. testConnection
        let connected = try await provider.testConnection()
        XCTAssertTrue(connected, "测试连接失败")

        // 2. 准备图像 payload（128px 占位）
        try await TestFixtures.withTemporaryDirectory(prefix: "AIContract") { dir in
            let imageURL = dir.appendingPathComponent("a.jpg")
            try TestFixtures.makeJPEG(at: imageURL, size: CGSize(width: 256, height: 256))
            guard let payload = await ImagePayloadBuilder.payload(from: imageURL) else {
                XCTFail("ImagePayloadBuilder 返回 nil")
                return
            }

            // 3. group scoring
            let groupContext = GroupContext(
                groupName: "Contract Test Group",
                cameraModel: "Test Camera",
                lensModel: "Test Lens",
                timeRangeDescription: nil
            )
            let groupResult = try await provider.scoreGroup(images: [payload, payload], context: groupContext)
            XCTAssertEqual(groupResult.perPhoto.count, 2, "返回的照片数应等于发送数（实际：\(groupResult.perPhoto.count)）")
            XCTAssertGreaterThan(groupResult.usage.inputTokens, 0, "应消耗 input tokens")

            // 4. detailed analysis
            let exif = EXIFData(
                captureDate: Date(),
                gpsCoordinate: nil,
                focalLength: 35,
                aperture: 1.8,
                shutterSpeed: "1/250",
                iso: 200,
                cameraModel: "Test",
                lensModel: "Test",
                imageWidth: 256,
                imageHeight: 256
            )
            let photoContext = PhotoContext(
                baseName: "test.jpg",
                exif: exif,
                groupName: "Contract Test Group",
                initialOverallScore: 75
            )
            let detailed = try await provider.detailedAnalysis(image: payload, context: photoContext)
            XCTAssertFalse(detailed.narrative.isEmpty, "narrative 不应为空")
            XCTAssertGreaterThan(detailed.usage.inputTokens, 0)

            print("=== 合约测试通过 ===")
            print("group scoring tokens: in=\(groupResult.usage.inputTokens) out=\(groupResult.usage.outputTokens)")
            print("detailed analysis tokens: in=\(detailed.usage.inputTokens) out=\(detailed.usage.outputTokens)")
        }
    }
}
