import Foundation
import Crypto

/// Manager for Ed25519 cryptographic operations
public class Ed25519Manager {

    // MARK: - Key Generation

    /// Generate new Ed25519 keypair
    /// - Returns: Tuple of (publicKey, privateKey, userId)
    ///   - publicKey: 64 lowercase hex chars
    ///   - privateKey: 64 lowercase hex chars
    ///   - userId: First 32 chars of public key
    public static func generateKey() -> (publicKey: String, privateKey: String, userId: String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let privateKeyData = privateKey.rawRepresentation

        // CRITICAL: Lowercase hexadecimal encoding (v1 protocol requirement)
        let publicKeyHex = publicKeyData.hexEncodedString(uppercase: false)
        let privateKeyHex = privateKeyData.hexEncodedString(uppercase: false)

        // User ID = first 32 chars of public key (per PROTOCOL.md)
        let userId = String(publicKeyHex.prefix(32))

        return (publicKeyHex, privateKeyHex, userId)
    }

    // MARK: - Signing

    /// Sign data with Ed25519 private key
    /// - Parameters:
    ///   - data: Data to sign
    ///   - privateKeyHex: Private key as 64 lowercase hex chars
    /// - Returns: Signature as 128 lowercase hex chars
    /// - Throws: CryptoError if signing fails
    public static func sign(data: Data, privateKeyHex: String) throws -> String {
        guard let privateKeyData = Data(hexEncoded: privateKeyHex),
              privateKeyData.count == 32 else {
            throw CryptoError.invalidPrivateKey
        }

        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let signature = try privateKey.signature(for: data)

        // CRITICAL: Lowercase hex encoding (v1 protocol)
        return signature.hexEncodedString(uppercase: false)
    }

    /// Sign string with Ed25519 private key
    /// - Parameters:
    ///   - string: String to sign (UTF-8 encoded)
    ///   - privateKeyHex: Private key as 64 lowercase hex chars
    /// - Returns: Signature as 128 lowercase hex chars
    /// - Throws: CryptoError if signing fails
    public static func sign(string: String, privateKeyHex: String) throws -> String {
        guard let data = string.data(using: .utf8) else {
            throw CryptoError.invalidData
        }
        return try sign(data: data, privateKeyHex: privateKeyHex)
    }

    // MARK: - Verification

    /// Verify Ed25519 signature
    /// - Parameters:
    ///   - data: Original data
    ///   - signature: Signature as 128 lowercase hex chars
    ///   - publicKeyHex: Public key as 64 lowercase hex chars
    /// - Returns: True if signature is valid
    /// - Throws: CryptoError if verification setup fails
    public static func verify(data: Data, signature: String, publicKeyHex: String) throws -> Bool {
        guard let publicKeyData = Data(hexEncoded: publicKeyHex),
              publicKeyData.count == 32 else {
            throw CryptoError.invalidPublicKey
        }

        guard let signatureData = Data(hexEncoded: signature),
              signatureData.count == 64 else {
            return false
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        return publicKey.isValidSignature(signatureData, for: data)
    }

    /// Verify Ed25519 signature on string
    /// - Parameters:
    ///   - string: Original string (UTF-8 encoded)
    ///   - signature: Signature as 128 lowercase hex chars
    ///   - publicKeyHex: Public key as 64 lowercase hex chars
    /// - Returns: True if signature is valid
    /// - Throws: CryptoError if verification setup fails
    public static func verify(string: String, signature: String, publicKeyHex: String) throws -> Bool {
        guard let data = string.data(using: .utf8) else {
            throw CryptoError.invalidData
        }
        return try verify(data: data, signature: signature, publicKeyHex: publicKeyHex)
    }

    // MARK: - User ID Derivation

    /// Derive user ID from public key
    /// - Parameter publicKeyHex: Public key as 64 lowercase hex chars
    /// - Returns: User ID (first 32 chars of public key)
    public static func getUserId(from publicKeyHex: String) -> String {
        String(publicKeyHex.prefix(32))
    }

    /// Validate public key format
    /// - Parameter publicKeyHex: Public key string
    /// - Returns: True if valid (64 lowercase hex chars)
    public static func isValidPublicKey(_ publicKeyHex: String) -> Bool {
        publicKeyHex.count == 64 && publicKeyHex.allSatisfy { $0.isHexDigit && $0.isLowercase || $0.isNumber }
    }

    /// Validate private key format
    /// - Parameter privateKeyHex: Private key string
    /// - Returns: True if valid (64 lowercase hex chars)
    public static func isValidPrivateKey(_ privateKeyHex: String) -> Bool {
        privateKeyHex.count == 64 && privateKeyHex.allSatisfy { $0.isHexDigit && $0.isLowercase || $0.isNumber }
    }

    /// Validate signature format
    /// - Parameter signatureHex: Signature string
    /// - Returns: True if valid (128 lowercase hex chars)
    public static func isValidSignature(_ signatureHex: String) -> Bool {
        signatureHex.count == 128 && signatureHex.allSatisfy { $0.isHexDigit && $0.isLowercase || $0.isNumber }
    }
}

// MARK: - Crypto Errors

public enum CryptoError: Error, LocalizedError {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidSignature
    case invalidData
    case signingFailed
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Invalid Ed25519 private key (must be 64 lowercase hex chars)"
        case .invalidPublicKey:
            return "Invalid Ed25519 public key (must be 64 lowercase hex chars)"
        case .invalidSignature:
            return "Invalid Ed25519 signature (must be 128 lowercase hex chars)"
        case .invalidData:
            return "Invalid data for cryptographic operation"
        case .signingFailed:
            return "Failed to sign data with Ed25519"
        case .verificationFailed:
            return "Failed to verify Ed25519 signature"
        }
    }
}

// MARK: - Data Extensions

extension Data {
    /// Convert data to hexadecimal string
    /// - Parameter uppercase: Whether to use uppercase letters (default: false)
    /// - Returns: Hex-encoded string
    func hexEncodedString(uppercase: Bool = false) -> String {
        let format = uppercase ? "%02X" : "%02x"
        return map { String(format: format, $0) }.joined()
    }

    /// Initialize data from hexadecimal string
    /// - Parameter hexString: Hex-encoded string
    init?(hexEncoded hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }

        var data = Data(capacity: hexString.count / 2)

        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

// MARK: - Character Extensions

extension Character {
    var isHexDigit: Bool {
        isNumber || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
