import Foundation
import LoopKit

enum AIMIB30Conf {
    enum Config {}

    enum FieldType {
        case boolean(keypath: WritableKeyPath<Preferences, Bool>)
        case decimal(keypath: WritableKeyPath<Preferences, Decimal>)
    }

    class Field: Identifiable {
        var displayName: String
        var type: FieldType
        var infoText: String

        var boolValue: Bool {
            get {
                switch type {
                case let .boolean(keypath):
                    return settable?.get(keypath) ?? false
                default: return false
                }
            }
            set { set(value: newValue) }
        }

        var decimalValue: Decimal {
            get {
                switch type {
                case let .decimal(keypath):
                    return settable?.get(keypath) ?? 0
                default: return 0
                }
            }
            set { set(value: newValue) }
        }

        private func set<T: SettableValue>(value: T) {
            switch (type, value) {
            case let (.boolean(keypath), value as Bool):
                settable?.set(keypath, value: value)
            case let (.decimal(keypath), value as Decimal):
                settable?.set(keypath, value: value)
            default: break
            }
        }

        weak var settable: PreferencesSettable?

        init(
            displayName: String,
            type: FieldType,
            infoText: String,
            settable: PreferencesSettable? = nil
        ) {
            self.displayName = displayName
            self.type = type
            self.infoText = infoText
            self.settable = settable
        }

        let id = UUID()
    }

    struct FieldSection: Identifiable {
        let displayName: String
        var fields: [Field]
        let id = UUID()
    }
}

protocol B30ConfProvider: Provider {}
