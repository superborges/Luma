import Foundation

struct AIScore: Codable, Hashable {
    let provider: String
    let scores: PhotoScores
    let overall: Int
    let comment: String
    let recommended: Bool
    let timestamp: Date
}

struct PhotoScores: Codable, Hashable {
    let composition: Int
    let exposure: Int
    let color: Int
    let sharpness: Int
    let story: Int
}
