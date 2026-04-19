import Foundation
import Observation

@Observable
final class CostTracker {
    private(set) var records: [CostRecord] = []

    var totalCost: Double {
        records.reduce(0) { $0 + $1.cost }
    }

    func record(_ record: CostRecord) {
        records.append(record)
    }

    func reset() {
        records.removeAll()
    }
}

struct CostRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let timestamp: Date
}
