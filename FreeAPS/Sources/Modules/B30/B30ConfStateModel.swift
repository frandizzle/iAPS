import SwiftUI

extension AIMIB30Conf {
    final class StateModel: BaseStateModel<Provider>, PreferencesSettable {
        private(set) var preferences = Preferences()
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var unit: GlucoseUnits = .mmolL
        @Published var sections: [FieldSection] = []
        @Published var enableB30: Bool = false

        override func subscribe() {
            unit = settingsManager.settings.units
            preferences = provider.preferences
            enableB30 = settings.preferences.enableB30

            // MARK: - AIMI B30 fields

            let xpmB30 = [
                Field(
                    displayName: "TempTarget Level in mg/dl for B30 to be enacted",
                    type: .decimal(keypath: \.B30iTimeTarget),
                    infoText: NSLocalizedString(
                        "An EatingSoon TempTarget needs to be enabled to start B30 adaption. Set level for this target to be identified. Default is 90 mg/dl. If you cancel this EatingSoon TT also the B30 basal rate will stop.",
                        comment: "EatingSoon TT level"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Minimum Start Bolus size",
                    type: .decimal(keypath: \.B30iTimeStartBolus),
                    infoText: NSLocalizedString(
                        "Minimum manual bolus to start a B30 adaption.",
                        comment: "B30 Start Bolus size"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Duration of increased B30 basal rate",
                    type: .decimal(keypath: \.B30iTime),
                    infoText: NSLocalizedString(
                        "Duration of increased basal rate that saturates the infusion site with insulin. Default 30 minutes, as in B30. The EatingSoon TT needs to be running at least for this duration, otherthise B30 will stopp after the TT runs out.",
                        comment: "Duration of B30"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "B30 Basal rate increase factor",
                    type: .decimal(keypath: \.B30basalFactor),
                    infoText: NSLocalizedString(
                        "Factor that multiplies your regular basal rate from profile for B30. Default is 10.",
                        comment: "Basal rate factor B30"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Upper BG limit in mg/dl for B30",
                    type: .decimal(keypath: \.B30upperLimit),
                    infoText: NSLocalizedString(
                        "B30 will only run as long as BG stays underneath that level, if above regular autoISF takes over. Default is 130 mg/dl.",
                        comment: "Upper BG for B30"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Upper Delta limit in mg/dl for B30",
                    type: .decimal(keypath: \.B30upperDelta),
                    infoText: NSLocalizedString(
                        "B30 will only run as long as BG delta stays below that level, if above regular autoISF takes over. Default is 8 mg/dl.",
                        comment: "Upper Delta for B30"
                    ),
                    settable: self
                )
            ]

            sections = [
                FieldSection(
                    displayName: NSLocalizedString(
                        "B30 settings",
                        comment: "AIMI B30  settings"
                    ),
                    fields: xpmB30
                )
            ]
        }

        var unChanged: Bool {
            preferences.enableB30 == enableB30
        }

        func convertBack(_ glucose: Decimal) -> Decimal {
            if unit == .mmolL {
                return glucose.asMgdL
            }
            return glucose
        }

        func save() {
            provider.savePreferences(preferences)
        }

        func set<T>(_ keypath: WritableKeyPath<Preferences, T>, value: T) {
            preferences[keyPath: keypath] = value
            save()
        }

        func get<T>(_ keypath: WritableKeyPath<Preferences, T>) -> T {
            preferences[keyPath: keypath]
        }

        func saveIfChanged() {
            if !unChanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
                newSettings.enableB30 = enableB30
                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
