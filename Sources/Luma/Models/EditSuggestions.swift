import Foundation

struct EditSuggestions: Codable, Hashable {
    let crop: CropSuggestion?
    let filterStyle: FilterSuggestion?
    let adjustments: AdjustmentValues?
    let hslAdjustments: [HSLAdjustment]?
    let localEdits: [LocalEdit]?
    let narrative: String
}

struct CropSuggestion: Codable, Hashable {
    let needed: Bool
    let ratio: String
    let direction: String
    let rule: String
    let top: Double?
    let bottom: Double?
    let left: Double?
    let right: Double?
    let angle: Double?
}

struct FilterSuggestion: Codable, Hashable {
    let primary: String
    let reference: String
    let mood: String
}

struct AdjustmentValues: Codable, Hashable {
    let exposure: Double?
    let contrast: Int?
    let highlights: Int?
    let shadows: Int?
    let temperature: Int?
    let tint: Int?
    let saturation: Int?
    let vibrance: Int?
    let clarity: Int?
    let dehaze: Int?
}

struct HSLAdjustment: Codable, Hashable {
    let color: String
    let hue: Int?
    let saturation: Int?
    let luminance: Int?
}

struct LocalEdit: Codable, Hashable {
    let area: String
    let action: String
}
