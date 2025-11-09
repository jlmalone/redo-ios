import Foundation

/// RFC 8785 canonical JSON serialization
/// Required for deterministic SHA-256 hashing across platforms
public class CanonicalJSON {

    // MARK: - Public API

    /// Serialize value to canonical JSON string
    /// - Parameter value: Any encodable value
    /// - Returns: Canonical JSON string (sorted keys, no whitespace)
    /// - Throws: EncodingError if serialization fails
    public static func stringify<T: Encodable>(_ value: T) throws -> String {
        // Use custom encoder with sorted keys
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Encode to data
        let data = try encoder.encode(value)

        // Convert to string (should be UTF-8 canonical form)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw CanonicalJSONError.invalidEncoding
        }

        // Remove whitespace (JSONEncoder with sortedKeys still adds some)
        let compacted = removeWhitespace(from: jsonString)

        return compacted
    }

    /// Serialize dictionary to canonical JSON string
    /// - Parameter dictionary: Dictionary with string keys
    /// - Returns: Canonical JSON string
    /// - Throws: EncodingError if serialization fails
    public static func stringify(_ dictionary: [String: Any]) throws -> String {
        // Sort keys alphabetically
        let sortedKeys = dictionary.keys.sorted()

        // Build JSON string manually with sorted keys
        var parts: [String] = []

        for key in sortedKeys {
            guard let value = dictionary[key] else { continue }
            let keyJson = try encodeValue(key)
            let valueJson = try encodeValue(value)
            parts.append("\(keyJson):\(valueJson)")
        }

        return "{\(parts.joined(separator: ","))}"
    }

    // MARK: - Private Helpers

    private static func removeWhitespace(from json: String) -> String {
        var result = ""
        var inString = false
        var escaped = false

        for char in json {
            if escaped {
                result.append(char)
                escaped = false
                continue
            }

            if char == "\\" && inString {
                escaped = true
                result.append(char)
                continue
            }

            if char == "\"" {
                inString.toggle()
                result.append(char)
                continue
            }

            if inString {
                result.append(char)
            } else if !char.isWhitespace {
                result.append(char)
            }
        }

        return result
    }

    private static func encodeValue(_ value: Any) throws -> String {
        if let string = value as? String {
            return encodeString(string)
        } else if let number = value as? NSNumber {
            return encodeNumber(number)
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if let array = value as? [Any] {
            let elements = try array.map { try encodeValue($0) }
            return "[\(elements.joined(separator: ","))]"
        } else if let dictionary = value as? [String: Any] {
            return try stringify(dictionary)
        } else if value is NSNull {
            return "null"
        } else {
            throw CanonicalJSONError.unsupportedType
        }
    }

    private static func encodeString(_ string: String) -> String {
        // JSON string encoding with escape sequences
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        return "\"\(escaped)\""
    }

    private static func encodeNumber(_ number: NSNumber) -> String {
        // Check if it's a boolean (NSNumber can represent bool)
        if CFNumberGetType(number as CFNumber) == .charType {
            return number.boolValue ? "true" : "false"
        }

        // Check if it's an integer
        if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(number.intValue)"
        }

        // It's a decimal number
        return "\(number.doubleValue)"
    }

    // MARK: - Validation

    /// Validate that a JSON string is in canonical form
    /// - Parameter json: JSON string to validate
    /// - Returns: True if canonical (sorted keys, no whitespace)
    public static func isCanonical(_ json: String) -> Bool {
        // Check for whitespace outside strings
        var inString = false
        var escaped = false

        for char in json {
            if escaped {
                escaped = false
                continue
            }

            if char == "\\" && inString {
                escaped = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            if !inString && char.isWhitespace {
                return false
            }
        }

        // TODO: Validate key ordering (requires full JSON parsing)
        return true
    }
}

// MARK: - Errors

public enum CanonicalJSONError: Error, LocalizedError {
    case invalidEncoding
    case unsupportedType
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Failed to encode JSON to UTF-8"
        case .unsupportedType:
            return "Unsupported type for canonical JSON encoding"
        case .invalidJSON:
            return "Invalid JSON format"
        }
    }
}
