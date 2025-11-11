import Foundation
import SwiftUI
import Combine
import RedoCore
import RedoCrypto

/// Main view model for the Redo app (MVVM pattern)
@MainActor
public class AppViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var tasks: [RedoTask] = []
    @Published public var filteredTasks: [RedoTask] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var syncStatus: SyncStatus = .idle

    // Filters
    @Published public var showArchived = false
    @Published public var searchText = ""
    @Published public var selectedPriority: Int? = nil
    @Published public var selectedPriorities: Set<Int> = []
    @Published public var showOnlyOverdue = false
    @Published public var showOnlyActive = false
    @Published public var searchScope: SearchScope = .both
    @Published public var sortOption: SortOption = .rank
    @Published public var dateFilter: DateFilter? = nil

    // User identity
    @Published public var userId: String = ""
    @Published public var deviceId: String = ""
    @Published public var isAuthenticated = false

    // MARK: - Services

    private let storage: ChangeLogStorage
    private let keychain: KeychainService
    private let stateReconstructor: StateReconstructor
    private var firebaseSync: FirebaseSyncService?

    private var cancellables = Set<AnyCancellable>()
    private var lamportClock: Int = 0

    // MARK: - Initialization

    public init(
        storage: ChangeLogStorage = ChangeLogStorage(),
        keychain: KeychainService = KeychainService()
    ) {
        self.storage = storage
        self.keychain = keychain
        self.stateReconstructor = StateReconstructor()

        setupObservers()
        Task { await initializeApp() }
    }

    // MARK: - App Initialization

    private func initializeApp() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 1. Load or generate crypto identity
            try await loadOrGenerateIdentity()

            // 2. Load change log and reconstruct state
            try await reconstructState()

            // 3. Initialize Firebase sync (if authenticated)
            await initializeFirebaseSync()

            isAuthenticated = true
        } catch {
            errorMessage = "Failed to initialize app: \(error.localizedDescription)"
        }
    }

    // MARK: - Identity Management

    private func loadOrGenerateIdentity() async throws {
        // Check if we have existing keys in Keychain
        if let existingUserId = try? keychain.loadUserId(),
           let existingDeviceId = try? keychain.loadDeviceId() {
            userId = existingUserId
            deviceId = existingDeviceId
        } else {
            // Generate new Ed25519 keypair
            let (publicKey, privateKey, newUserId) = Ed25519Manager.generateKey()

            // Save to Keychain
            try keychain.savePublicKey(publicKey)
            try keychain.savePrivateKey(privateKey)
            try keychain.saveUserId(newUserId)

            // Generate device ID
            let newDeviceId = UUID().uuidString
            try keychain.saveDeviceId(newDeviceId)

            userId = newUserId
            deviceId = newDeviceId
        }
    }

    // MARK: - State Reconstruction

    public func reconstructState() async throws {
        let changes = try storage.getAllChanges(userId: userId)

        // Update Lamport clock to max
        lamportClock = changes.map { $0.timestamp.lamport }.max() ?? 0

        // Reconstruct tasks from change log
        let reconstructedTasks = try stateReconstructor.reconstructTasks(from: changes)

        tasks = reconstructedTasks
        applyFilters()
    }

    // MARK: - Task Operations

    public func createTask(
        title: String,
        description: String,
        priority: Int,
        storyPoints: Float,
        frequencyDays: Int
    ) async throws {
        let taskId = UUID()

        // Create change log entry
        let change = try createChangeLogEntry(
            action: .create,
            taskId: taskId.uuidString,
            data: [
                "title": title,
                "description": description,
                "priority": priority,
                "storyPoints": storyPoints,
                "frequencyDays": frequencyDays,
                "privacy": false
            ]
        )

        // Save locally
        try storage.saveChanges(userId: userId, newChanges: [change])

        // Sync with Firebase (if available)
        await syncChanges()

        // Reconstruct state
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskCreated()
    }

    public func updateTask(
        taskId: UUID,
        title: String?,
        description: String?,
        priority: Int?,
        storyPoints: Float?,
        frequencyDays: Int?
    ) async throws {
        var fields: [String: Any] = [:]

        if let title = title { fields["title"] = title }
        if let description = description { fields["description"] = description }
        if let priority = priority { fields["priority"] = priority }
        if let storyPoints = storyPoints { fields["storyPoints"] = storyPoints }
        if let frequencyDays = frequencyDays { fields["frequencyDays"] = frequencyDays }

        let change = try createChangeLogEntry(
            action: .update,
            taskId: taskId.uuidString,
            data: fields
        )

        try storage.saveChanges(userId: userId, newChanges: [change])
        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskUpdated()
    }

    public func completeTask(_ task: RedoTask) async throws {
        guard let todo = task.currentPendingTask else { return }

        let change = try createChangeLogEntry(
            action: .completeTodo,
            taskId: task.guid.uuidString,
            data: [
                "todoTaskId": todo.guid.uuidString,
                "completed": ISO8601DateFormatter().string(from: Date()),
                "notes": ""
            ]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])
        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskCompleted()
    }

    public func archiveTask(_ task: RedoTask) async throws {
        let change = try createChangeLogEntry(
            action: task.archived ? .unarchive : .archive,
            taskId: task.guid.uuidString,
            data: [:]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])
        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskArchived()
    }

    public func deleteTask(_ task: RedoTask) async throws {
        let change = try createChangeLogEntry(
            action: .delete,
            taskId: task.guid.uuidString,
            data: [:]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])
        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskDeleted()
    }

    public func snoozeTask(_ task: RedoTask, days: Int, notes: String = "") async throws {
        guard let todo = task.currentPendingTask else { return }

        let change = try createChangeLogEntry(
            action: .snooze,
            taskId: task.guid.uuidString,
            data: [
                "todoTaskId": todo.guid.uuidString,
                "snoozeDays": days,
                "notes": notes.isEmpty ? "Snoozed for \(days) day(s)" : notes
            ]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])
        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskSnoozed()
    }

    public func createTodo(for task: RedoTask, deadline: Date, notes: String = "") async throws {
        let todoId = UUID()

        let change = try createChangeLogEntry(
            action: .createTodo,
            taskId: task.guid.uuidString,
            data: [
                "todoTaskId": todoId.uuidString,
                "deadline": ISO8601DateFormatter().string(from: deadline),
                "notes": notes
            ]
        )

        try storage.saveChanges(userId: userId, newChanges: [change])
        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskCreated()
    }

    // MARK: - Change Log Creation

    private func createChangeLogEntry(
        action: ChangeAction,
        taskId: String,
        data: [String: Any]
    ) throws -> ChangeLogEntry {
        // Increment Lamport clock
        lamportClock += 1

        // Get parent changes (last change for this task)
        let allChanges = try storage.getAllChanges(userId: userId)
        let lastChange = allChanges
            .filter { $0.taskId == taskId }
            .max(by: { $0.timestamp.lamport < $1.timestamp.lamport })

        let parents = lastChange != nil ? [lastChange!.id] : []

        // Create timestamp
        let timestamp = LogicalTimestamp(
            lamport: lamportClock,
            wall: ISO8601DateFormatter().string(from: Date())
        )

        // Create author info
        let publicKey = try keychain.loadPublicKey() ?? ""
        let author = AuthorInfo(
            userId: userId,
            deviceId: deviceId,
            name: nil,
            publicKey: publicKey
        )

        // Create change data
        let changeData = ChangeData(dictionary: data)

        // Create entry (without ID and signature first)
        var entry = ChangeLogEntry(
            id: "",  // Will be calculated
            version: 1,
            parents: parents,
            timestamp: timestamp,
            author: author,
            action: action,
            taskId: taskId,
            data: changeData,
            signature: nil
        )

        // Calculate content-addressed ID
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

        // Sign entry (optional for now)
        // TODO: Implement signing

        return entry
    }

    // MARK: - Firebase Sync

    private func initializeFirebaseSync() async {
        // Check if user is authenticated with Google OAuth
        guard let googleSubjectID = GoogleAuthManager.shared.getGoogleSubjectID() else {
            print("ℹ️ No Google authentication, running in offline mode")
            return
        }

        // Initialize Firebase sync service
        firebaseSync = FirebaseSyncService(userId: googleSubjectID, deviceId: deviceId)

        // Perform initial sync
        await syncChanges()

        // Start real-time listener
        firebaseSync?.startRealtimeSync { [weak self] remoteChanges in
            guard let self = self else { return }

            Task { @MainActor in
                do {
                    // Get current local changes
                    let localChanges = try self.storage.getAllChanges(userId: self.userId)
                    let localIds = Set(localChanges.map { $0.id })

                    // Find new changes from server
                    let newChanges = remoteChanges.filter { !localIds.contains($0.id) }

                    if !newChanges.isEmpty {
                        // Save new changes locally
                        try self.storage.saveChanges(userId: self.userId, newChanges: newChanges)

                        // Reconstruct state
                        try await self.reconstructState()

                        // Haptic feedback for sync
                        HapticManager.shared.selectionChanged()

                        print("✅ Synced \(newChanges.count) new changes from server")
                    }
                } catch {
                    print("❌ Error processing real-time sync: \(error)")
                }
            }
        }
    }

    private func syncChanges() async {
        guard let firebaseSync = firebaseSync else { return }

        syncStatus = .syncing

        do {
            let localChanges = try storage.getAllChanges(userId: userId)
            let response = try await firebaseSync.syncChanges(localChanges: localChanges)

            // Save missing changes locally
            if !response.missingChanges.isEmpty {
                try storage.saveChanges(userId: userId, newChanges: response.missingChanges)
                try await reconstructState()
            }

            syncStatus = .synced
        } catch {
            syncStatus = .failed(error: error.localizedDescription)
        }
    }

    /// Reinitialize sync after authentication
    public func reinitializeSync() async {
        await initializeFirebaseSync()
    }

    // MARK: - Batch Operations

    public func completeTasks(_ tasks: [RedoTask]) async throws {
        for task in tasks where task.hasPendingTodos {
            try await completeTask(task)
        }
    }

    public func archiveTasks(_ tasks: [RedoTask]) async throws {
        for task in tasks {
            let change = try createChangeLogEntry(
                action: .archive,
                taskId: task.guid.uuidString,
                data: [:]
            )
            try storage.saveChanges(userId: userId, newChanges: [change])
        }

        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.success()
    }

    public func deleteTasks(_ tasks: [RedoTask]) async throws {
        for task in tasks {
            let change = try createChangeLogEntry(
                action: .delete,
                taskId: task.guid.uuidString,
                data: [:]
            )
            try storage.saveChanges(userId: userId, newChanges: [change])
        }

        await syncChanges()
        try await reconstructState()

        // Haptic feedback
        HapticManager.shared.taskDeleted()
    }

    // MARK: - Filtering

    private func setupObservers() {
        // Update filtered tasks when any filter changes
        $tasks
            .combineLatest($showArchived, $searchText, $selectedPriority)
            .combineLatest($selectedPriorities, $showOnlyOverdue, $showOnlyActive)
            .combineLatest($searchScope, $sortOption, $dateFilter)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }

    private func applyFilters() {
        var filtered = tasks

        // Filter archived
        if !showArchived {
            filtered = filtered.filter { !$0.archived }
        }

        // Filter by search text with scope
        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                switch searchScope {
                case .both:
                    return task.title.localizedCaseInsensitiveContains(searchText) ||
                           task.description.localizedCaseInsensitiveContains(searchText)
                case .title:
                    return task.title.localizedCaseInsensitiveContains(searchText)
                case .description:
                    return task.description.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        // Filter by priority (old single selection - keep for backward compatibility)
        if let priority = selectedPriority {
            filtered = filtered.filter { $0.priority == priority }
        }

        // Filter by multiple priorities (new)
        if !selectedPriorities.isEmpty {
            filtered = filtered.filter { selectedPriorities.contains($0.priority) }
        }

        // Filter overdue only
        if showOnlyOverdue {
            filtered = filtered.filter { $0.isOverdue }
        }

        // Filter active only (has pending todos)
        if showOnlyActive {
            filtered = filtered.filter { $0.hasPendingTodos }
        }

        // Filter by date range
        if let dateFilter = dateFilter {
            filtered = filtered.filter { task in
                switch dateFilter.type {
                case .created:
                    if let start = dateFilter.startDate, task.created < start {
                        return false
                    }
                    if let end = dateFilter.endDate, task.created > end {
                        return false
                    }
                    return true
                case .dueDate:
                    guard let todo = task.currentPendingTask else { return false }
                    if let start = dateFilter.startDate, todo.deadline < start {
                        return false
                    }
                    if let end = dateFilter.endDate, todo.deadline > end {
                        return false
                    }
                    return true
                }
            }
        }

        // Apply sorting
        switch sortOption {
        case .rank:
            filtered.sort { $0.currentRank() > $1.currentRank() }
        case .priority:
            filtered.sort { $0.priority > $1.priority }
        case .dueDate:
            filtered.sort { task1, task2 in
                guard let todo1 = task1.currentPendingTask,
                      let todo2 = task2.currentPendingTask else {
                    return task1.currentPendingTask != nil
                }
                return todo1.deadline < todo2.deadline
            }
        case .createdDate:
            filtered.sort { $0.created > $1.created }
        case .title:
            filtered.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        }

        filteredTasks = filtered
    }

    // MARK: - Export/Import

    public func exportData() throws -> String {
        try storage.exportToJSON()
    }

    public func importData(_ jsonString: String) async throws {
        let count = try storage.importFromJSON(jsonString)
        try await reconstructState()
        errorMessage = "Imported \(count) changes successfully"
    }
}

// MARK: - Sync Status

public enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case failed(error: String)
}

// MARK: - Search & Filter Options

public enum SearchScope: String, CaseIterable, Identifiable {
    case both = "All"
    case title = "Title Only"
    case description = "Description Only"

    public var id: String { rawValue }
}

public enum SortOption: String, CaseIterable, Identifiable {
    case rank = "Rank (Smart)"
    case priority = "Priority"
    case dueDate = "Due Date"
    case createdDate = "Created Date"
    case title = "Title"

    public var id: String { rawValue }
}

public struct DateFilter: Equatable {
    public var type: DateFilterType
    public var startDate: Date?
    public var endDate: Date?

    public enum DateFilterType: String, CaseIterable {
        case created = "Created"
        case dueDate = "Due Date"
    }
}
