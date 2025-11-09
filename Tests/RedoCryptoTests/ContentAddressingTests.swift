import XCTest
@testable import RedoCrypto
@testable import RedoCore

/// Tests for SHA-256 content addressing
final class ContentAddressingTests: XCTestCase {

    // MARK: - Basic Hashing

    func testCalculateHashOfData() {
        let data = "Hello, Redo!".data(using: .utf8)!
        let hash = ContentAddressing.calculateHash(of: data)

        XCTAssertTrue(hash.hasPrefix("sha256:"))
        XCTAssertEqual(hash.count, 71)  // "sha256:" + 64 hex chars
    }

    func testCalculateHashOfString() {
        let hash = ContentAddressing.calculateHash(of: "Hello, Redo!")

        XCTAssertNotNil(hash)
        XCTAssertTrue(hash!.hasPrefix("sha256:"))
        XCTAssertEqual(hash!.count, 71)
    }

    func testDeterministicHashing() {
        let data = "Test message".data(using: .utf8)!

        let hash1 = ContentAddressing.calculateHash(of: data)
        let hash2 = ContentAddressing.calculateHash(of: data)

        XCTAssertEqual(hash1, hash2)
    }

    func testDifferentDataProducesDifferentHash() {
        let data1 = "Message 1".data(using: .utf8)!
        let data2 = "Message 2".data(using: .utf8)!

        let hash1 = ContentAddressing.calculateHash(of: data1)
        let hash2 = ContentAddressing.calculateHash(of: data2)

        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Change ID Validation

    func testValidChangeId() {
        let validId = "sha256:" + String(repeating: "a", count: 64)

        XCTAssertTrue(ContentAddressing.isValidChangeId(validId))
    }

    func testInvalidChangeIdFormat() {
        // Missing prefix
        XCTAssertFalse(ContentAddressing.isValidChangeId(String(repeating: "a", count: 64)))

        // Wrong prefix
        XCTAssertFalse(ContentAddressing.isValidChangeId("sha512:" + String(repeating: "a", count: 64)))

        // Wrong length
        XCTAssertFalse(ContentAddressing.isValidChangeId("sha256:abc"))

        // Uppercase hex
        XCTAssertFalse(ContentAddressing.isValidChangeId("sha256:" + String(repeating: "A", count: 64)))

        // Non-hex characters
        XCTAssertFalse(ContentAddressing.isValidChangeId("sha256:" + String(repeating: "g", count: 64)))
    }

    // MARK: - Lowercase Hex Enforcement

    func testHashIsLowercaseHex() {
        let hash = ContentAddressing.calculateHash(of: "Test".data(using: .utf8)!)

        let hashPart = String(hash.dropFirst(7))  // Remove "sha256:"

        // All characters should be lowercase hex
        for char in hashPart {
            XCTAssertTrue(char.isNumber || ("a"..."f").contains(char))
        }
    }

    // MARK: - Known Test Vectors

    func testKnownSHA256Vectors() {
        // Known SHA-256 test vectors for cross-platform verification

        // Empty string
        let hash1 = ContentAddressing.calculateHash(of: "".data(using: .utf8)!)
        XCTAssertEqual(
            hash1,
            "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )

        // "abc"
        let hash2 = ContentAddressing.calculateHash(of: "abc".data(using: .utf8)!)
        XCTAssertEqual(
            hash2,
            "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    // MARK: - Cross-Platform Compatibility

    func testCanonicalJSONHashConsistency() throws {
        // Test that same data produces same hash (for cross-platform compatibility)
        let entry = createTestEntry()

        let hash1 = try ContentAddressing.calculateChangeId(entry: entry)
        let hash2 = try ContentAddressing.calculateChangeId(entry: entry)

        XCTAssertEqual(hash1, hash2)
        XCTAssertTrue(ContentAddressing.isValidChangeId(hash1))
    }

    func testOrderIndependentFields() throws {
        // Canonical JSON should sort keys, so order doesn't matter
        let data1 = ChangeData(dictionary: ["b": "value2", "a": "value1"])
        let data2 = ChangeData(dictionary: ["a": "value1", "b": "value2"])

        let entry1 = createTestEntry(data: data1)
        let entry2 = createTestEntry(data: data2)

        let hash1 = try ContentAddressing.calculateChangeId(entry: entry1)
        let hash2 = try ContentAddressing.calculateChangeId(entry: entry2)

        // Should produce same hash because canonical JSON sorts keys
        XCTAssertEqual(hash1, hash2)
    }

    // MARK: - Change Detection

    func testDifferentDataProducesDifferentChangeId() throws {
        let entry1 = createTestEntry(data: ChangeData(dictionary: ["title": "Task 1"]))
        let entry2 = createTestEntry(data: ChangeData(dictionary: ["title": "Task 2"]))

        let hash1 = try ContentAddressing.calculateChangeId(entry: entry1)
        let hash2 = try ContentAddressing.calculateChangeId(entry: entry2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testDifferentActionProducesDifferentChangeId() throws {
        var entry1 = createTestEntry()
        entry1 = ChangeLogEntry(
            id: entry1.id,
            version: entry1.version,
            parents: entry1.parents,
            timestamp: entry1.timestamp,
            author: entry1.author,
            action: .create,
            taskId: entry1.taskId,
            data: entry1.data,
            signature: entry1.signature
        )

        var entry2 = createTestEntry()
        entry2 = ChangeLogEntry(
            id: entry2.id,
            version: entry2.version,
            parents: entry2.parents,
            timestamp: entry2.timestamp,
            author: entry2.author,
            action: .update,
            taskId: entry2.taskId,
            data: entry2.data,
            signature: entry2.signature
        )

        let hash1 = try ContentAddressing.calculateChangeId(entry: entry1)
        let hash2 = try ContentAddressing.calculateChangeId(entry: entry2)

        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Performance

    func testHashingPerformance() {
        measure {
            for _ in 0..<100 {
                _ = ContentAddressing.calculateHash(of: "Test message".data(using: .utf8)!)
            }
        }
    }

    func testChangeIdCalculationPerformance() throws {
        let entry = createTestEntry()

        measure {
            for _ in 0..<100 {
                _ = try? ContentAddressing.calculateChangeId(entry: entry)
            }
        }
    }

    // MARK: - Helper Methods

    private func createTestEntry(data: ChangeData? = nil) -> ChangeLogEntry {
        let timestamp = LogicalTimestamp(
            lamport: 1,
            wallDate: Date()
        )

        let (publicKey, _, userId) = Ed25519Manager.generateKey()

        let author = AuthorInfo(
            userId: userId,
            deviceId: "test_device",
            name: nil,
            publicKey: publicKey
        )

        let changeData = data ?? ChangeData(dictionary: ["title": "Test"])

        return ChangeLogEntry(
            id: "",  // Will be calculated
            version: 1,
            parents: [],
            timestamp: timestamp,
            author: author,
            action: .create,
            taskId: UUID().uuidString,
            data: changeData,
            signature: nil
        )
    }
}
