import Foundation
import LoopKit

extension Array where Element == PumpHistoryEvent {
    /// Convert ANY numeric type into Double safely
    private func toDouble(_ any: Any?) -> Double {
        switch any {
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let dec as Decimal:
            return NSDecimalNumber(decimal: dec).doubleValue
        case let str as String:
            return Double(str) ?? 0.0
        case let num as NSNumber:
            return num.doubleValue
        default:
            return 0.0
        }
    }

    /// Convert ANY value into a Date
    private func toDate(_ any: Any?) -> Date? {
        switch any {
        case let date as Date:
            return date

        case let ts as TimeInterval: // seconds since 1970
            return Date(timeIntervalSince1970: ts)

        case let int as Int: // unix int
            return Date(timeIntervalSince1970: TimeInterval(int))

        case let str as String:
            // Try ISO 8601 first
            if let iso = ISO8601DateFormatter().date(from: str) {
                return iso
            }

            // Try timestamp-in-string
            if let ts = Double(str) {
                return Date(timeIntervalSince1970: ts)
            }

            return nil

        default:
            return nil
        }
    }

    func asDoseEntries() -> [DoseEntry] {
        compactMap { event in

            let start = toDate(event.timestamp) ?? Date()
            let end = toDate(event.endTimestamp) ?? start

            switch event.type {
            // ----------------------------
            // BOLUS
            // ----------------------------
            case .bolus:
                let value = toDouble(event.amount)
                return DoseEntry(
                    type: .bolus,
                    startDate: start,
                    endDate: end,
                    value: value,
                    unit: .units
                )

            // ----------------------------
            // TEMP BASAL
            // ----------------------------
            case .tempBasal:
                let rate = toDouble(event.rate)
                return DoseEntry(
                    type: .tempBasal,
                    startDate: start,
                    endDate: end,
                    value: rate,
                    unit: .unitsPerHour
                )

            default:
                return nil
            }
        }
    }
}
