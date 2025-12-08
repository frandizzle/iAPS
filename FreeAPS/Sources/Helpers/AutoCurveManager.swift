import Dispatch
import Foundation

final class AutoCurveManager {
    static let shared = AutoCurveManager()

    private let keyCurve = "autoDIA.learnedCurve"
    private let keyHistory = "autoDIA.history"

    private let queue = DispatchQueue(label: "autoDIA.curve.queue")

    // MARK: - Safe load current curve

    var currentCurve: LearnedCurve? {
        queue.sync {
            guard let data = UserDefaults.standard.data(forKey: keyCurve) else { return nil }
            return try? JSONDecoder().decode(LearnedCurve.self, from: data)
        }
    }

    // MARK: - Safe history loader (NO queue.sync recursion)

    var history: [AutoDIAHistoryEntry] {
        // If we're already on the same queue → load WITHOUT sync
        if DispatchQueue.getSpecific(key: key) == queueContext {
            return loadHistoryDirect()
        }

        return queue.sync { loadHistoryDirect() }
    }

    // Low-level safe load (no locking)
    private func loadHistoryDirect() -> [AutoDIAHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: keyHistory) else { return [] }

        do {
            return try JSONDecoder().decode([AutoDIAHistoryEntry].self, from: data)
        } catch {
            print("⚠️ AutoDIA history decode failed, clearing corrupted history: \(error)")
            UserDefaults.standard.removeObject(forKey: keyHistory)
            return []
        }
    }

    // MARK: - Save new curve + log history

    func update(curve: LearnedCurve) {
        queue.async {
            // Save curve
            if let data = try? JSONEncoder().encode(curve) {
                UserDefaults.standard.set(data, forKey: self.keyCurve)
            }

            // Build entry
            let entry = AutoDIAHistoryEntry(
                timestamp: Date(),
                diaHours: curve.diaHours,
                peakMinutes: curve.peakMinutes
            )

            self.appendHistoryEntry(entry)
        }
    }

    // MARK: - Append entry WITHOUT deadlock

    private func appendHistoryEntry(_ entry: AutoDIAHistoryEntry) {
        queue.async {
            var list = self.loadHistoryDirect() // <-- NO sync here
            list.append(entry)

            do {
                let data = try JSONEncoder().encode(list)
                UserDefaults.standard.set(data, forKey: self.keyHistory)
                print("💾 AutoDIA history saved successfully. Total entries: \(list.count)")
            } catch {
                print("❌ Failed to save AutoDIA history: \(error)")
            }
        }
    }

    // MARK: - Reset

    func reset() {
        queue.async {
            UserDefaults.standard.removeObject(forKey: self.keyCurve)
            UserDefaults.standard.removeObject(forKey: self.keyHistory)
        }
    }

    // MARK: - Queue identification

    private let key = DispatchSpecificKey<String>()
    private let queueContext = "autoDIA.curve.queue"

    init() {
        queue.setSpecific(key: key, value: queueContext)
    }
}
