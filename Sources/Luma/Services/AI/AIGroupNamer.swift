import Foundation

/// AI 组名生成器：给一组照片的代表帧发 API，返回 ≤ 8 个汉字的描述性名称。
/// 对所有组串行调用（避免并发导致费用不可控）。
enum AIGroupNamer {

    struct NamingResult: Sendable {
        let groupID: UUID
        let name: String
        let isAIGenerated: Bool
    }

    /// 为多个组串行生成 AI 名称。
    static func generateNames(
        groups: [PhotoGroup],
        assets: [MediaAsset],
        config: ModelConfig,
        apiKey: String,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        onResult: @MainActor (NamingResult) async -> Void
    ) async {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        for group in groups {
            let result = await generateSingleName(
                group: group,
                assetsByID: assetsByID,
                config: config,
                apiKey: apiKey,
                httpClient: httpClient
            )
            await onResult(result)
        }
    }

    static let maxRepresentativePhotos = 5

    /// 为单个组生成名称。失败时 fallback 到原有名称。
    static func generateSingleName(
        group: PhotoGroup,
        assetsByID: [UUID: MediaAsset],
        config: ModelConfig,
        apiKey: String,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) async -> NamingResult {
        let allURLs: [URL] = group.assets.compactMap { assetID -> URL? in
            guard let asset = assetsByID[assetID] else { return nil }
            return asset.previewURL ?? asset.thumbnailURL
        }

        guard !allURLs.isEmpty else {
            return NamingResult(groupID: group.id, name: group.name, isAIGenerated: false)
        }

        let sampledURLs = evenSample(from: allURLs, count: maxRepresentativePhotos)

        var payloads: [ProviderImagePayload] = []
        for url in sampledURLs {
            if let p = await ImagePayloadBuilder.payload(from: url) {
                payloads.append(p)
            }
        }
        guard !payloads.isEmpty else {
            return NamingResult(groupID: group.id, name: group.name, isAIGenerated: false)
        }

        let locationStr = group.location.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) }
        let prompt = PromptBuilder.groupNamingPrompt(
            currentName: group.name,
            location: locationStr,
            photoCount: payloads.count
        )

        do {
            let rawText = try await callModel(
                systemPrompt: prompt.system,
                userPrompt: prompt.user,
                images: payloads,
                config: config,
                apiKey: apiKey,
                httpClient: httpClient
            )
            let name = extractGroupName(from: rawText, fallback: group.name)
            return NamingResult(groupID: group.id, name: name, isAIGenerated: true)
        } catch {
            return NamingResult(groupID: group.id, name: group.name, isAIGenerated: false)
        }
    }

    /// 从 AI 返回的文本中提取组名（≤ 8 汉字）。
    static func extractGroupName(from text: String, fallback: String) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(8))
    }

    /// 从数组中均匀采样 count 个元素，保持原始顺序。
    static func evenSample<T>(from array: [T], count: Int) -> [T] {
        guard array.count > count else { return array }
        let step = Double(array.count) / Double(count)
        return (0..<count).map { array[Int(Double($0) * step)] }
    }

    // MARK: - HTTP 调用

    private static func callModel(
        systemPrompt: String,
        userPrompt: String,
        images: [ProviderImagePayload],
        config: ModelConfig,
        apiKey: String,
        httpClient: HTTPClient
    ) async throws -> String {
        let params = ProviderHTTPSupport.LightRequestParams(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            config: config,
            apiKey: apiKey,
            temperature: 0.3,
            maxTokens: 50
        )
        let request = try ProviderHTTPSupport.buildLightRequest(params)
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)
        return ProviderHTTPSupport.extractPlainText(from: data, apiProtocol: config.apiProtocol)
    }
}
