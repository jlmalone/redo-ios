import Foundation
import Intents
import RedoCore

// MARK: - Create Task Intent Handler

@available(iOS 16.0, *)
class CreateTaskIntentHandler: NSObject, CreateTaskIntentHandling {
    func handle(intent: CreateTaskIntent) async -> CreateTaskIntentResponse {
        guard let title = intent.title, !title.isEmpty else {
            return CreateTaskIntentResponse(code: .failure, userActivity: nil)
        }

        do {
            // Get user ID
            let keychain = KeychainService()
            guard let userId = try? keychain.loadUserId() else {
                return CreateTaskIntentResponse(code: .failure, userActivity: nil)
            }

            // Create change log entry
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
                    "description": intent.taskDescription ?? "",
                    "priority": intent.priority?.intValue ?? 3,
                    "storyPoints": 1.0,
                    "frequencyDays": 0,
                    "privacy": false
                ]
            )

            try storage.saveChanges(userId: userId, newChanges: [change])

            let response = CreateTaskIntentResponse(code: .success, userActivity: nil)
            response.taskTitle = title
            return response

        } catch {
            return CreateTaskIntentResponse(code: .failure, userActivity: nil)
        }
    }

    func resolveTitle(for intent: CreateTaskIntent) async -> INStringResolutionResult {
        guard let title = intent.title, !title.isEmpty else {
            return INStringResolutionResult.needsValue()
        }
        return INStringResolutionResult.success(with: title)
    }

    func resolvePriority(for intent: CreateTaskIntent) async -> INIntegerResolutionResult {
        guard let priority = intent.priority else {
            return INIntegerResolutionResult.success(with: 3) // Default: medium priority
        }
        let priorityInt = priority.intValue
        // Clamp to valid range 1-5
        let validPriority = min(max(priorityInt, 1), 5)
        return INIntegerResolutionResult.success(with: validPriority)
    }
}

// MARK: - Complete Task Intent Handler

@available(iOS 16.0, *)
class CompleteTaskIntentHandler: NSObject, CompleteTaskIntentHandling {
    func handle(intent: CompleteTaskIntent) async -> CompleteTaskIntentResponse {
        do {
            let keychain = KeychainService()
            guard let userId = try? keychain.loadUserId() else {
                return CompleteTaskIntentResponse(code: .failure, userActivity: nil)
            }

            let storage = ChangeLogStorage()
            let reconstructor = StateReconstructor()

            // Load tasks
            let changes = try storage.getAllChanges(userId: userId)
            let tasks = try reconstructor.reconstructTasks(from: changes)

            // Find task to complete
            let activeTasks = tasks.filter { !$0.archived && $0.hasPendingTodos }

            guard let taskToComplete: RedoTask = {
                if let taskTitle = intent.taskTitle {
                    return activeTasks.first { $0.title.localizedCaseInsensitiveContains(taskTitle) }
                } else {
                    return activeTasks.sorted { $0.currentRank() > $1.currentRank() }.first
                }
            }() else {
                return CompleteTaskIntentResponse(code: .failure, userActivity: nil)
            }

            guard let todo = taskToComplete.currentPendingTask else {
                return CompleteTaskIntentResponse(code: .failure, userActivity: nil)
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

            let response = CompleteTaskIntentResponse(code: .success, userActivity: nil)
            response.completedTaskTitle = taskToComplete.title
            return response

        } catch {
            return CompleteTaskIntentResponse(code: .failure, userActivity: nil)
        }
    }

    func provideTaskTitleOptionsCollection(for intent: CompleteTaskIntent) async throws -> INObjectCollection<NSString> {
        do {
            let keychain = KeychainService()
            guard let userId = try? keychain.loadUserId() else {
                return INObjectCollection(items: [])
            }

            let storage = ChangeLogStorage()
            let reconstructor = StateReconstructor()

            let changes = try storage.getAllChanges(userId: userId)
            let tasks = try reconstructor.reconstructTasks(from: changes)

            let activeTasks = tasks
                .filter { !$0.archived && $0.hasPendingTodos }
                .sorted { $0.currentRank() > $1.currentRank() }
                .prefix(10)
                .map { $0.title as NSString }

            return INObjectCollection(items: Array(activeTasks))
        } catch {
            return INObjectCollection(items: [])
        }
    }
}

// MARK: - View Tasks Intent Handler

@available(iOS 16.0, *)
class ViewTasksIntentHandler: NSObject, ViewTasksIntentHandling {
    func handle(intent: ViewTasksIntent) async -> ViewTasksIntentResponse {
        do {
            let keychain = KeychainService()
            guard let userId = try? keychain.loadUserId() else {
                return ViewTasksIntentResponse(code: .failure, userActivity: nil)
            }

            let storage = ChangeLogStorage()
            let reconstructor = StateReconstructor()

            let changes = try storage.getAllChanges(userId: userId)
            var tasks = try reconstructor.reconstructTasks(from: changes)

            // Apply filter
            switch intent.filter {
            case .all:
                tasks = tasks.filter { !$0.archived }
            case .active:
                tasks = tasks.filter { !$0.archived && $0.hasPendingTodos }
            case .overdue:
                tasks = tasks.filter { $0.isOverdue }
            case .highPriority:
                tasks = tasks.filter { $0.priority >= 4 }
            default:
                tasks = tasks.filter { !$0.archived }
            }

            // Sort by rank
            tasks.sort { $0.currentRank() > $1.currentRank() }

            // Format response
            let taskDescriptions = tasks.prefix(5).map { task in
                let priorityText = String(repeating: "!", count: task.priority)
                let overdueText = task.isOverdue ? " [OVERDUE]" : ""
                return "[\(priorityText)] \(task.title)\(overdueText)"
            }.joined(separator: "\n")

            let response = ViewTasksIntentResponse(code: .success, userActivity: nil)
            response.taskCount = NSNumber(value: tasks.count)
            response.taskList = taskDescriptions
            return response

        } catch {
            return ViewTasksIntentResponse(code: .failure, userActivity: nil)
        }
    }
}

// MARK: - Helper Functions

@available(iOS 16.0, *)
private func createChangeLogEntry(
    userId: String,
    keychain: KeychainService,
    storage: ChangeLogStorage,
    action: ChangeAction,
    taskId: String,
    data: [String: Any]
) throws -> ChangeLogEntry {
    // Get Lamport clock
    let allChanges = try storage.getAllChanges(userId: userId)
    let lamportClock = (allChanges.map { $0.timestamp.lamport }.max() ?? 0) + 1

    // Get parent
    let lastChange = allChanges
        .filter { $0.taskId == taskId }
        .max(by: { $0.timestamp.lamport < $1.timestamp.lamport })
    let parents = lastChange != nil ? [lastChange!.id] : []

    // Create timestamp
    let timestamp = LogicalTimestamp(
        lamport: lamportClock,
        wall: ISO8601DateFormatter().string(from: Date())
    )

    // Create author
    let publicKey = try keychain.loadPublicKey() ?? ""
    let author = AuthorInfo(
        userId: userId,
        deviceId: try keychain.loadDeviceId() ?? "",
        name: nil,
        publicKey: publicKey
    )

    // Create entry
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

    // Calculate ID
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
