import Foundation
import Security

/// Secure storage for Ed25519 private keys in iOS Keychain
public class KeychainService {

    // MARK: - Properties

    private let service: String

    // MARK: - Initialization

    public init(service: String = "com.salient.vision.redo") {
        self.service = service
    }

    // MARK: - Public API

    /// Save data to Keychain
    /// - Parameters:
    ///   - data: Data to save
    ///   - key: Keychain key
    /// - Throws: KeychainError if save fails
    public func save(data: Data, forKey key: String) throws {
        // Delete existing item first
        try? delete(forKey: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Save string to Keychain
    /// - Parameters:
    ///   - string: String to save
    ///   - key: Keychain key
    /// - Throws: KeychainError if save fails
    public func save(string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data: data, forKey: key)
    }

    /// Load data from Keychain
    /// - Parameter key: Keychain key
    /// - Returns: Data if found, nil otherwise
    public func load(forKey key: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    /// Load string from Keychain
    /// - Parameter key: Keychain key
    /// - Returns: String if found, nil otherwise
    public func loadString(forKey key: String) throws -> String? {
        guard let data = try load(forKey: key) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete item from Keychain
    /// - Parameter key: Keychain key
    /// - Throws: KeychainError if delete fails
    public func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    /// Check if key exists in Keychain
    /// - Parameter key: Keychain key
    /// - Returns: True if key exists
    public func exists(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Delete all items for this service
    /// - Throws: KeychainError if delete fails
    public func deleteAll() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - Convenience Methods for Redo

extension KeychainService {
    /// Save Ed25519 private key
    /// - Parameter privateKey: Private key hex string (64 chars)
    /// - Throws: KeychainError if save fails
    public func savePrivateKey(_ privateKey: String) throws {
        try save(string: privateKey, forKey: "ed25519_private_key")
    }

    /// Load Ed25519 private key
    /// - Returns: Private key hex string if found
    public func loadPrivateKey() throws -> String? {
        try loadString(forKey: "ed25519_private_key")
    }

    /// Save Ed25519 public key
    /// - Parameter publicKey: Public key hex string (64 chars)
    /// - Throws: KeychainError if save fails
    public func savePublicKey(_ publicKey: String) throws {
        try save(string: publicKey, forKey: "ed25519_public_key")
    }

    /// Load Ed25519 public key
    /// - Returns: Public key hex string if found
    public func loadPublicKey() throws -> String? {
        try loadString(forKey: "ed25519_public_key")
    }

    /// Save user ID (derived from public key)
    /// - Parameter userId: User ID (first 32 chars of public key)
    /// - Throws: KeychainError if save fails
    public func saveUserId(_ userId: String) throws {
        try save(string: userId, forKey: "user_id")
    }

    /// Load user ID
    /// - Returns: User ID if found
    public func loadUserId() throws -> String? {
        try loadString(forKey: "user_id")
    }

    /// Save device ID
    /// - Parameter deviceId: Device identifier
    /// - Throws: KeychainError if save fails
    public func saveDeviceId(_ deviceId: String) throws {
        try save(string: deviceId, forKey: "device_id")
    }

    /// Load device ID
    /// - Returns: Device ID if found
    public func loadDeviceId() throws -> String? {
        try loadString(forKey: "device_id")
    }
}

// MARK: - Errors

public enum KeychainError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .invalidData:
            return "Invalid data format for Keychain operation"
        }
    }
}
