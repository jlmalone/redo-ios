import Foundation
import Crypto

/// Content addressing using SHA-256 hashing
public class ContentAddressing {

    // MARK: - Change ID Calculation

    /// Calculate content-addressed ID for a change log entry
    /// - Parameter entry: Change log entry
    /// - Returns: "sha256:<64 hex chars>"
    /// - Throws: EncodingError if canonical JSON serialization fails
    public static func calculateChangeId<T: Encodable>(entry: T) throws -> String {
        // 1. Serialize to canonical JSON (sorted keys, no whitespace)
        let canonicalJson = try CanonicalJSON.stringify(entry)

        // 2. SHA-256 hash
        guard let data = canonicalJson.data(using: .utf8) else {
            throw ContentAddressingError.invalidJSON
        }

        let hash = SHA256.hash(data: data)

        // 3. Lowercase hex encoding (v1 protocol requirement)
        let hashHex = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "sha256:\(hashHex)"
    }

    /// Calculate SHA-256 hash of arbitrary data
    /// - Parameter data: Data to hash
    /// - Returns: "sha256:<64 hex chars>"
    public static func calculateHash(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        let hashHex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "sha256:\(hashHex)"
    }

    /// Calculate SHA-256 hash of string
    /// - Parameter string: String to hash (UTF-8 encoded)
    /// - Returns: "sha256:<64 hex chars>"
    public static func calculateHash(of string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        return calculateHash(of: data)
    }

    // MARK: - Validation

    /// Validate change ID format
    /// - Parameter id: Change ID to validate
    /// - Returns: True if format is valid ("sha256:" + 64 hex chars)
    public static func isValidChangeId(_ id: String) -> Bool {
        guard id.hasPrefix("sha256:") else { return false }
        let hash = String(id.dropFirst(7))  // Remove "sha256:" prefix
        return hash.count == 64 && hash.allSatisfy { $0.isHexDigit && ($0.isLowercase || $0.isNumber) }
    }

    /// Verify that entry's ID matches its content
    /// - Parameter entry: Change log entry with id field
    /// - Returns: True if ID is correctly calculated from content
    /// - Throws: EncodingError if canonical JSON fails
    public static func verifyChangeId<T: Encodable & ChangeIdProviding>(entry: T) throws -> Bool {
        let calculatedId = try calculateChangeId(entry: entry)
        return calculatedId == entry.changeId
    }
}

// MARK: - Protocol

/// Protocol for objects that provide a change ID
public protocol ChangeIdProviding {
    var changeId: String { get }
}

// MARK: - Errors

public enum ContentAddressingError: Error, LocalizedError {
    case invalidJSON
    case invalidChangeId
    case idMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Failed to serialize to canonical JSON"
        case .invalidChangeId:
            return "Invalid change ID format (must be 'sha256:' + 64 lowercase hex chars)"
        case .idMismatch(let expected, let actual):
            return "Change ID mismatch: expected \(expected), got \(actual)"
        }
    }
}
