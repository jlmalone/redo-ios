import XCTest
@testable import RedoCore
@testable import RedoCrypto

final class ChangeLogValidatorTests: XCTestCase {

    var validator: ChangeLogValidator!

    override func setUp() {
        super.setUp()
        validator = ChangeLogValidator()
    }

    // MARK: - Version Validation

    func testValidV1Node() {
        let change = createValidChange()
        XCTAssertTrue(validator.isValidV1Node(change))
    }

    func testInvalidVersion() {
        var change = createValidChange()
        change = ChangeLogEntry(
            id: change.id,
            version: 2,  // Invalid: must be 1
            parents: change.parents,
            timestamp: change.timestamp,
            author: change.author,
            action: change.action,
            taskId: change.taskId,
            data: change.data,
            signature: change.signature
        )

        XCTAssertFalse(validator.isValidV1Node(change))
    }

    // MARK: - ID Validation

    func testValidChangeId() {
        let change = createValidChange()
        XCTAssertTrue(change.id.hasPrefix("sha256:"))
        XCTAssertEqual(change.id.count, 71)  // "sha256:" + 64 hex chars
    }

    func testInvalidChangeIdFormat() {
        var change = createValidChange()
        change = ChangeLogEntry(
            id: "invalid_id",  // Invalid format
            version: change.version,
            parents: change.parents,
            timestamp: change.timestamp,
            author: change.author,
            action: change.action,
            taskId: change.taskId,
            data: change.data,
            signature: change.signature
        )

        XCTAssertFalse(validator.isValidV1Node(change))
    }

    func testChangeIdWithUppercaseHex() {
        var change = createValidChange()
        change = ChangeLogEntry(
            id: "sha256:ABC123",  // Invalid: must be lowercase
            version: change.version,
            parents: change.parents,
            timestamp: change.timestamp,
            author: change.author,
            action: change.action,
            taskId: change.taskId,
            data: change.data,
            signature: change.signature
        )

        XCTAssertFalse(validator.isValidV1Node(change))
    }

    // MARK: - Timestamp Validation

    func testValidTimestamp() {
        let change = createValidChange()
        XCTAssertTrue(change.timestamp.lamport > 0)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: change.timestamp.wall))
    }

    func testInvalidLamportClock() {
        var change = createValidChange()
        change = ChangeLogEntry(
            id: change.id,
            version: change.version,
            parents: change.parents,
            timestamp: LogicalTimestamp(lamport: 0, wall: change.timestamp.wall),  // Invalid: must be > 0
            author: change.author,
            action: change.action,
            taskId: change.taskId,
            data: change.data,
            signature: change.signature
        )

        XCTAssertFalse(validator.isValidV1Node(change))
    }

    // MARK: - Author Validation

    func testValidAuthor() {
        let change = createValidChange()
        XCTAssertEqual(change.author.userId.count, 32)
        XCTAssertFalse(change.author.deviceId.isEmpty)
    }

    func testInvalidUserId() {
        var change = createValidChange()
        change = ChangeLogEntry(
            id: change.id,
            version: change.version,
            parents: change.parents,
            timestamp: change.timestamp,
            author: AuthorInfo(
                userId: "short",  // Invalid: must be 32 hex chars
                deviceId: change.author.deviceId,
                name: change.author.name,
                publicKey: change.author.publicKey
            ),
            action: change.action,
            taskId: change.taskId,
            data: change.data,
            signature: change.signature
        )

        XCTAssertFalse(validator.isValidV1Node(change))
    }

    // MARK: - Helpers

    private func createValidChange() -> ChangeLogEntry {
        let (publicKey, _, userId) = Ed25519Manager.generateKey()

        return ChangeLogEntry(
            id: "sha256:" + String(repeating: "a", count: 64),
            version: 1,
            parents: [],
            timestamp: LogicalTimestamp(lamport: 1, wallDate: Date()),
            author: AuthorInfo(
                userId: userId,
                deviceId: "test_device",
                name: nil,
                publicKey: publicKey
            ),
            action: .create,
            taskId: UUID().uuidString,
            data: ChangeData(fields: ["title": AnyCodable("Test")]),
            signature: nil
        )
    }
}
