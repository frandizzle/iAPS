import Foundation

extension AIMIB30Conf {
    final class Provider: BaseProvider, B30ConfProvider {
        @Injected() private var settingsManager: SettingsManager!
        private let processQueue = DispatchQueue(label: "PreferencesEditorProvider.processQueue")

        var preferences: Preferences {
            settingsManager.preferences
        }

        func savePreferences(_ preferences: Preferences) {
            processQueue.async {
                var prefs = preferences
                prefs.timestamp = Date()
                self.storage.save(prefs, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
