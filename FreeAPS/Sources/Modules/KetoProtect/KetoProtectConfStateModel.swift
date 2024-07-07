import SwiftUI

extension KetoConf {
    final class StateModel: BaseStateModel<Provider>, PreferencesSettable {
        private(set) var preferences = Preferences()
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Published var sections: [FieldSection] = []
        @Published var ketoProtect: Bool = false

        override func subscribe() {
            preferences = provider.preferences
            ketoProtect = settings.preferences.ketoProtect

            // MARK: - Keto Protect fields

            let ketoProt = [
                Field(
                    displayName: "Safety TBR in %",
                    type: .decimal(keypath: \.ketoProtectBasalPercent),
                    infoText: NSLocalizedString(
                        "Quantity of the small safety TBR in % of Profile BR, which is given to avoid ketoacidosis. Will be limited to min = 5%, max = 50%!",
                        comment: "safety TBR"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Variable protection",
                    type: .boolean(keypath: \.variableKetoProtect), infoText: NSLocalizedString(
                        "If activated the small safety TBR kicks in when IOB is in negative range as if no basal insulin has been delivered for one hour. If deactivated and static is enabled every Zero Temp is replaced with the small TBR.",
                        comment: "Variable Keto protection"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable Absolute Safety TBR",
                    type: .boolean(keypath: \.ketoProtectAbsolut), infoText: NSLocalizedString(
                        "Should an absolute TBR between 0 and 2 U/hr be specified instead of percentage of current BR",
                        comment: "Keto protection with pre-defined TBR"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Absolute Safety TBR ",
                    type: .decimal(keypath: \.ketoProtectBasalAbsolut),
                    infoText: NSLocalizedString(
                        "Amount in U/hr of the small safety TBR, which is given to avoid ketoacidosis. Will be limited to min = 0U/hr, max = 2U/hr!",
                        comment: "safety TBR"
                    ),
                    settable: self
                )
            ]

            sections = [
                FieldSection(
                    displayName: NSLocalizedString(
                        "KetoProtect Settings",
                        comment: "KetoProtect settings"
                    ),
                    fields: ketoProt
                )
            ]
        }

        var unChanged: Bool {
            preferences.ketoProtect == ketoProtect
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
                newSettings.ketoProtect = ketoProtect
                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
