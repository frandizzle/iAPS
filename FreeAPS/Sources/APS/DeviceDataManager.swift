import Combine
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import MockKit
import OmniKit
import SwiftDate
import Swinject
import UserNotifications

protocol DeviceDataManager {
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var recommendsLoop: PassthroughSubject<Void, Never> { get }
}

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self,
    MockPumpManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
    map[Type.managerIdentifier] = Type
}

final class BaseDeviceDataManager: DeviceDataManager, Injectable {
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!

    @Persisted(key: "BaseDeviceDataManager.lastEventDate") var lastEventDate: Date? = nil

    let recommendsLoop = PassthroughSubject<Void, Never>()

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
            if let pumpManager = pumpManager {
                pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
            } else {
                pumpDisplayState.value = nil
            }
        }
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)

    init(resolver: Resolver) {
        injectServices(resolver)
        setupPumpManager()
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func setupPumpManager() {
        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        }
    }

    private func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return staticPumpManagersByIdentifier[managerIdentifier]
    }
}

extension BaseDeviceDataManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy _: TimeInterval) {
//        log.debug("didAdjustPumpClockBy %@", adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        debug(.deviceManager, "Pump Heartbeat")
        pumpManager.ensureCurrentPumpData {
            debug(.deviceManager, "Pump Data updated")
        }
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        info(.deviceManager, "error: \(error.localizedDescription)")
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        pumpHistoryStorage.storePumpEvents(events)
        lastEventDate = events.last?.date
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        debug(.deviceManager, "Reservoir Value \(units), at: \(date)")
        try? storage.save(Decimal(units), as: OpenAPS.Monitor.reservoir)
        let batteryPercent = Int((pumpManager?.status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(percent: batteryPercent, voltage: nil, string: batteryPercent >= 10 ? .normal : .low)
        try? storage.save(battery, as: OpenAPS.Monitor.battery)
        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        debug(.deviceManager, "Recomends loop")
        recommendsLoop.send()
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: DeviceManagerDelegate {
    func scheduleNotification(
        for _: DeviceManager,
        identifier: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger?
    ) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        DispatchQueue.main.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clearNotification(for _: DeviceManager, identifier: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    func removeNotificationRequests(for _: DeviceManager, identifiers: [String]) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message _: String,
        completion _: ((Error?) -> Void)?
    ) {}
}

// MARK: - AlertPresenter

extension BaseDeviceDataManager: AlertPresenter {
    func issueAlert(_: Alert) {}

    func retractAlert(identifier _: Alert.Identifier) {}
}
