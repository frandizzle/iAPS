import CoreMotion
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

    // MARK: Settings-backed knobs

    var enabled: Bool = true

    // Gate: minimum steps in last 15 minutes before ANY effect
    var minStepsForAnyEffect: Int = 150

    // Classification thresholds (SPM over 5 minutes)
    var lightSPMThreshold: Double = 10.0
    var moderateSPMThreshold: Double = 40.0
    var highSPMThreshold: Double = 70.0

    // Reduction DELTAS
    var lightReductionDelta: Double = 0.2
    var moderateReductionDelta: Double = 0.3
    var highReductionDelta: Double = 0.5

    // Hold / hysteresis
    private var holdCounter: Int = 0
    var holdLoops: Int = 3
    var holdLoopsRemaining: Int { holdCounter }

    // MARK: - LIVE PEDOMETER (CoreMotion)

    var livePedometerEnabled: Bool = true

    private let pedometer = CMPedometer()
    private var pedometerActive: Bool = false

    /// Timeline of (timestamp, cumulativeSteps)
    private var stepTimeline: [(Date, Int)] = []

    /// Keep ≥60 min + buffer
    private let timelineMaxAge: TimeInterval = 60 * 60 + 120

    /// Serialize timeline + snapshot updates
    private let timelineQueue = DispatchQueue(
        label: "ActivityManager.timelineQueue",
        qos: .utility
    )

    // MARK: Apply FreeAPS settings

    func applySettings(_ s: FreeAPSSettings) {
        func bool(_ any: Any?, _ fallback: Bool) -> Bool {
            if let v = any as? Bool { return v }
            if let v = any as? NSNumber { return v.boolValue }
            if let v = any as? String {
                let l = v.lowercased()
                if l == "true" || l == "1" { return true }
                if l == "false" || l == "0" { return false }
            }
            return fallback
        }

        func int(_ any: Any?, _ fallback: Int) -> Int {
            if let v = any as? Int { return v }
            if let v = any as? NSNumber { return v.intValue }
            if let v = any as? Double { return Int(v.rounded()) }
            if let v = any as? Decimal {
                return NSDecimalNumber(decimal: v).intValue
            }
            if let v = any as? String, let d = Double(v) {
                return Int(d.rounded())
            }
            return fallback
        }

        func dbl(_ any: Any?, _ fallback: Double) -> Double {
            if let v = any as? Double { return v }
            if let v = any as? NSNumber { return v.doubleValue }
            if let v = any as? Int { return Double(v) }
            if let v = any as? Decimal {
                return NSDecimalNumber(decimal: v).doubleValue
            }
            if let v = any as? String, let d = Double(v) { return d }
            return fallback
        }

        let wasEnabled = enabled
        enabled = bool(s.stepsISFEnabled, enabled)

        if wasEnabled, !enabled {
            clearReduction()
            stopLivePedometer()
        }

        minStepsForAnyEffect = int(s.stepsMinThreshold15, minStepsForAnyEffect)

        lightSPMThreshold = dbl(s.stepsLightSPMThreshold5, lightSPMThreshold)
        moderateSPMThreshold = dbl(s.stepsModerateSPMThreshold5, moderateSPMThreshold)
        highSPMThreshold = dbl(s.stepsHighSPMThreshold5, highSPMThreshold)

        lightReductionDelta = dbl(s.stepsLightReductionDelta, lightReductionDelta)
        moderateReductionDelta = dbl(s.stepsModerateReductionDelta, moderateReductionDelta)
        highReductionDelta = dbl(s.stepsHighReductionDelta, highReductionDelta)

        holdLoops = max(0, int(s.stepsHoldLoops, holdLoops))

        if enabled, livePedometerEnabled {
            startLivePedometer()
        }
    }

    // MARK: Permissions

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        healthStore.requestAuthorization(
            toShare: [],
            read: [stepType]
        ) { success, _ in completion?(success) }
    }

    func requestMotionPermission() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.queryPedometerData(
            from: Date().addingTimeInterval(-60),
            to: Date()
        ) { _, _ in }
    }

    // MARK: Live pedometer control

    private func ensureLivePedometerRunning() {
        guard enabled, livePedometerEnabled else { return }
        guard CMPedometer.isStepCountingAvailable() else { return }
        if !pedometerActive {
            startLivePedometer()
            debug(.openAPS, "Started CMPedometer live steps feed")
        }
    }

    func startLivePedometer() {
        guard enabled, livePedometerEnabled else { return }
        guard CMPedometer.isStepCountingAvailable() else { return }
        guard !pedometerActive else { return }

        pedometerActive = true

        timelineQueue.async {
            self.stepTimeline.removeAll(keepingCapacity: true)
        }

        let start = Date().addingTimeInterval(-3600)

        pedometer.startUpdates(from: start) { [weak self] data, error in
            guard let self = self else { return }
            guard let data = data, error == nil else { return }

            let now = Date()
            let cumulative = data.numberOfSteps.intValue

            self.timelineQueue.async {
                self.stepTimeline.append((now, cumulative))

                let cutoff = now.addingTimeInterval(-self.timelineMaxAge)
                while let first = self.stepTimeline.first,
                      first.0 < cutoff
                {
                    self.stepTimeline.removeFirst()
                }

                self.refreshActivityFromTimeline(now: now)
            }
        }
    }

    func stopLivePedometer() {
        pedometer.stopUpdates()
        pedometerActive = false
        timelineQueue.async {
            self.stepTimeline.removeAll()
        }
    }

    // MARK: Refresh snapshot

    func refreshActivity(completion: ((ActivitySnapshot?) -> Void)? = nil) {
        guard enabled else {
            completion?(snapshot)
            return
        }

        ensureLivePedometerRunning()

        if livePedometerEnabled, pedometerActive {
            // IMPORTANT: do this synchronously so snapshot/state/reduction are updated
            // before the caller continues (matches old HealthKit behavior).
            timelineQueue.sync {
                let now = Date()
                if !self.stepTimeline.isEmpty {
                    self.refreshActivityFromTimeline(now: now)
                }
            }

            completion?(self.snapshot)
            return
        }

        completion?(snapshot) // HK fallback retained elsewhere if needed
    }

    // MARK: Timeline-based snapshot builder

    // ⚠️ Must ONLY be called from timelineQueue

    private func cumulativeAtOrBefore(_ t: Date) -> Int? {
        for (ts, cum) in stepTimeline.reversed() {
            if ts <= t { return cum }
        }
        return stepTimeline.first?.1
    }

    private func refreshActivityFromTimeline(now: Date) {
        guard let endCum = stepTimeline.last?.1 else { return }

        func window(_ minutes: Double) -> Int {
            let start = now.addingTimeInterval(-minutes * 60)
            let startCum = cumulativeAtOrBefore(start) ?? endCum
            return max(0, endCum - startCum)
        }

        let snap = ActivitySnapshot(
            steps5: window(5),
            steps10: window(10),
            steps15: window(15),
            steps30: window(30),
            steps60: window(60),
            spm5: Double(window(5)) / 5.0,
            spm10: Double(window(10)) / 10.0,
            spm15: Double(window(15)) / 15.0,
            spm30: Double(window(30)) / 30.0,
            spm60: Double(window(60)) / 60.0,
            lastUpdate: now
        )

        snapshot = snap
        state = classify(snapshot: snap)

        let raw = autoISFReductionRaw()
        updateISFReduction(rawReduction: raw)
    }

    // MARK: - ISF reduction hold / decay

        func updateISFReduction(rawReduction: Double) {
            if rawReduction > 0 {
                // New or continued activity → reset hold
                cachedISFReduction = rawReduction
                originalReduction = rawReduction  // Store for hold period
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
        if snapshot.steps15 < minStepsForAnyEffect { return .rest }

        let spm = snapshot.spm5
        if spm >= highSPMThreshold { return .high }
        if spm >= moderateSPMThreshold { return .moderate }
        if spm >= lightSPMThreshold { return .light }
        return .rest
    }

    // MARK: AutoISF

    private func autoISFReductionRaw() -> Double {
        guard let snap = snapshot else { return 0 }
        if snap.steps15 < minStepsForAnyEffect { return 0 }

        switch state {
        case .rest: return 0
        case .light: return lightReductionDelta
        case .moderate: return moderateReductionDelta
        case .high: return highReductionDelta
        }
    }

    // MARK: Debug

    func activitySummaryString() -> String? {
        guard enabled else { return "Steps: OFF" }
        guard let snap = snapshot else { return "Steps: —" }

        let src = (livePedometerEnabled && pedometerActive) ? "LIVE" : "HK"
        return
            "Steps(\(src)) 5m: \(snap.steps5), " +
            "10m: \(snap.steps10), " +
            "15m: \(snap.steps15), " +
            "30m: \(snap.steps30), " +
            "60m: \(snap.steps60), " +
            "State: \(state.rawValue), " +
            "ISFΔ: \(String(format: "%.2f", cachedISFReduction))"
    }
}
