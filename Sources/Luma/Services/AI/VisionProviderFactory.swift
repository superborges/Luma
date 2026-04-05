import Foundation

enum VisionProviderFactory {
    static func makeProvider(config: ModelConfig) -> any VisionModelProvider {
        switch config.apiProtocol {
        case .openAICompatible:
            return OpenAICompatibleProvider(config: config)
        case .googleGemini:
            return GeminiProvider(config: config)
        case .anthropicMessages:
            return AnthropicProvider(config: config)
        }
    }
}
