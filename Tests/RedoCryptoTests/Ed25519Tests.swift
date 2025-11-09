import XCTest
@testable import RedoCrypto

final class Ed25519Tests: XCTestCase {

    // MARK: - Key Generation

    func testKeyGeneration() {
        let (publicKey, privateKey, userId) = Ed25519Manager.generateKey()

        // Public key should be 64 lowercase hex chars
        XCTAssertEqual(publicKey.count, 64)
        XCTAssertTrue(Ed25519Manager.isValidPublicKey(publicKey))

        // Private key should be 64 lowercase hex chars
        XCTAssertEqual(privateKey.count, 64)
        XCTAssertTrue(Ed25519Manager.isValidPrivateKey(privateKey))

        // User ID should be first 32 chars of public key
        XCTAssertEqual(userId.count, 32)
        XCTAssertEqual(userId, String(publicKey.prefix(32)))
    }

    func testMultipleKeyGenerations() {
        let key1 = Ed25519Manager.generateKey()
        let key2 = Ed25519Manager.generateKey()

        // Keys should be different
        XCTAssertNotEqual(key1.publicKey, key2.publicKey)
        XCTAssertNotEqual(key1.privateKey, key2.privateKey)
        XCTAssertNotEqual(key1.userId, key2.userId)
    }

    // MARK: - Signing

    func testSigningAndVerification() throws {
        let (publicKey, privateKey, _) = Ed25519Manager.generateKey()
        let message = "Hello, Redo!"

        // Sign message
        let signature = try Ed25519Manager.sign(string: message, privateKeyHex: privateKey)

        // Signature should be 128 lowercase hex chars
        XCTAssertEqual(signature.count, 128)
        XCTAssertTrue(Ed25519Manager.isValidSignature(signature))

        // Verify signature
        let isValid = try Ed25519Manager.verify(
            string: message,
            signature: signature,
            publicKeyHex: publicKey
        )
        XCTAssertTrue(isValid)
    }

    func testSignatureRejectsTamperedMessage() throws {
        let (publicKey, privateKey, _) = Ed25519Manager.generateKey()
        let originalMessage = "Hello, Redo!"
        let tamperedMessage = "Hello, Hacker!"

        // Sign original message
        let signature = try Ed25519Manager.sign(string: originalMessage, privateKeyHex: privateKey)

        // Verification should fail for tampered message
        let isValid = try Ed25519Manager.verify(
            string: tamperedMessage,
            signature: signature,
            publicKeyHex: publicKey
        )
        XCTAssertFalse(isValid)
    }

    func testSignatureRejectsWrongPublicKey() throws {
        let key1 = Ed25519Manager.generateKey()
        let key2 = Ed25519Manager.generateKey()
        let message = "Hello, Redo!"

        // Sign with key1
        let signature = try Ed25519Manager.sign(string: message, privateKeyHex: key1.privateKey)

        // Verification should fail with key2's public key
        let isValid = try Ed25519Manager.verify(
            string: message,
            signature: signature,
            publicKeyHex: key2.publicKey
        )
        XCTAssertFalse(isValid)
    }

    // MARK: - Cross-Platform Compatibility

    func testDeterministicSigning() throws {
        // Same message and key should produce same signature
        let (publicKey, privateKey, _) = Ed25519Manager.generateKey()
        let message = "Test message"

        let signature1 = try Ed25519Manager.sign(string: message, privateKeyHex: privateKey)
        let signature2 = try Ed25519Manager.sign(string: message, privateKeyHex: privateKey)

        XCTAssertEqual(signature1, signature2)

        // Both signatures should verify
        XCTAssertTrue(try Ed25519Manager.verify(string: message, signature: signature1, publicKeyHex: publicKey))
        XCTAssertTrue(try Ed25519Manager.verify(string: message, signature: signature2, publicKeyHex: publicKey))
    }

    // MARK: - User ID Derivation

    func testUserIdDerivation() {
        let (publicKey, _, userId) = Ed25519Manager.generateKey()

        let derivedUserId = Ed25519Manager.getUserId(from: publicKey)
        XCTAssertEqual(userId, derivedUserId)
        XCTAssertEqual(derivedUserId.count, 32)
    }

    // MARK: - Validation

    func testPublicKeyValidation() {
        // Valid key
        let validKey = String(repeating: "a", count: 64)
        XCTAssertTrue(Ed25519Manager.isValidPublicKey(validKey))

        // Invalid: wrong length
        XCTAssertFalse(Ed25519Manager.isValidPublicKey("abc123"))

        // Invalid: uppercase hex
        let uppercaseKey = String(repeating: "A", count: 64)
        XCTAssertFalse(Ed25519Manager.isValidPublicKey(uppercaseKey))

        // Invalid: non-hex characters
        let invalidKey = String(repeating: "g", count: 64)
        XCTAssertFalse(Ed25519Manager.isValidPublicKey(invalidKey))
    }

    func testSignatureValidation() {
        // Valid signature
        let validSig = String(repeating: "a", count: 128)
        XCTAssertTrue(Ed25519Manager.isValidSignature(validSig))

        // Invalid: wrong length
        XCTAssertFalse(Ed25519Manager.isValidSignature("abc123"))

        // Invalid: uppercase hex
        let uppercaseSig = String(repeating: "A", count: 128)
        XCTAssertFalse(Ed25519Manager.isValidSignature(uppercaseSig))
    }
}
