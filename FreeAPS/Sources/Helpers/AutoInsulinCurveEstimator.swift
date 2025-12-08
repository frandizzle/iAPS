import Foundation
import HealthKit
import LoopKit

// Result of the learning step
struct LearnedInsulinCurve {
    let diaHours: Double
    let peakMinutes: Double
}

final class AutoInsulinCurveEstimator {
    /// Main DIA + peak learning entry point
    /// - Parameters:
    ///   - glucose: chronological SimpleGlucoseValue history
    ///   - doses: DoseEntry history (bolus, SMB, temp basals, etc)
    /// - Returns: Best-fit DIA (hours) and Peak (minutes), or nil if data is not suitable
    func calculate(glucose: [SimpleGlucoseValue], doses: [DoseEntry]) -> LearnedInsulinCurve? {
        // Need at least a few points
        guard glucose.count > 2 else { return nil }

        let unit = HKUnit.milligramsPerDeciliter

        // ---------------------------------------
        // GLOBAL SIGNAL CHECKS (before search)
        // ---------------------------------------

        // 1) Compute BG deltas to see if anything actually moved
        let bgValues: [Double] = glucose.map { $0.quantity.doubleValue(for: unit) }
        var bgDeltas: [Double] = []
        for i in 1 ..< bgValues.count {
            bgDeltas.append(bgValues[i] - bgValues[i - 1])
        }
        let maxAbsBgDelta = bgDeltas.map { abs($0) }.max() ?? 0

        // 2) Compute total insulin over the window
        var totalInsulin = 0.0
        for d in doses {
            switch d.type {
            case .bolus:
                totalInsulin += d.deliveredUnits ?? d.programmedUnits
            case .resume,
                 .suspend:
                // no net insulin here
                break
            case .basal,
                 .tempBasal:
                totalInsulin += d.netBasalUnits
            }
        }

        // Guard rails: only learn when there is real signal
        // - At least ~0.5U insulin
        // - At least ~8 mg/dL of movement somewhere
        if totalInsulin < 0.8 || maxAbsBgDelta < 8 {
            debug(
                .openAPS,
                "AutoDIA: ❌ Skipping learning — insufficient insulin signal (totalInsulin=\(totalInsulin), maxΔBG=\(maxAbsBgDelta))"
            )
            return nil
        }

        // ---------------------------------------
        // Candidate search space
        // ---------------------------------------
        let diaCandidates = stride(from: 5.0, through: 11.0, by: 0.25) // hours
        let peakCandidates = stride(from: 35.0, through: 120.0, by: 5.0) // minutes

        var bestScore = Double.infinity
        var bestCurve: LearnedInsulinCurve?

        let timestamps = glucose.map(\.startDate)

        for dia in diaCandidates {
            for peak in peakCandidates {
                let model = ExponentialInsulinModel(
                    actionDuration: TimeInterval(dia * 3600),
                    peakActivityTime: TimeInterval(peak * 60)
                )

                let effect = computeEffect(
                    model: model,
                    doses: doses,
                    timestamps: timestamps
                )

                // If effect is all zeros (no overlap of doses & timestamps),
                // this curve tells us nothing → skip quickly.
                if effect.allSatisfy({ $0 == 0 }) {
                    continue
                }

                let score = scoreFit(
                    glucose: glucose,
                    effect: effect,
                    diaHours: dia,
                    peakMinutes: peak
                )

                if score < bestScore {
                    bestScore = score
                    bestCurve = LearnedInsulinCurve(
                        diaHours: dia,
                        peakMinutes: peak
                    )
                }
            }
        }

        if let curve = bestCurve {
            debug(.openAPS, "AutoDIA estimator:")
            debug(.openAPS, "  raw DIA  = \(curve.diaHours)h")
            debug(.openAPS, "  raw Peak = \(curve.peakMinutes)m")
        } else {
            debug(.openAPS, "AutoDIA: ❌ estimator failed to find a suitable curve")
        }

        return bestCurve
    }

    // ---------------------------------------------------------

    // MARK: INSULIN EFFECT CALCULATION

    // ---------------------------------------------------------
    private func computeEffect(
        model: ExponentialInsulinModel,
        doses: [DoseEntry],
        timestamps: [Date]
    ) -> [Double] {
        var output = Array(repeating: 0.0, count: timestamps.count)

        for dose in doses {
            // Amount of insulin for this dose
            let amount: Double = {
                switch dose.type {
                case .bolus:
                    return dose.deliveredUnits ?? dose.programmedUnits
                case .resume,
                     .suspend:
                    return 0.0
                case .basal,
                     .tempBasal:
                    return dose.netBasalUnits
                }
            }()

            if amount == 0 { continue }

            let start = dose.startDate

            for (i, t) in timestamps.enumerated() {
                let dt = t.timeIntervalSince(start)
                if dt < 0 { continue }

                // insulin model: percentEffectRemaining = IOB%
                // therefore effectFrac = 1 - IOB%
                let remaining = model.percentEffectRemaining(at: dt)
                let effectFrac = max(0, 1 - remaining)

                output[i] += amount * effectFrac
            }
        }

        return output
    }

    // ---------------------------------------------------------

    // MARK: SCORING MODEL FIT (REGRESSION + PENALTIES)

    // ---------------------------------------------------------
    private func scoreFit(
        glucose: [SimpleGlucoseValue],
        effect: [Double],
        diaHours: Double,
        peakMinutes: Double
    ) -> Double {
        // Need enough points and aligned arrays
        guard glucose.count > 1, glucose.count == effect.count else {
            return Double.infinity
        }

        let unit = HKUnit.milligramsPerDeciliter

        // Convert glucose to mg/dL array
        let bgValues = glucose.map { $0.quantity.doubleValue(for: unit) }

        // Calculate glucose deltas (change from previous reading)
        var bgDeltas: [Double] = []
        for i in 1 ..< bgValues.count {
            bgDeltas.append(bgValues[i] - bgValues[i - 1])
        }

        // Calculate insulin effect deltas (change from previous timestamp)
        var effectDeltas: [Double] = []
        for i in 1 ..< effect.count {
            effectDeltas.append(effect[i] - effect[i - 1])
        }

        let n = min(bgDeltas.count, effectDeltas.count)
        if n == 0 {
            return Double.infinity
        }

        // -----------------------------------
        // 1) Solve for best-fit ISF by regression
        //    ISF = (Σ ΔE·ΔG) / (Σ ΔE²)
        // -----------------------------------
        var num = 0.0
        var den = 0.0

        for i in 0 ..< n {
            let dG = bgDeltas[i]
            let dE = effectDeltas[i]
            num += dE * dG
            den += dE * dE
        }

        if den == 0 {
            // No variation in effect → can't learn from this curve
            return Double.infinity
        }

        var isf = num / den // mg/dL per "effect unit"

        // Clamp ISF to a sane range so outliers don't dominate
        let minISF = 20.0 // very strong insulin
        let maxISF = 120.0 // very weak insulin
        if isf.isNaN || isf.isInfinite {
            return Double.infinity
        }
        isf = max(minISF, min(maxISF, isf))

        // -----------------------------------
        // 2) Compute SSE of residuals using this ISF
        //    predicted ΔBG = -ΔEffect * ISF
        // -----------------------------------
        var totalError = 0.0

        for i in 0 ..< n {
            let dG = bgDeltas[i]
            let dE = effectDeltas[i]

            let predictedChange = -dE * isf
            let residual = dG - predictedChange
            totalError += residual * residual
        }

        let normalizedError = totalError / Double(n)

        // -----------------------------------
        // 3) Add soft penalties to prevent "runaway" max curves
        // -----------------------------------
        var penalty = 0.0

        // Prefer DIA near ~7h; penalize very long tails
        let diaSoftMax = 10.0 // start penalizing after 8h
        if diaHours > diaSoftMax {
            penalty += (diaHours - diaSoftMax) * 1.0
        }

        // Prefer peak near ~60m; penalize very late peaks
        let peakSoftMax = 65.0 // start penalizing after 75m
        if peakMinutes > peakSoftMax {
            penalty += (peakMinutes - peakSoftMax) * 0.5
        }

        return normalizedError + penalty
    }
}
