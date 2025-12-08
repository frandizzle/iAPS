import Foundation

struct AutoDIAHistoryEntry: Codable, Equatable, Identifiable {
    let timestamp: Date
    let diaHours: Double
    let peakMinutes: Double

    var id: Date { timestamp }
}
