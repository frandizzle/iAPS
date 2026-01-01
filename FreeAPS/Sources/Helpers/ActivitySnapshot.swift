import Foundation
import HealthKit

// MARK: - Snapshot model

/// Aggregated step data over fixed time windows
struct ActivitySnapshot {
    let steps5: Int
    let steps10: Int
    let steps15: Int
    let steps30: Int
    let steps60: Int

    let spm5: Double
    let spm10: Double
    let spm15: Double
    let spm30: Double
    let spm60: Double

    let lastUpdate: Date
}

// MARK: - Activity state

enum ActivityState: String {
    case rest
    case light
    case moderate
    case high
}

// MARK: - Activity manager

final class ActivityManager {
    // MARK: Singleton

    static let shared = ActivityManager()
    private init() {}

    // MARK: HealthKit

    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

    // MARK: State

    private(set) var cachedISFReduction: Double = 0.0
    private(set) var snapshot: ActivitySnapshot?
    private(set) var state: ActivityState = .rest
    private var originalReduction: Double = 0.0

    // MARK: Settings-backed knobs (defaults match your current hardcoded behavior)

    var enabled: Bool = true

    // Gate: minimum steps in last 15 minutes before ANY effect
    var minStepsForAnyEffect: Int = 150

    // Classification thresholds (SPM over 5 minutes)
    var lightSPMThreshold: Double = 10.0
    var moderateSPMThreshold: Double = 40.0
    var highSPMThreshold: Double = 70.0

    // Reduction DELTAS (subtracted from AutoISF ratio)
    var lightReductionDelta: Double = 0.2
    var moderateReductionDelta: Double = 0.3
    var highReductionDelta: Double = 0.5

    // Hold / hysteresis
    private var holdCounter: Int = 0
    var holdLoops: Int = 3 // <- must be var to be configurable
    var holdLoopsRemaining: Int { holdCounter }

    // MARK: Apply FreeAPS settings

    /// Call this before refreshActivity(), or whenever settings change.
    func applySettings(_ s: FreeAPSSettings) {
        func bool(_ any: Any?, _ fallback: Bool) -> Bool {
            if let v = any as? Bool { return v }
            if let v = any as? NSNumber { return v.boolValue }
            if let v = any as? String {
                let lower = v.lowercased()
                if lower == "true" || lower == "1" { return true }
                if lower == "false" || lower == "0" { return false }
            }
            return fallback
        }

        func int(_ any: Any?, _ fallback: Int) -> Int {
            if let v = any as? Int { return v }
            if let v = any as? NSNumber { return v.intValue }
            if let v = any as? Double { return Int(v.rounded()) }
            if let v = any as? Decimal { return NSDecimalNumber(decimal: v).intValue }
            if let v = any as? String, let d = Double(v) { return Int(d.rounded()) }
            return fallback
        }

        func dbl(_ any: Any?, _ fallback: Double) -> Double {
            if let v = any as? Double { return v }
            if let v = any as? NSNumber { return v.doubleValue }
            if let v = any as? Int { return Double(v) }
            if let v = any as? Decimal { return NSDecimalNumber(decimal: v).doubleValue }
            if let v = any as? String, let d = Double(v) { return d }
            return fallback
        }

        // ────────────────────────────────────────────────
        // Apply settings
        // ────────────────────────────────────────────────
        let wasEnabled = enabled
        let newEnabled = bool(s.stepsISFEnabled, enabled)
        enabled = newEnabled

        // If just disabled → clear everything immediately
        if wasEnabled, !enabled {
            cachedISFReduction = 0.0
            holdCounter = 0
            state = .rest
        }

        // Gate
        minStepsForAnyEffect = int(s.stepsMinThreshold15, minStepsForAnyEffect)

        // Thresholds
        lightSPMThreshold = dbl(s.stepsLightSPMThreshold5, lightSPMThreshold)
        moderateSPMThreshold = dbl(s.stepsModerateSPMThreshold5, moderateSPMThreshold)
        highSPMThreshold = dbl(s.stepsHighSPMThreshold5, highSPMThreshold)

        // Reductions
        lightReductionDelta = dbl(s.stepsLightReductionDelta, lightReductionDelta)
        moderateReductionDelta = dbl(s.stepsModerateReductionDelta, moderateReductionDelta)
        highReductionDelta = dbl(s.stepsHighReductionDelta, highReductionDelta)

        // Hold
        holdLoops = max(0, int(s.stepsHoldLoops, holdLoops))
    }

    // MARK: Permissions

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        healthStore.requestAuthorization(
            toShare: [],
            read: [stepType]
        ) { success, _ in
            completion?(success)
        }
    }

    // MARK: Refresh snapshot

    /// Call once per loop cycle before AutoISF merge
    func refreshActivity(completion: ((ActivitySnapshot?) -> Void)? = nil) {
        guard enabled else {
            completion?(snapshot)
            return
        }

        let now = Date()

        let t5 = now.addingTimeInterval(-5 * 60)
        let t10 = now.addingTimeInterval(-10 * 60)
        let t15 = now.addingTimeInterval(-15 * 60)
        let t30 = now.addingTimeInterval(-30 * 60)
        let t60 = now.addingTimeInterval(-60 * 60)

        func sumSteps(from start: Date, completion: @escaping (Int) -> Void) {

            // ⏱ Buffer the start time to avoid HK boundary issues
            let bufferedStart = start.addingTimeInterval(-60)

            let predicate = HKQuery.predicateForSamples(
                withStart: bufferedStart,
                end: now,
                options: []
            )

            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let total = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                completion(Int(total))
            }

            healthStore.execute(query)
        }

        sumSteps(from: t5) { s5 in
            sumSteps(from: t10) { s10 in
                sumSteps(from: t15) { s15 in
                    sumSteps(from: t30) { s30 in
                        sumSteps(from: t60) { s60 in

                            let snap = ActivitySnapshot(
                                steps5: s5,
                                steps10: s10,
                                steps15: s15,
                                steps30: s30,
                                steps60: s60,
                                spm5: Double(s5) / 5.0,
                                spm10: Double(s10) / 10.0,
                                spm15: Double(s15) / 15.0,
                                spm30: Double(s30) / 30.0,
                                spm60: Double(s60) / 60.0,
                                lastUpdate: now
                            )

                            self.snapshot = snap
                            self.state = self.classify(snapshot: snap)

                            // ✅ IMPORTANT: use hold/decay logic (previous code bypassed this)
                            let raw = self.autoISFReductionRaw()
                            self.updateISFReduction(rawReduction: raw)

                            completion?(snap)
                        }
                    }
                }
            }
        }
    }

    // MARK: - ISF reduction hold / decay

    func updateISFReduction(rawReduction: Double) {
        if rawReduction > 0 {
            // New or continued activity → reset hold
            cachedISFReduction = rawReduction
            originalReduction = rawReduction // Store for hold period
            holdCounter = holdLoops
        } else if holdCounter > 0 {
            // No new activity, but still holding
            holdCounter -= 1

            // Keep full reduction value during hold period
            // Example with holdLoops=3, originalReduction=0.3:
            //   Loop 1: holdCounter=2, keep 0.3
            //   Loop 2: holdCounter=1, keep 0.3
            //   Loop 3: holdCounter=0, drop to 0.0
            if holdCounter > 0 {
                cachedISFReduction = originalReduction
            } else {
                cachedISFReduction = 0.0
                originalReduction = 0.0
            }
        } else {
            // Fully expired
            cachedISFReduction = 0.0
            originalReduction = 0.0
        }
    }

    /// Clear all cached reduction and reset state (used when feature is disabled)
    func clearReduction() {
        cachedISFReduction = 0.0
        originalReduction = 0.0
        holdCounter = 0
        state = .rest
    }

    // MARK: Classification

    private func classify(snapshot: ActivitySnapshot) -> ActivityState {
        // Ignore trivial movement (15-min gate)
        if snapshot.steps15 < minStepsForAnyEffect {
            return .rest
        }

        // Fast reaction uses 5-minute SPM
        let spm = snapshot.spm5

        if spm >= highSPMThreshold {
            return .high
        } else if spm >= moderateSPMThreshold {
            return .moderate
        } else if spm >= lightSPMThreshold {
            return .light
        }

        return .rest
    }

    // MARK: AutoISF integration

    /// Raw reduction delta (before hold/decay).
    /// This should NOT write cachedISFReduction directly.
    private func autoISFReductionRaw() -> Double {
        guard enabled else {
            print("AISFReduction: disabled")
            return 0.0
        }

        guard let snap = snapshot else {
            print("AISFReduction: snapshot nil")
            return 0.0
        }

        print("AISFReduction: steps15=\(snap.steps15), state=\(state)")

        if snap.steps15 < minStepsForAnyEffect {
            return 0.0
        }

        switch state {
        case .rest: return 0.0
        case .light: return lightReductionDelta
        case .moderate: return moderateReductionDelta
        case .high: return highReductionDelta
        }
    }

    // MARK: Background refresh

    private var refreshTimer: Timer?

    func startBackgroundRefresh(interval: TimeInterval = 300) { // Every 5 minutes
        stopBackgroundRefresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshActivity { snap in
                if let snap = snap {
                    debug(
                        .openAPS,
                        "Background activity refresh: steps15=\(snap.steps15), state=\(self?.state.rawValue ?? "unknown")"
                    )
                }
            }
        }

        // Do initial refresh
        refreshActivity(completion: nil)
    }

    func stopBackgroundRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: Debug / UI helper

    func activitySummaryString() -> String? {
        // Show explicit OFF state
        guard enabled else {
            return "Steps: OFF"
        }

        guard let snap = snapshot else {
            return "Steps: —"
        }

        return
            "Steps 5m: \(snap.steps5), " +
            "10m: \(snap.steps10), " +
            "15m: \(snap.steps15), " +
            "30m: \(snap.steps30), " +
            "60m: \(snap.steps60), " +
            "State: \(state.rawValue), " +
            "ISFΔ: \(String(format: "%.2f", cachedISFReduction))"
    }
}
