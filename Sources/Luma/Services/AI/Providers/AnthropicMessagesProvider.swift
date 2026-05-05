import Foundation

/// Anthropic Claude Messages API。
///
/// 请求形态：`POST {endpoint}/messages`，图像走
/// `image { source { type: "base64", media_type, data } }`。
struct AnthropicMessagesProvider: VisionModelProvider {
    let id: String
    let displayName: String
    let endpoint: String
    let modelID: String
    let apiKey: String
    let httpClient: HTTPClient

    var apiProtocol: APIProtocol { .anthropicMessages }

    init(config: ModelConfig, apiKey: String, httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.id = config.id.uuidString
        self.displayName = config.name
        self.endpoint = config.endpoint
        self.modelID = config.modelID
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - VisionModelProvider

    func scoreGroup(images: [ProviderImagePayload], context: GroupContext) async throws -> GroupScoreResult {
        let prompt = PromptBuilder.groupScoringPrompt(context, photoCount: images.count)
        let body = try buildRequestBody(systemPrompt: prompt.system, userPrompt: prompt.user, images: images)
        let request = try buildRequest(body: body)
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)

        switch ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: apiProtocol) {
        case .success(let result): return result
        case .failure(let error): throw ProviderHTTPSupport.wrapNormalizerError(error)
        }
    }

    func detailedAnalysis(image: ProviderImagePayload, context: PhotoContext) async throws -> DetailedAnalysisResult {
        let prompt = PromptBuilder.detailedAnalysisPrompt(context)
        let body = try buildRequestBody(systemPrompt: prompt.system, userPrompt: prompt.user, images: [image])
        let request = try buildRequest(body: body)
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)

        switch ResponseNormalizer.normalizeDetailedAnalysisResponse(data, apiProtocol: apiProtocol) {
        case .success(let result): return result
        case .failure(let error): throw ProviderHTTPSupport.wrapNormalizerError(error)
        }
    }

    func testConnection() async throws -> Bool {
        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        let request = try buildRequest(body: try JSONSerialization.data(withJSONObject: body))
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)
        return true
    }

    // MARK: - Request 构造

    func buildRequest(body: Data) throws -> URLRequest {
        let url = try ProviderHTTPSupport.parseEndpoint(endpoint).appendingPathComponent("messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = body
        return req
    }

    func buildRequestBody(systemPrompt: String, userPrompt: String, images: [ProviderImagePayload]) throws -> Data {
        var content: [[String: Any]] = []
        for image in images {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mimeType,
                    "data": image.base64
                ]
            ])
        }
        content.append(["type": "text", "text": userPrompt])

        // max_tokens=2048 足够覆盖 group score（约 1500 token）和 detailed analysis（约 2000 token）。
        // 4096 会被部分小模型（如 Claude Haiku）拒绝，且无实际收益。
        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": content]],
            "temperature": 0.2
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

}
