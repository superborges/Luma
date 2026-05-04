import Foundation

/// OpenAI 兼容协议（GPT-4o, DeepSeek, GLM-4V, 通义千问, Ollama 等）。
///
/// 请求形态：`POST {endpoint}/chat/completions`，多模态走 `image_url` data URL。
struct OpenAICompatibleProvider: VisionModelProvider {
    let id: String
    let displayName: String
    let endpoint: String
    let modelID: String
    let apiKey: String
    let httpClient: HTTPClient

    var apiProtocol: APIProtocol { .openAICompatible }

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
        // 用最小 payload（一句 ping）测试 endpoint + key 是否可达。
        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        let request = try buildRequest(body: try JSONSerialization.data(withJSONObject: body))
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)
        return true
    }

    // MARK: - Request 构造

    func buildRequest(body: Data) throws -> URLRequest {
        let url = try ProviderHTTPSupport.parseEndpoint(endpoint).appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        return req
    }

    func buildRequestBody(systemPrompt: String, userPrompt: String, images: [ProviderImagePayload]) throws -> Data {
        var userContent: [[String: Any]] = [["type": "text", "text": userPrompt]]
        for image in images {
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)"]
            ])
        }
        // 不发送 `response_format: json_object`：该字段是 OpenAI 官方扩展，
        // Ollama / 多数自部署的兼容服务不支持，会直接 400。统一靠 PromptBuilder
        // 中的 system 约束 "Respond ONLY in JSON" 来保证 JSON-only 输出。
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.2
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

}
