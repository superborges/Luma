import Foundation

// MARK: - 协议种类

/// 三种支持的视觉模型 API 协议。
enum APIProtocol: String, Codable, Hashable, CaseIterable, Sendable {
    case openAICompatible
    case googleGemini
    case anthropicMessages

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容"
        case .googleGemini: return "Google Gemini"
        case .anthropicMessages: return "Anthropic Claude"
        }
    }

    /// 协议默认 endpoint placeholder，仅用于设置页 UI。运行时以 `ModelConfig.endpoint` 为准。
    var defaultEndpointPlaceholder: String {
        switch self {
        case .openAICompatible: return "https://api.openai.com/v1"
        case .googleGemini: return "https://generativelanguage.googleapis.com"
        case .anthropicMessages: return "https://api.anthropic.com/v1"
        }
    }

    /// 协议常见 model id placeholder。
    var defaultModelIDPlaceholder: String {
        switch self {
        case .openAICompatible: return "gpt-4o-mini"
        case .googleGemini: return "gemini-2.0-flash"
        case .anthropicMessages: return "claude-3-5-sonnet-20241022"
        }
    }
}

/// 模型角色：用于三档评分策略中区分 primary（全量打分）与 premiumFallback（精评）。
enum ModelRole: String, Codable, Hashable, CaseIterable, Sendable {
    case primary
    case premiumFallback
}

/// 持久化的模型配置。**绝不**包含 API Key 字段；Key 单独走 Keychain。
struct ModelConfig: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var apiProtocol: APIProtocol
    var endpoint: String
    var modelID: String
    var role: ModelRole
    var isActive: Bool
    /// 该模型并发请求数上限。
    var maxConcurrency: Int
    /// 单价（USD per 1M tokens）。可选；用于 BudgetTracker 计费。
    var costPerInputTokenUSD: Double?
    var costPerOutputTokenUSD: Double?

    init(
        id: UUID = UUID(),
        name: String,
        apiProtocol: APIProtocol,
        endpoint: String,
        modelID: String,
        role: ModelRole = .primary,
        isActive: Bool = true,
        maxConcurrency: Int = 4,
        costPerInputTokenUSD: Double? = nil,
        costPerOutputTokenUSD: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.apiProtocol = apiProtocol
        self.endpoint = endpoint
        self.modelID = modelID
        self.role = role
        self.isActive = isActive
        self.maxConcurrency = max(1, maxConcurrency)
        self.costPerInputTokenUSD = costPerInputTokenUSD
        self.costPerOutputTokenUSD = costPerOutputTokenUSD
    }
}

// MARK: - 输入数据

/// Provider 接收的图像负载。`base64` 不含 data URL 前缀；`mimeType` 由调用方决定。
///
/// 注：原本叫 `ImageData`，但与 Foundation 概念易混淆，且语义不清晰（不知道是图像本身
/// 还是图像的元数据），改名为 `ProviderImagePayload` 强调"准备给 Provider 的载荷"。
struct ProviderImagePayload: Sendable {
    let base64: String
    let longEdgePixels: Int
    let mimeType: String

    static let defaultMimeType = "image/jpeg"
}

struct GroupContext: Sendable {
    let groupName: String
    let cameraModel: String?
    let lensModel: String?
    let timeRangeDescription: String?
}

struct PhotoContext: Sendable {
    let baseName: String
    let exif: EXIFData
    let groupName: String
    let initialOverallScore: Int?
}

// MARK: - 输出数据

/// 单张照片的评分结果（一个 PhotoGroup 内每张一项）。
struct PerPhotoScore: Codable, Hashable, Sendable {
    let index: Int
    let scores: PhotoScores
    let overall: Int
    let comment: String
    let recommended: Bool
}

/// 一次组评的完整结果。`groupBest` 索引相对于发送的图像数组。
struct GroupScoreResult: Codable, Hashable, Sendable {
    let perPhoto: [PerPhotoScore]
    let groupBest: [Int]
    let groupComment: String
    let usage: TokenUsage
}

/// 单张精评的修图建议结果。
struct DetailedAnalysisResult: Codable, Hashable, Sendable {
    let crop: CropSuggestion?
    let filterStyle: FilterSuggestion?
    let adjustments: AdjustmentValues?
    let hsl: [HSLAdjustment]?
    let localEdits: [LocalEdit]?
    let narrative: String
    let usage: TokenUsage
}

/// API 调用消耗的 token 统计。`outputTokens` 在某些协议未返回时为 0。
struct TokenUsage: Codable, Hashable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0)

    func cost(inputUSDPerMillion: Double?, outputUSDPerMillion: Double?) -> Double {
        let inUSD = (inputUSDPerMillion ?? 0) * Double(inputTokens) / 1_000_000.0
        let outUSD = (outputUSDPerMillion ?? 0) * Double(outputTokens) / 1_000_000.0
        return inUSD + outUSD
    }
}

// MARK: - 错误

/// `ResponseNormalizer` 内部错误。统一通过 `LumaError.aiProvider` 包装后抛给上层。
enum NormalizerError: Error, Equatable {
    case markdownFenceUnstripped
    case malformedJSON(reason: String)
    case missingField(String)
    case protocolMismatch(reason: String)
}
