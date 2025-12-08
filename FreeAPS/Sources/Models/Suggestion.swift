import Foundation

struct Suggestion: JSON, Equatable {
    // MARK: - Core Suggestion Fields

    var reason: String
    var units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    var rate: Decimal?
    var duration: Int?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
    let carbsReq: Decimal?
    var temp: TempType?
    let bg: Decimal?
    let reservoir: Decimal?
    var timestamp: Date?
    var recieved: Bool?
    var targetBG: Decimal?

    // MARK: - AutoDIA Learning Output

    var autoDIA: Decimal? // learned DIA (hours)
    var autoPeak: Decimal? // learned peak time (minutes)
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

// MARK: - Coding Keys

extension Suggestion {
    private enum CodingKeys: String, CodingKey {
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case recieved
        case targetBG = "target_bg"

        // Auto-DIA fields
        case autoDIA = "auto_dia"
        case autoPeak = "auto_peak"
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

// MARK: - Helpers

extension Suggestion {
    /// List version for UI display (ISF, COB, IOB, etc)
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    /// Final conclusion line
    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
