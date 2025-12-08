import Foundation
import HealthKit

/// A safe wrapper around a JSON dictionary used for profiles.
/// Allows modifying keys and re-encoding to RawJSON safely.
struct ProfileObject {
    /// Internal JSON dictionary
    private(set) var dictionary: [String: Any]

    // MARK: - Init From Any Raw Profile

    init(_ raw: Any?) {
        if let dict = raw as? [String: Any] {
            dictionary = dict
        } else if let str = raw as? String,
                  let data = str.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            dictionary = json
        } else {
            dictionary = [:]
        }
    }

    // MARK: - Codable Conformance
}

extension ProfileObject: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as dictionary directly
        if let dict = try? container.decode([String: AnyCodable].self) {
            dictionary = dict.mapValues { $0.value }
            return
        }

        // Try to decode as RawJSON string
        if let rawString = try? container.decode(String.self),
           let data = rawString.data(using: .utf8),
           let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            dictionary = dict
            return
        }

        dictionary = [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        // Always encode as proper JSON string
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"

        try container.encode(jsonString)
    }
}

// MARK: - JSON Conversion Helpers

extension ProfileObject {
    /// Safely convert back to RawJSON string
    func encodeToRawJSON() -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Modify a key in the JSON safely
    mutating func set(key: String, value: Any?) {
        dictionary[key] = value
    }
}

// MARK: - Equatable

extension ProfileObject: Equatable {
    static func == (lhs: ProfileObject, rhs: ProfileObject) -> Bool {
        let lhsData = try? JSONSerialization.data(withJSONObject: lhs.dictionary, options: [.sortedKeys])
        let rhsData = try? JSONSerialization.data(withJSONObject: rhs.dictionary, options: [.sortedKeys])
        return lhsData == rhsData
    }
}

/// Wrapper to allow Any in Codable
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intVal = try? container.decode(Int.self) {
            value = intVal
            return
        }
        if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
            return
        }
        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
            return
        }
        if let stringVal = try? container.decode(String.self) {
            value = stringVal
            return
        }
        if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
            return
        }
        if let arrVal = try? container.decode([AnyCodable].self) {
            value = arrVal.map(\.value)
            return
        }

        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intVal as Int: try container.encode(intVal)
        case let doubleVal as Double: try container.encode(doubleVal)
        case let boolVal as Bool: try container.encode(boolVal)
        case let stringVal as String: try container.encode(stringVal)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
