import Foundation
import HealthKit
import LoopKit

struct SimpleGlucoseValue: GlucoseValue {
    let startDate: Date
    let quantity: HKQuantity

    init(date: Date, glucose: Double) {
        startDate = date
        quantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: glucose)
    }
}
