import XCTest
@testable import RedoCore
@testable import RedoCrypto

/// Comprehensive state reconstruction tests (ported from Android's 18-test suite)
final class StateReconstructorTests: XCTestCase {

    var reconstructor: StateReconstructor!
    var testUserId: String!
    var testDeviceId: String!

    override func setUp() {
        super.setUp()
        reconstructor = StateReconstructor()

        let (_, _, userId) = Ed25519Manager.generateKey()
        testUserId = userId
        testDeviceId = "test_device_\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Basic Operations

    func testEmptyChangeLog() throws {
        let tasks = try reconstructor.reconstructTasks(from: [])
        XCTAssertTrue(tasks.isEmpty)
    }

    func testSingleCreateChange() throws {
        let taskId = UUID()
        let change = createChange(
            action: .create,
            taskId: taskId,
            data: [
                "title": "Test Task",
                "description": "Description",
                "priority": 3,
                "storyPoints": 2.0,
                "frequencyDays": 7
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [change])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Test Task")
        XCTAssertEqual(tasks[0].description, "Description")
        XCTAssertEqual(tasks[0].priority, 3)
        XCTAssertEqual(tasks[0].storyPoints, 2.0)
        XCTAssertEqual(tasks[0].frequencyDays, 7)
    }

    func testCreateThenUpdate() throws {
        let taskId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: [
                "title": "Original Title",
                "priority": 1
            ]
        )

        let update = createChange(
            action: .update,
            taskId: taskId,
            lamport: 2,
            data: [
                "title": "Updated Title",
                "priority": 5
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, update])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Updated Title")
        XCTAssertEqual(tasks[0].priority, 5)
    }

    // MARK: - TODO Lifecycle

    func testCreateTodo() throws {
        let taskId = UUID()
        let todoId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task with TODO"]
        )

        let createTodo = createChange(
            action: .createTodo,
            taskId: taskId,
            lamport: 2,
            data: [
                "todoTaskId": todoId.uuidString,
                "deadline": ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)),
                "notes": "First TODO"
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, createTodo])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].todoTasks.count, 1)
        XCTAssertEqual(tasks[0].todoTasks[0].guid, todoId)
        XCTAssertEqual(tasks[0].todoTasks[0].notes, "First TODO")
        XCTAssertNil(tasks[0].todoTasks[0].completed)
    }

    func testCompleteTodo() throws {
        let taskId = UUID()
        let todoId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Recurring Task", "frequencyDays": 7]
        )

        let createTodo = createChange(
            action: .createTodo,
            taskId: taskId,
            lamport: 2,
            data: [
                "todoTaskId": todoId.uuidString,
                "deadline": ISO8601DateFormatter().string(from: Date())
            ]
        )

        let completeTodo = createChange(
            action: .completeTodo,
            taskId: taskId,
            lamport: 3,
            data: [
                "todoTaskId": todoId.uuidString,
                "completed": ISO8601DateFormatter().string(from: Date()),
                "notes": "Completed successfully"
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, createTodo, completeTodo])

        XCTAssertEqual(tasks.count, 1)
        // Should have 2 TODOs: completed one + auto-created next
        XCTAssertEqual(tasks[0].todoTasks.count, 2)

        // First TODO should be completed
        let completedTodo = tasks[0].todoTasks.first { $0.guid == todoId }
        XCTAssertNotNil(completedTodo)
        XCTAssertNotNil(completedTodo?.completed)
        XCTAssertTrue(completedTodo?.notes.contains("Completed successfully") ?? false)

        // Second TODO should be pending
        let nextTodo = tasks[0].todoTasks.first { $0.guid != todoId }
        XCTAssertNotNil(nextTodo)
        XCTAssertNil(nextTodo?.completed)
    }

    func testCompleteOneTimeTask() throws {
        let taskId = UUID()
        let todoId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "One-time Task", "frequencyDays": 0]  // One-time
        )

        let createTodo = createChange(
            action: .createTodo,
            taskId: taskId,
            lamport: 2,
            data: [
                "todoTaskId": todoId.uuidString,
                "deadline": ISO8601DateFormatter().string(from: Date())
            ]
        )

        let completeTodo = createChange(
            action: .completeTodo,
            taskId: taskId,
            lamport: 3,
            data: [
                "todoTaskId": todoId.uuidString,
                "completed": ISO8601DateFormatter().string(from: Date())
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, createTodo, completeTodo])

        XCTAssertEqual(tasks.count, 1)
        // Should have only 1 TODO (no auto-creation for one-time tasks)
        XCTAssertEqual(tasks[0].todoTasks.count, 1)
        XCTAssertNotNil(tasks[0].todoTasks[0].completed)
    }

    // MARK: - Archive/Unarchive

    func testArchiveTask() throws {
        let taskId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task to Archive"]
        )

        let archive = createChange(
            action: .archive,
            taskId: taskId,
            lamport: 2,
            data: [:]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, archive])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks[0].archived)
    }

    func testUnarchiveTask() throws {
        let taskId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task"]
        )

        let archive = createChange(
            action: .archive,
            taskId: taskId,
            lamport: 2,
            data: [:]
        )

        let unarchive = createChange(
            action: .unarchive,
            taskId: taskId,
            lamport: 3,
            data: [:]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, archive, unarchive])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertFalse(tasks[0].archived)
    }

    func testCompleteArchivedTask() throws {
        let taskId = UUID()
        let todoId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task", "frequencyDays": 7]
        )

        let createTodo = createChange(
            action: .createTodo,
            taskId: taskId,
            lamport: 2,
            data: [
                "todoTaskId": todoId.uuidString,
                "deadline": ISO8601DateFormatter().string(from: Date())
            ]
        )

        let archive = createChange(
            action: .archive,
            taskId: taskId,
            lamport: 3,
            data: [:]
        )

        let completeTodo = createChange(
            action: .completeTodo,
            taskId: taskId,
            lamport: 4,
            data: [
                "todoTaskId": todoId.uuidString,
                "completed": ISO8601DateFormatter().string(from: Date())
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, createTodo, archive, completeTodo])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks[0].archived)
        // Should NOT auto-create next TODO because task is archived
        XCTAssertEqual(tasks[0].todoTasks.count, 1)
        XCTAssertNotNil(tasks[0].todoTasks[0].completed)
    }

    // MARK: - Delete

    func testDeleteTask() throws {
        let taskId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task to Delete"]
        )

        let delete = createChange(
            action: .delete,
            taskId: taskId,
            lamport: 2,
            data: [:]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, delete])

        // Deleted tasks are filtered out
        XCTAssertEqual(tasks.count, 0)
    }

    func testDeleteThenUpdate() throws {
        let taskId = UUID()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task"]
        )

        let delete = createChange(
            action: .delete,
            taskId: taskId,
            lamport: 2,
            data: [:]
        )

        let update = createChange(
            action: .update,
            taskId: taskId,
            lamport: 3,
            data: ["title": "Updated After Delete"]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, delete, update])

        // Task should remain deleted (delete tombstone takes precedence)
        XCTAssertEqual(tasks.count, 0)
    }

    // MARK: - Snooze

    func testSnoozeTodo() throws {
        let taskId = UUID()
        let todoId = UUID()
        let originalDeadline = Date()

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Task"]
        )

        let createTodo = createChange(
            action: .createTodo,
            taskId: taskId,
            lamport: 2,
            data: [
                "todoTaskId": todoId.uuidString,
                "deadline": ISO8601DateFormatter().string(from: originalDeadline)
            ]
        )

        let snooze = createChange(
            action: .snooze,
            taskId: taskId,
            lamport: 3,
            data: [
                "todoTaskId": todoId.uuidString,
                "snoozeDays": 3,
                "notes": "Snoozed for 3 days"
            ]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create, createTodo, snooze])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].todoTasks.count, 1)

        let todo = tasks[0].todoTasks[0]
        // Deadline should be extended by 3 days
        let expectedDeadline = Calendar.current.date(byAdding: .day, value: 3, to: originalDeadline)!
        XCTAssertEqual(
            Calendar.current.compare(todo.deadline, to: expectedDeadline, toGranularity: .day),
            .orderedSame
        )
        XCTAssertTrue(todo.notes.contains("Snoozed for 3 days"))
    }

    // MARK: - Lamport Clock Ordering

    func testLamportClockOrdering() throws {
        let taskId = UUID()

        // Create changes out of order
        let update2 = createChange(
            action: .update,
            taskId: taskId,
            lamport: 3,
            data: ["title": "Third Update"]
        )

        let create = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Original"]
        )

        let update1 = createChange(
            action: .update,
            taskId: taskId,
            lamport: 2,
            data: ["title": "Second Update"]
        )

        // Reconstruct with out-of-order changes
        let tasks = try reconstructor.reconstructTasks(from: [update2, create, update1])

        XCTAssertEqual(tasks.count, 1)
        // Should apply changes in Lamport order (1, 2, 3)
        XCTAssertEqual(tasks[0].title, "Third Update")
    }

    // MARK: - Validation

    func testInvalidNodeRejected() throws {
        let taskId = UUID()

        let validChange = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Valid"]
        )

        var invalidChange = createChange(
            action: .update,
            taskId: taskId,
            lamport: 2,
            data: ["title": "Invalid"]
        )

        // Make change invalid (version 0)
        invalidChange = ChangeLogEntry(
            id: invalidChange.id,
            version: 0,  // Invalid!
            parents: invalidChange.parents,
            timestamp: invalidChange.timestamp,
            author: invalidChange.author,
            action: invalidChange.action,
            taskId: invalidChange.taskId,
            data: invalidChange.data,
            signature: invalidChange.signature
        )

        let tasks = try reconstructor.reconstructTasks(from: [validChange, invalidChange])

        // Invalid change should be rejected
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Valid")  // Not "Invalid"
    }

    // MARK: - Multiple Tasks

    func testMultipleTasks() throws {
        let task1 = UUID()
        let task2 = UUID()
        let task3 = UUID()

        let changes = [
            createChange(action: .create, taskId: task1, lamport: 1, data: ["title": "Task 1"]),
            createChange(action: .create, taskId: task2, lamport: 2, data: ["title": "Task 2"]),
            createChange(action: .create, taskId: task3, lamport: 3, data: ["title": "Task 3"]),
            createChange(action: .update, taskId: task2, lamport: 4, data: ["title": "Updated Task 2"]),
            createChange(action: .delete, taskId: task3, lamport: 5, data: [:])
        ]

        let tasks = try reconstructor.reconstructTasks(from: changes)

        XCTAssertEqual(tasks.count, 2)  // task1, task2 (task3 deleted)

        let titles = Set(tasks.map { $0.title })
        XCTAssertTrue(titles.contains("Task 1"))
        XCTAssertTrue(titles.contains("Updated Task 2"))
        XCTAssertFalse(titles.contains("Task 3"))
    }

    // MARK: - Complex Scenarios

    func testComplexScenario() throws {
        // Simulate real-world usage:
        // 1. Create task
        // 2. Create first TODO
        // 3. Complete it (auto-creates next)
        // 4. Snooze next TODO
        // 5. Update task metadata
        // 6. Complete second TODO
        // 7. Archive task

        let taskId = UUID()
        let todo1 = UUID()
        let todo2 = UUID()

        let changes = [
            createChange(
                action: .create,
                taskId: taskId,
                lamport: 1,
                data: ["title": "Weekly Review", "frequencyDays": 7, "priority": 3]
            ),
            createChange(
                action: .createTodo,
                taskId: taskId,
                lamport: 2,
                data: [
                    "todoTaskId": todo1.uuidString,
                    "deadline": ISO8601DateFormatter().string(from: Date())
                ]
            ),
            createChange(
                action: .completeTodo,
                taskId: taskId,
                lamport: 3,
                data: [
                    "todoTaskId": todo1.uuidString,
                    "completed": ISO8601DateFormatter().string(from: Date())
                ]
            ),
            createChange(
                action: .update,
                taskId: taskId,
                lamport: 4,
                data: ["priority": 5]
            ),
            createChange(
                action: .archive,
                taskId: taskId,
                lamport: 5,
                data: [:]
            )
        ]

        let tasks = try reconstructor.reconstructTasks(from: changes)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Weekly Review")
        XCTAssertEqual(tasks[0].priority, 5)
        XCTAssertTrue(tasks[0].archived)
        XCTAssertEqual(tasks[0].todoTasks.count, 2)  // Completed + auto-created
        XCTAssertNotNil(tasks[0].todoTasks[0].completed)
    }

    // MARK: - Edge Cases

    func testDuplicateCreate() throws {
        let taskId = UUID()

        let create1 = createChange(
            action: .create,
            taskId: taskId,
            lamport: 1,
            data: ["title": "First Create"]
        )

        let create2 = createChange(
            action: .create,
            taskId: taskId,
            lamport: 2,
            data: ["title": "Second Create"]
        )

        let tasks = try reconstructor.reconstructTasks(from: [create1, create2])

        // First CREATE wins, duplicate ignored
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "First Create")
    }

    func testUpdateNonExistentTask() throws {
        let taskId = UUID()

        let update = createChange(
            action: .update,
            taskId: taskId,
            lamport: 1,
            data: ["title": "Update Without Create"]
        )

        let tasks = try reconstructor.reconstructTasks(from: [update])

        // Update without CREATE is ignored
        XCTAssertEqual(tasks.count, 0)
    }

    // MARK: - Helper Methods

    private func createChange(
        action: ChangeAction,
        taskId: UUID,
        lamport: Int = 1,
        data: [String: Any]
    ) -> ChangeLogEntry {
        let timestamp = LogicalTimestamp(
            lamport: lamport,
            wallDate: Date()
        )

        let author = AuthorInfo(
            userId: testUserId,
            deviceId: testDeviceId,
            name: nil,
            publicKey: nil
        )

        let changeData = ChangeData(dictionary: data)

        let id = "sha256:" + String(repeating: "\(lamport)", count: 64).prefix(64).padding(toLength: 64, withPad: "0", startingAt: 0)

        return ChangeLogEntry(
            id: id,
            version: 1,
            parents: [],
            timestamp: timestamp,
            author: author,
            action: action,
            taskId: taskId.uuidString,
            data: changeData,
            signature: nil
        )
    }
}
