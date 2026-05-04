import Foundation

/// 抽象云端视觉模型，为上层（评分流水线、设置页测试连接）提供与协议无关的 API。
protocol VisionModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var apiProtocol: APIProtocol { get }

    func scoreGroup(images: [ProviderImagePayload], context: GroupContext) async throws -> GroupScoreResult
    func detailedAnalysis(image: ProviderImagePayload, context: PhotoContext) async throws -> DetailedAnalysisResult
    func testConnection() async throws -> Bool
}

/// 三个 Provider 共享的 HTTP 失败处理逻辑。
enum ProviderHTTPSupport {
    /// 检查 HTTP 状态码；非 2xx 抛 `LumaError.aiProvider`。
    /// 对常见错误（鉴权、不支持视觉、限速）做语义识别，给用户更友好的提示。
    static func ensureSuccess(_ response: HTTPURLResponse, body: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let raw = String(data: body, encoding: .utf8) ?? "<binary>"
        let friendly = humanReadableMessage(status: response.statusCode, body: raw)
        throw LumaError.aiProvider(code: response.statusCode, message: friendly)
    }

    /// 把原始服务端错误转成给用户看的简短中文消息。
    ///
    /// 设计取舍：
    /// - 仅对**特别明确**的模式（401 / 403 / 429 / 不支持视觉）给完全替换的诊断提示
    /// - 其他错误码（404 / 400 / 5xx）给中文前缀 + 服务端原始消息摘要，让用户看到 "model not found" 这种关键线索
    /// - 不要因为给"友好提示"而吞掉关键诊断信息
    static func humanReadableMessage(status: Int, body: String) -> String {
        let lowered = body.lowercased()

        // 特别明确的模式：完全替换消息
        if lowered.contains("image_url") || lowered.contains("unknown variant") {
            return "该模型不支持视觉输入（图像类型被服务端拒绝）。请换用支持多模态的模型，如 GPT-4o / Gemini / Claude / Qwen-VL / GLM-4V。"
        }
        if lowered.contains("does not support image") || lowered.contains("vision is not supported") {
            return "该模型不支持视觉输入。请使用支持多模态的模型。"
        }

        // 状态码前缀 + 截断的原始消息（保留可诊断信息）
        let prefix: String
        switch status {
        case 401: prefix = "API Key 无效或已过期"
        case 403: prefix = "API Key 没有权限访问该模型"
        case 404: prefix = "Model ID 不存在或 endpoint 错误"
        case 408: prefix = "请求超时"
        case 413: prefix = "请求体过大；图像可能过多或过大"
        case 429: prefix = "触发限速；请稍后再试或调低并发"
        case 500..<600: prefix = "服务端错误（HTTP \(status)）"
        default: prefix = "HTTP \(status)"
        }

        let snippet = extractServerMessage(body)
        if snippet.isEmpty { return prefix }
        return "\(prefix)：\(snippet)"
    }

    /// 从 API 响应 body 中提取人类可读的"主要错误消息"。
    /// 优先解析常见的 `error.message` / `message` / `error_message` JSON 字段；
    /// 失败时降级为整个 body 的前 200 字符。
    private static func extractServerMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return truncate(body, max: 200)
        }
        // OpenAI / OpenAI 兼容 / Anthropic 都常见 error.message 结构
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            return truncate(msg, max: 240)
        }
        if let msg = json["message"] as? String {
            return truncate(msg, max: 240)
        }
        if let msg = json["error_message"] as? String {
            return truncate(msg, max: 240)
        }
        // Gemini 错误格式：{"error":{"code":404,"message":"...","status":"NOT_FOUND"}}
        // 已被上面的分支覆盖
        return truncate(body, max: 200)
    }

    private static func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }

    /// 把 `NormalizerError` 转成 `LumaError.aiProvider`，保留可读原因。
    static func wrapNormalizerError(_ error: NormalizerError) -> LumaError {
        switch error {
        case .markdownFenceUnstripped:
            return .aiProvider(code: -1, message: "响应仍包含 markdown 代码围栏")
        case .malformedJSON(let reason):
            return .aiProvider(code: -2, message: "JSON 解析失败：\(reason)")
        case .missingField(let field):
            return .aiProvider(code: -3, message: "响应缺少字段：\(field)")
        case .protocolMismatch(let reason):
            return .aiProvider(code: -4, message: reason)
        }
    }

    /// 解析用户填写的 endpoint 字符串：去前后空白、去尾部 `/`，失败抛错。
    /// 不静默 fallback 到协议默认值——避免用户写错却看到"连接成功"。
    static func parseEndpoint(_ raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw LumaError.configurationInvalid("Endpoint 无效：\(raw)")
        }
        return url
    }
}
