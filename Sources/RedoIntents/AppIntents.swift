import Foundation
import AppIntents
import RedoCore

// MARK: - Create Task App Intent (iOS 16+)

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
struct CreateTaskAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Task"
    static var description = IntentDescription("Create a new task in Redo")

    @Parameter(title: "Title", description: "The task title")
    var title: String

    @Parameter(title: "Description", description: "Task description (optional)", default: "")
    var taskDescription: String

    @Parameter(title: "Priority", description: "Task priority (1-5)", default: 3)
    var priority: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Create task \(\.$title)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Get user ID
        let keychain = KeychainService()
        guard let userId = try? keychain.loadUserId() else {
            throw IntentError.message("Not authenticated")
        }

        // Validate priority
        let validPriority = min(max(priority, 1), 5)

        // Create task
        let storage = ChangeLogStorage()
        let taskId = UUID()

        let change = try createChangeLogEntry(
            userId: userId,
            keychain: keychain,
            storage: storage,
            action: .create,
            taskId: taskId.uuidString,
            data: [
                "title": title,
                "description": taskDescription,
                "priority": validPriority,
                "storyPoints": 1.0,
                "frequencyDays": 0,
                "privacy": false
            ]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])

        // Success
        return .result(
            dialog: "Created task '\(title)' with priority \(validPriority)"
        )
    }
}

// MARK: - Complete Task App Intent

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
struct CompleteTaskAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Mark a task as complete in Redo")

    @Parameter(title: "Task", description: "The task to complete (leave empty for highest priority)")
    var taskTitle: String?

    static var parameterSummary: some ParameterSummary {
        When(\.$taskTitle, .hasAnyValue) {
            Summary("Complete \(\.$taskTitle)")
        } otherwise: {
            Summary("Complete top priority task")
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let keychain = KeychainService()
        guard let userId = try? keychain.loadUserId() else {
            throw IntentError.message("Not authenticated")
        }

        let storage = ChangeLogStorage()
        let validator = ChangeLogValidator()
        let reconstructor = StateReconstructor(validator: validator)

        // Load tasks
        let changes = try storage.getAllChanges(userId: userId)
        let tasks = try reconstructor.reconstructTasks(from: changes)

        // Find task to complete
        let activeTasks = tasks.filter { !$0.archived && $0.hasPendingTodos }

        guard let taskToComplete: RedoTask = {
            if let title = taskTitle {
                return activeTasks.first { $0.title.localizedCaseInsensitiveContains(title) }
            } else {
                return activeTasks.sorted { $0.currentRank() > $1.currentRank() }.first
            }
        }() else {
            throw IntentError.message("No matching task found")
        }

        guard let todo = taskToComplete.currentPendingTask else {
            throw IntentError.message("Task has no pending TODO")
        }

        // Create completion change
        let change = try createChangeLogEntry(
            userId: userId,
            keychain: keychain,
            storage: storage,
            action: .completeTodo,
            taskId: taskToComplete.guid.uuidString,
            data: [
                "todoTaskId": todo.guid.uuidString,
                "completed": ISO8601DateFormatter().string(from: Date()),
                "notes": ""
            ]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])

        return .result(dialog: "Completed '\(taskToComplete.title)'")
    }
}

// MARK: - View Tasks App Intent

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
struct ViewTasksAppIntent: AppIntent {
    static var title: LocalizedStringResource = "View Tasks"
    static var description = IntentDescription("View your tasks in Redo")

    @Parameter(title: "Filter", description: "Filter tasks by status", default: .active)
    var filter: TaskFilterOption

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$filter) tasks")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let keychain = KeychainService()
        guard let userId = try? keychain.loadUserId() else {
            throw IntentError.message("Not authenticated")
        }

        let storage = ChangeLogStorage()
        let validator = ChangeLogValidator()
        let reconstructor = StateReconstructor(validator: validator)

        let changes = try storage.getAllChanges(userId: userId)
        var tasks = try reconstructor.reconstructTasks(from: changes)

        // Apply filter
        tasks = filter.apply(to: tasks)

        // Sort by rank
        tasks.sort { $0.currentRank() > $1.currentRank() }

        let taskCount = tasks.count
        let topTasks = Array(tasks.prefix(5))

        return .result(
            dialog: "You have \(taskCount) \(filter.displayName) tasks"
        )
    }
}

// MARK: - Quick Add Task Intent

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
struct QuickAddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add"
    static var description = IntentDescription("Quickly add a task")

    @Parameter(title: "Task")
    var title: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let intent = CreateTaskAppIntent()
        intent.title = title
        intent.taskDescription = ""
        intent.priority = 3
        _ = try await intent.perform()
        return .result(dialog: "Added '\(title)'")
    }
}

// MARK: - Supporting Types

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
enum TaskFilterOption: String, AppEnum {
    case all
    case active
    case overdue
    case highPriority

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task Filter")
    static var caseDisplayRepresentations: [TaskFilterOption: DisplayRepresentation] = [
        .all: "All Tasks",
        .active: "Active Tasks",
        .overdue: "Overdue Tasks",
        .highPriority: "High Priority Tasks"
    ]

    var displayName: String {
        switch self {
        case .all: return "all"
        case .active: return "active"
        case .overdue: return "overdue"
        case .highPriority: return "high priority"
        }
    }

    func apply(to tasks: [RedoTask]) -> [RedoTask] {
        switch self {
        case .all:
            return tasks.filter { !$0.archived }
        case .active:
            return tasks.filter { !$0.archived && $0.hasPendingTodos }
        case .overdue:
            return tasks.filter { $0.isOverdue }
        case .highPriority:
            return tasks.filter { $0.priority >= 4 }
        }
    }
}

// MARK: - Snippet Views removed
// Note: SwiftUI views removed as they're not compatible with Intents extension
// App Intents in iOS 16+ use dialog-based results instead

// MARK: - Shortcuts Provider

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
struct RedoShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Create a task in \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: CompleteTaskAppIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Mark task done in \(.applicationName)",
                "Finish task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: ViewTasksAppIntent(),
            phrases: [
                "Show my tasks in \(.applicationName)",
                "View tasks in \(.applicationName)",
                "What are my tasks"
            ],
            shortTitle: "View Tasks",
            systemImageName: "list.bullet"
        )
    }
}

// MARK: - Helper Functions

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
private func createChangeLogEntry(
    userId: String,
    keychain: KeychainService,
    storage: ChangeLogStorage,
    action: ChangeAction,
    taskId: String,
    data: [String: Any]
) throws -> ChangeLogEntry {
    // Implementation same as in IntentHandlers.swift
    let allChanges = try storage.getAllChanges(userId: userId)
    let lamportClock = (allChanges.map { $0.timestamp.lamport }.max() ?? 0) + 1

    let lastChange = allChanges
        .filter { $0.taskId == taskId }
        .max(by: { $0.timestamp.lamport < $1.timestamp.lamport })
    let parents = lastChange != nil ? [lastChange!.id] : []

    let timestamp = LogicalTimestamp(
        lamport: lamportClock,
        wall: ISO8601DateFormatter().string(from: Date())
    )

    let publicKey = try keychain.loadPublicKey() ?? ""
    let author = AuthorInfo(
        userId: userId,
        deviceId: try keychain.loadDeviceId() ?? "",
        name: nil,
        publicKey: publicKey
    )

    var entry = ChangeLogEntry(
        id: "",
        version: 1,
        parents: parents,
        timestamp: timestamp,
        author: author,
        action: action,
        taskId: taskId,
        data: ChangeData(dictionary: data),
        signature: nil
    )

    let changeId = try ContentAddressing.calculateChangeId(entry: entry)
    entry = ChangeLogEntry(
        id: changeId,
        version: entry.version,
        parents: entry.parents,
        timestamp: entry.timestamp,
        author: entry.author,
        action: entry.action,
        taskId: entry.taskId,
        data: entry.data,
        signature: entry.signature
    )

    return entry
}

enum IntentError: Error {
    case message(String)
}
