import Foundation

/// Reconstructs current task state from immutable change log (event sourcing)
public class StateReconstructor {

    // MARK: - Public API

    /// Reconstruct all tasks from change log
    /// - Parameter changes: Array of change log entries
    /// - Returns: Array of reconstructed RedoTask objects
    /// - Throws: ReconstructionError if reconstruction fails
    public func reconstructTasks(from changes: [ChangeLogEntry]) throws -> [RedoTask] {
        var tasks: [String: RedoTask] = [:]

        // 1. Sort by Lamport clock (causal ordering)
        let sortedChanges = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

        // 2. Validate all changes (strict v1 enforcement)
        let validChanges = sortedChanges.filter { change in
            let validator = ChangeLogValidator()
            if !validator.isValidV1Node(change) {
                print("⚠️ Rejecting invalid change: \(change.id)")
                return false
            }
            return true
        }

        // 3. Replay each change
        for change in validChanges {
            try applyChange(change, to: &tasks)
        }

        // 4. Filter out deleted tasks
        let activeTasks = tasks.values.filter { task in
            // Check if task has been deleted
            !isDeleted(taskId: task.guid.uuidString, in: validChanges)
        }

        return Array(activeTasks)
    }

    // MARK: - Change Application

    private func applyChange(_ change: ChangeLogEntry, to tasks: inout [String: RedoTask]) throws {
        switch change.action {
        case .create:
            try handleCreate(change, tasks: &tasks)
        case .update:
            try handleUpdate(change, tasks: &tasks)
        case .createTodo:
            try handleCreateTodo(change, tasks: &tasks)
        case .completeTodo:
            try handleCompleteTodo(change, tasks: &tasks)
        case .snooze:
            try handleSnooze(change, tasks: &tasks)
        case .archive:
            try handleArchive(change, tasks: &tasks)
        case .unarchive:
            try handleUnarchive(change, tasks: &tasks)
        case .delete:
            try handleDelete(change, tasks: &tasks)
        }
    }

    // MARK: - Action Handlers

    private func handleCreate(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        // Check for duplicate CREATE
        if tasks[taskId] != nil {
            print("⚠️ Duplicate CREATE for task \(taskId), ignoring")
            return
        }

        let fields = change.data.fields

        let task = RedoTask(
            guid: UUID(uuidString: taskId) ?? UUID(),
            userId: change.author.userId,
            title: fields["title"]?.stringValue ?? "",
            description: fields["description"]?.stringValue ?? "",
            privacy: fields["privacy"]?.boolValue ?? false,
            storyPoints: Float(fields["storyPoints"]?.doubleValue ?? 1.0),
            priority: fields["priority"]?.intValue ?? 3,
            frequencyDays: fields["frequencyDays"]?.intValue ?? 7,
            created: change.timestamp.wallDate ?? Date(),
            archived: false,
            lastUpdated: nil,
            todoTasks: []
        )

        tasks[taskId] = task
    }

    private func handleUpdate(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        guard var task = tasks[taskId] else {
            print("⚠️ UPDATE for non-existent task \(taskId), ignoring")
            return
        }

        let fields = change.data.fields

        // Update fields (only if present in change data)
        if let title = fields["title"]?.stringValue {
            task.title = title
        }
        if let description = fields["description"]?.stringValue {
            task.description = description
        }
        if let privacy = fields["privacy"]?.boolValue {
            task.privacy = privacy
        }
        if let storyPoints = fields["storyPoints"]?.doubleValue {
            task.storyPoints = Float(storyPoints)
        }
        if let priority = fields["priority"]?.intValue {
            task.priority = priority
        }
        if let frequencyDays = fields["frequencyDays"]?.intValue {
            task.frequencyDays = frequencyDays
        }

        task.lastUpdated = change.timestamp.wallDate ?? Date()

        tasks[taskId] = task
    }

    private func handleCreateTodo(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        guard var task = tasks[taskId] else {
            print("⚠️ CREATE_TODO for non-existent task \(taskId), ignoring")
            return
        }

        let fields = change.data.fields

        guard let todoTaskIdStr = fields["todoTaskId"]?.stringValue,
              let deadlineStr = fields["deadline"]?.stringValue,
              let todoTaskId = UUID(uuidString: todoTaskIdStr),
              let deadline = ISO8601DateFormatter().date(from: deadlineStr) else {
            print("⚠️ CREATE_TODO missing required fields, ignoring")
            return
        }

        let todo = TodoTask(
            guid: todoTaskId,
            redoParentGuid: task.guid,
            created: change.timestamp.wallDate ?? Date(),
            notes: fields["notes"]?.stringValue ?? "",
            deadline: deadline,
            completed: nil
        )

        task.todoTasks.append(todo)
        tasks[taskId] = task
    }

    private func handleCompleteTodo(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        guard var task = tasks[taskId] else {
            print("⚠️ COMPLETE_TODO for non-existent task \(taskId), ignoring")
            return
        }

        let fields = change.data.fields

        guard let todoTaskIdStr = fields["todoTaskId"]?.stringValue,
              let completedStr = fields["completed"]?.stringValue,
              let completed = ISO8601DateFormatter().date(from: completedStr) else {
            print("⚠️ COMPLETE_TODO missing required fields, ignoring")
            return
        }

        // Mark todo as completed
        if let todoIndex = task.todoTasks.firstIndex(where: { $0.guid.uuidString == todoTaskIdStr }) {
            var todo = task.todoTasks[todoIndex]
            todo.completed = completed

            // Append notes
            if let notes = fields["notes"]?.stringValue, !notes.isEmpty {
                todo.notes += (todo.notes.isEmpty ? "" : "\n") + notes
            }

            task.todoTasks[todoIndex] = todo

            // Auto-create next todo for recurring tasks
            if !task.archived && task.frequencyDays > 0 {
                let nextDeadline = Calendar.current.date(
                    byAdding: .day,
                    value: task.frequencyDays,
                    to: completed
                ) ?? completed.addingTimeInterval(TimeInterval(task.frequencyDays * 86400))

                let nextTodo = TodoTask(
                    guid: UUID(),
                    redoParentGuid: task.guid,
                    created: completed,
                    notes: "",
                    deadline: nextDeadline,
                    completed: nil
                )

                task.todoTasks.append(nextTodo)
            }
        }

        tasks[taskId] = task
    }

    private func handleSnooze(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        guard var task = tasks[taskId] else {
            print("⚠️ SNOOZE for non-existent task \(taskId), ignoring")
            return
        }

        let fields = change.data.fields

        guard let todoTaskIdStr = fields["todoTaskId"]?.stringValue else {
            print("⚠️ SNOOZE missing todoTaskId, ignoring")
            return
        }

        if let todoIndex = task.todoTasks.firstIndex(where: { $0.guid.uuidString == todoTaskIdStr }) {
            var todo = task.todoTasks[todoIndex]

            // Update deadline
            if let newDeadlineStr = fields["newDeadline"]?.stringValue,
               let newDeadline = ISO8601DateFormatter().date(from: newDeadlineStr) {
                todo.deadline = newDeadline
            } else if let snoozeDays = fields["snoozeDays"]?.intValue {
                todo.deadline = Calendar.current.date(
                    byAdding: .day,
                    value: snoozeDays,
                    to: todo.deadline
                ) ?? todo.deadline.addingTimeInterval(TimeInterval(snoozeDays * 86400))
            }

            // Append snooze note
            if let notes = fields["notes"]?.stringValue, !notes.isEmpty {
                todo.notes += (todo.notes.isEmpty ? "" : "\n") + notes
            }

            task.todoTasks[todoIndex] = todo
        }

        tasks[taskId] = task
    }

    private func handleArchive(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        guard var task = tasks[taskId] else {
            print("⚠️ ARCHIVE for non-existent task \(taskId), ignoring")
            return
        }

        task.archived = true
        task.lastUpdated = change.timestamp.wallDate ?? Date()
        tasks[taskId] = task
    }

    private func handleUnarchive(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else {
            throw ReconstructionError.missingTaskId(changeId: change.id)
        }

        guard var task = tasks[taskId] else {
            print("⚠️ UNARCHIVE for non-existent task \(taskId), ignoring")
            return
        }

        task.archived = false
        task.lastUpdated = change.timestamp.wallDate ?? Date()
        tasks[taskId] = task
    }

    private func handleDelete(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        // DELETE is a tombstone marker, actual deletion happens in isDeleted check
        // We keep the task in the map during reconstruction for branch tracking
    }

    // MARK: - Delete Branch Tracking

    private func isDeleted(taskId: String, in changes: [ChangeLogEntry]) -> Bool {
        // Check if there's a DELETE action for this task
        changes.contains { change in
            change.action == .delete && change.taskId == taskId
        }
    }
}

// MARK: - Errors

public enum ReconstructionError: Error, LocalizedError {
    case missingTaskId(changeId: String)
    case invalidChangeAction(changeId: String, action: String)
    case inconsistentState(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingTaskId(let changeId):
            return "Change \(changeId) is missing required taskId field"
        case .invalidChangeAction(let changeId, let action):
            return "Change \(changeId) has invalid action: \(action)"
        case .inconsistentState(let message):
            return "Inconsistent state during reconstruction: \(message)"
        }
    }
}
