import Foundation

struct ModelConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var apiProtocol: APIProtocol
    var endpoint: String
    var apiKeyReference: String?
    var modelId: String
    var isActive: Bool
    var role: ModelRole
    var maxConcurrency: Int
    var costPerInputToken: Double?
    var costPerOutputToken: Double?
    var calibrationOffset: Double

    var resolvedEndpoint: String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch apiProtocol {
        case .openAICompatible:
            return "https://api.openai.com/v1"
        case .googleGemini:
            return "https://generativelanguage.googleapis.com"
        case .anthropicMessages:
            return "https://api.anthropic.com/v1/messages"
        }
    }

    var keychainAccount: String {
        apiKeyReference ?? "model-\(id.uuidString)"
    }
}

enum APIProtocol: String, Codable, Hashable, CaseIterable, Identifiable {
    case openAICompatible
    case googleGemini
    case anthropicMessages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI Compatible"
        case .googleGemini:
            return "Google Gemini"
        case .anthropicMessages:
            return "Anthropic Messages"
        }
    }
}

enum ModelRole: String, Codable, Hashable, CaseIterable, Identifiable {
    case primary
    case premiumFallback

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary:
            return "Primary"
        case .premiumFallback:
            return "Premium Fallback"
        }
    }
}

enum AIScoringStrategy: String, Codable, Hashable, CaseIterable, Identifiable {
    case budget
    case balanced
    case bestQuality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .budget:
            return "省钱模式"
        case .balanced:
            return "均衡模式"
        case .bestQuality:
            return "最佳质量"
        }
    }
}
