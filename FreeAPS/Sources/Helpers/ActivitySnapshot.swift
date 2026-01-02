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
    var minStepsForAnyEffect: Int = 0

    // Defaults expressed as "steps in 5 minutes" (UI), internally stored as SPM
    // 60 steps / 5 min = 12 spm, 200/5=40 spm, 350/5=70 spm
    var lightSPMThreshold: Double = 60.0 / 5.0
    var moderateSPMThreshold: Double = 200.0 / 5.0
    var highSPMThreshold: Double = 350.0 / 5.0

    // Reduction DELTAS (subtracted from AutoISF ratio)
    var lightReductionDelta: Double = 0.2
    var moderateReductionDelta: Double = 0.3
    var highReductionDelta: Double = 0.5

    // Hold / hysteresis
    private var holdCounter: Int = 0
    var holdLoops: Int = 3
    var holdLoopsRemaining: Int { holdCounter }

    // MARK: - LIVE PEDOMETER (CoreMotion)

    /// Toggle live pedometer feed (CMPedometer). Keep this true unless you want HK-only.
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

        let wasEnabled = enabled
        enabled = bool(s.stepsISFEnabled, enabled)

        if wasEnabled, !enabled {
            clearReduction()
            stopLivePedometer()
        }

        // Gate
        minStepsForAnyEffect = int(s.stepsMinThreshold15, minStepsForAnyEffect)

        // Thresholds:
        // UI fields are "steps in 5 minutes", but classifier uses SPM (steps per minute),
        // so we convert: stepsPer5Min / 5.0 = SPM
        lightSPMThreshold = dbl(s.stepsLightSPMThreshold5, lightSPMThreshold * 5.0) / 5.0
        moderateSPMThreshold = dbl(s.stepsModerateSPMThreshold5, moderateSPMThreshold * 5.0) / 5.0
        highSPMThreshold = dbl(s.stepsHighSPMThreshold5, highSPMThreshold * 5.0) / 5.0

        // Reductions
        lightReductionDelta = dbl(s.stepsLightReductionDelta, lightReductionDelta)
        moderateReductionDelta = dbl(s.stepsModerateReductionDelta, moderateReductionDelta)
        highReductionDelta = dbl(s.stepsHighReductionDelta, highReductionDelta)

        // Hold
        holdLoops = max(0, int(s.stepsHoldLoops, holdLoops))

        // Ensure live pedometer if enabled
        if enabled, livePedometerEnabled {
            startLivePedometer()
        }
    }

    // MARK: Permissions

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, _ in
            completion?(success)
        }
    }

    /// Triggers Motion & Fitness permission prompt (best-effort).
    func requestMotionPermission() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.queryPedometerData(
            from: Date().addingTimeInterval(-60),
            to: Date()
        ) { _, _ in
            // no-op; prompts permission if needed
        }
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
        guard CMPedometer.isStepCountingAvailable() else {
            debug(.openAPS, "CMPedometer step counting not available")
            return
        }
        guard !pedometerActive else { return }

        pedometerActive = true

        timelineQueue.async {
            self.stepTimeline.removeAll(keepingCapacity: true)
        }

        let start = Date().addingTimeInterval(-3600) // 1 hour history

        pedometer.startUpdates(from: start) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                debug(.openAPS, "CMPedometer error: \(error.localizedDescription)")
                return
            }
            guard let data = data else { return }

            let now = Date()
            let cumulative = data.numberOfSteps.intValue

            self.timelineQueue.async {
                self.stepTimeline.append((now, cumulative))

                let cutoff = now.addingTimeInterval(-self.timelineMaxAge)
                while let first = self.stepTimeline.first, first.0 < cutoff {
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

    /// Call once per loop cycle before AutoISF merge
    func refreshActivity(completion: ((ActivitySnapshot?) -> Void)? = nil) {
        guard enabled else {
            completion?(snapshot)
            return
        }

        ensureLivePedometerRunning()

        // LIVE PEDOMETER path (preferred)
        if livePedometerEnabled, pedometerActive {
            timelineQueue.sync {
                let now = Date()

                if !self.stepTimeline.isEmpty {
                    self.refreshActivityFromTimeline(now: now)
                }

                // ✅ compute raw fresh from the current snapshot/state
                let raw = self.autoISFReductionRaw()

                // ✅ apply hold logic ONCE per loop
                self.updateISFReduction(rawReduction: raw)
            }

            completion?(self.snapshot)
            return
        }

        // If pedometer isn't active, keep returning last known snapshot (HK fallback elsewhere if needed)
        completion?(snapshot)
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

        let s5 = window(5)
        let s10 = window(10)
        let s15 = window(15)
        let s30 = window(30)
        let s60 = window(60)

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

        snapshot = snap
        state = classify(snapshot: snap)
    }

    // MARK: - ISF reduction hold / decay (edge-detect)

    func updateISFReduction(rawReduction: Double) {
        if rawReduction > 0 {
            // New or continued activity → reset hold
            cachedISFReduction = rawReduction
            originalReduction = rawReduction
            holdCounter = holdLoops
        } else if holdCounter > 0 {
            // No new activity, but still holding
            holdCounter -= 1
            
            // Keep full reduction value during hold period
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
        // Gate
        if snapshot.steps15 < minStepsForAnyEffect { return .rest }

        // Fast reaction uses 5-minute SPM
        let spm = snapshot.spm5

        if spm >= highSPMThreshold { return .high }
        if spm >= moderateSPMThreshold { return .moderate }
        if spm >= lightSPMThreshold { return .light }
        return .rest
    }

    // MARK: AutoISF

    /// Raw reduction delta (before hold/decay).
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
            "ISFΔ: \(String(format: "%.2f", cachedISFReduction)), " +
            "Hold: \(holdCounter)"
    }
}
