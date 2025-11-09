import XCTest
@testable import RedoCore
@testable import RedoCrypto

/// Tests for file-based change log storage
final class ChangeLogStorageTests: XCTestCase {

    var storage: ChangeLogStorage!
    var testUserId: String!

    override func setUp() {
        super.setUp()
        storage = ChangeLogStorage()

        let (_, _, userId) = Ed25519Manager.generateKey()
        testUserId = userId

        // Clean up any existing test data
        try? storage.deleteAllChanges()
    }

    override func tearDown() {
        // Clean up after tests
        try? storage.deleteAllChanges()
        super.tearDown()
    }

    // MARK: - Basic Operations

    func testSaveAndLoadChanges() throws {
        let change = createTestChange(lamport: 1)

        // Save
        try storage.saveChanges(userId: testUserId, newChanges: [change])

        // Load
        let loaded = try storage.getAllChanges(userId: testUserId)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, change.id)
        XCTAssertEqual(loaded[0].action, change.action)
    }

    func testSaveMultipleChanges() throws {
        let changes = [
            createTestChange(lamport: 1),
            createTestChange(lamport: 2),
            createTestChange(lamport: 3)
        ]

        try storage.saveChanges(userId: testUserId, newChanges: changes)

        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertEqual(loaded.count, 3)
    }

    func testAppendChanges() throws {
        // Save first batch
        let batch1 = [createTestChange(lamport: 1)]
        try storage.saveChanges(userId: testUserId, newChanges: batch1)

        // Save second batch
        let batch2 = [createTestChange(lamport: 2)]
        try storage.saveChanges(userId: testUserId, newChanges: batch2)

        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertEqual(loaded.count, 2)
    }

    // MARK: - Deduplication

    func testDeduplication() throws {
        let change = createTestChange(lamport: 1)

        // Save same change twice
        try storage.saveChanges(userId: testUserId, newChanges: [change])
        try storage.saveChanges(userId: testUserId, newChanges: [change])

        let loaded = try storage.getAllChanges(userId: testUserId)

        // Should only have one copy (deduplication by ID)
        XCTAssertEqual(loaded.count, 1)
    }

    func testDeduplicationMultipleChanges() throws {
        let change1 = createTestChange(lamport: 1)
        let change2 = createTestChange(lamport: 2)
        let change3 = createTestChange(lamport: 3)

        // Save changes with some duplicates
        try storage.saveChanges(userId: testUserId, newChanges: [change1, change2])
        try storage.saveChanges(userId: testUserId, newChanges: [change2, change3])

        let loaded = try storage.getAllChanges(userId: testUserId)

        // Should have 3 unique changes
        XCTAssertEqual(loaded.count, 3)
    }

    // MARK: - Multi-User

    func testMultipleUsers() throws {
        let user1 = testUserId!
        let (_, _, user2) = Ed25519Manager.generateKey()

        let change1 = createTestChange(lamport: 1, userId: user1)
        let change2 = createTestChange(lamport: 1, userId: user2)

        try storage.saveChanges(userId: user1, newChanges: [change1])
        try storage.saveChanges(userId: user2, newChanges: [change2])

        // Each user should only see their own changes
        let user1Changes = try storage.getAllChanges(userId: user1)
        let user2Changes = try storage.getAllChanges(userId: user2)

        XCTAssertEqual(user1Changes.count, 1)
        XCTAssertEqual(user1Changes[0].author.userId, user1)

        XCTAssertEqual(user2Changes.count, 1)
        XCTAssertEqual(user2Changes[0].author.userId, user2)
    }

    // MARK: - Delete Operations

    func testDeleteAllChangesForUser() throws {
        let user1 = testUserId!
        let (_, _, user2) = Ed25519Manager.generateKey()

        try storage.saveChanges(userId: user1, newChanges: [createTestChange(lamport: 1, userId: user1)])
        try storage.saveChanges(userId: user2, newChanges: [createTestChange(lamport: 1, userId: user2)])

        // Delete user1's changes
        try storage.deleteAllChanges(userId: user1)

        let user1Changes = try storage.getAllChanges(userId: user1)
        let user2Changes = try storage.getAllChanges(userId: user2)

        XCTAssertEqual(user1Changes.count, 0)
        XCTAssertEqual(user2Changes.count, 1)  // user2's changes remain
    }

    func testDeleteAllChanges() throws {
        try storage.saveChanges(userId: testUserId, newChanges: [
            createTestChange(lamport: 1),
            createTestChange(lamport: 2)
        ])

        try storage.deleteAllChanges()

        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertEqual(loaded.count, 0)
    }

    // MARK: - Query Operations

    func testGetChangesAfter() throws {
        let change1 = createTestChange(lamport: 1)
        let change2 = createTestChange(lamport: 2)
        let change3 = createTestChange(lamport: 3)

        try storage.saveChanges(userId: testUserId, newChanges: [change1, change2, change3])

        let changesAfter = try storage.getChangesAfter(userId: testUserId, afterId: change1.id)

        XCTAssertEqual(changesAfter.count, 2)
        XCTAssertTrue(changesAfter.contains { $0.id == change2.id })
        XCTAssertTrue(changesAfter.contains { $0.id == change3.id })
        XCTAssertFalse(changesAfter.contains { $0.id == change1.id })
    }

    func testGetChangesAfterNonExistent() throws {
        let changes = [
            createTestChange(lamport: 1),
            createTestChange(lamport: 2)
        ]

        try storage.saveChanges(userId: testUserId, newChanges: changes)

        // Query with non-existent ID should return all changes
        let changesAfter = try storage.getChangesAfter(userId: testUserId, afterId: "sha256:nonexistent")

        XCTAssertEqual(changesAfter.count, 2)
    }

    // MARK: - Statistics

    func testGetStats() throws {
        let changes = [
            createTestChange(lamport: 1),
            createTestChange(lamport: 2),
            createTestChange(lamport: 3)
        ]

        try storage.saveChanges(userId: testUserId, newChanges: changes)

        let stats = try storage.getStats()

        XCTAssertEqual(stats["totalChanges"] as? Int, 3)
        XCTAssertNotNil(stats["fileSize"])
        XCTAssertNotNil(stats["lastModified"])
    }

    // MARK: - Export/Import

    func testExportToJSON() throws {
        let changes = [
            createTestChange(lamport: 1),
            createTestChange(lamport: 2)
        ]

        try storage.saveChanges(userId: testUserId, newChanges: changes)

        let json = try storage.exportToJSON()

        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("sha256:"))
        XCTAssertTrue(json.contains(testUserId))
    }

    func testImportFromJSON() throws {
        let change = createTestChange(lamport: 1)
        try storage.saveChanges(userId: testUserId, newChanges: [change])

        // Export
        let json = try storage.exportToJSON()

        // Clear storage
        try storage.deleteAllChanges()

        // Import
        let importedCount = try storage.importFromJSON(json)

        XCTAssertEqual(importedCount, 1)

        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, change.id)
    }

    func testImportDuplicates() throws {
        let change = createTestChange(lamport: 1)

        try storage.saveChanges(userId: testUserId, newChanges: [change])
        let json = try storage.exportToJSON()

        // Import same data (should deduplicate)
        let importedCount = try storage.importFromJSON(json)

        XCTAssertEqual(importedCount, 0)  // No new changes imported

        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertEqual(loaded.count, 1)  // Still only one copy
    }

    // MARK: - Edge Cases

    func testEmptyStorage() throws {
        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveEmptyArray() throws {
        try storage.saveChanges(userId: testUserId, newChanges: [])

        let loaded = try storage.getAllChanges(userId: testUserId)
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Data Persistence

    func testDataPersistsAcrossInstances() throws {
        let change = createTestChange(lamport: 1)

        // Save with first instance
        try storage.saveChanges(userId: testUserId, newChanges: [change])

        // Create new instance
        let newStorage = ChangeLogStorage()

        // Load with second instance
        let loaded = try newStorage.getAllChanges(userId: testUserId)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, change.id)
    }

    // MARK: - Helper Methods

    private func createTestChange(lamport: Int, userId: String? = nil) -> ChangeLogEntry {
        let effectiveUserId = userId ?? testUserId!

        let timestamp = LogicalTimestamp(
            lamport: lamport,
            wallDate: Date()
        )

        let author = AuthorInfo(
            userId: effectiveUserId,
            deviceId: "test_device",
            name: nil,
            publicKey: nil
        )

        let data = ChangeData(dictionary: [
            "title": "Test Task \(lamport)",
            "priority": 3
        ])

        let id = "sha256:" + String(repeating: "\(lamport)", count: 64).prefix(64).padding(toLength: 64, withPad: "0", startingAt: 0)

        return ChangeLogEntry(
            id: id,
            version: 1,
            parents: [],
            timestamp: timestamp,
            author: author,
            action: .create,
            taskId: UUID().uuidString,
            data: data,
            signature: nil
        )
    }
}
