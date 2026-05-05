import Foundation

enum LumaError: LocalizedError {
    case userCancelled
    case unsupported(String)
    case notImplemented(String)
    case importFailed(String)
    case persistenceFailed(String)
    case configurationInvalid(String)
    case networkFailed(String)
    case aiProvider(code: Int, message: String)
    case keychainUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "The operation was cancelled."
        case .unsupported(let message):
            return message
        case .notImplemented(let feature):
            return "\(feature) is not implemented yet."
        case .importFailed(let message):
            return message
        case .persistenceFailed(let message):
            return message
        case .configurationInvalid(let message):
            return message
        case .networkFailed(let message):
            return message
        case .aiProvider(let code, let message):
            return "AI 服务返回错误（\(code)）：\(message)"
        case .keychainUnavailable(let message):
            return "Keychain 不可用：\(message)"
        }
    }
}
