import Foundation

extension AutoISFConf {
    final class Provider: BaseProvider, AutoISFConfProvider {
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
