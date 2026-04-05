import Foundation

enum LumaError: LocalizedError {
    case userCancelled
    case unsupported(String)
    case notImplemented(String)
    case importFailed(String)
    case persistenceFailed(String)
    case configurationInvalid(String)
    case networkFailed(String)

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
        }
    }
}
