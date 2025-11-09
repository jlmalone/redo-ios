import Foundation

/// Recurring task template that generates TodoTask instances
public struct RedoTask: Identifiable, Codable, Equatable {
    // MARK: - Core Properties

    public let guid: UUID
    public let userId: String              // First 32 chars of Ed25519 public key
    public var title: String
    public var description: String
    public var privacy: Bool               // true = private, false = public
    public var storyPoints: Float
    public var priority: Int               // 1-5 (1=Low, 3=Medium, 5=High)
    public var frequencyDays: Int          // 0 = one-time, 7 = weekly, etc.
    public let created: Date
    public var archived: Bool
    public var lastUpdated: Date?
    public var todoTasks: [TodoTask]

    // MARK: - Computed Properties

    public var id: UUID { guid }

    public var isRecurring: Bool {
        frequencyDays > 0
    }

    public var currentPendingTask: TodoTask? {
        todoTasks.first { $0.completed == nil }
    }

    public var currentActiveTodo: TodoTask? {
        currentPendingTask
    }

    public var hasPendingTodos: Bool {
        currentPendingTask != nil
    }

    public var isOverdue: Bool {
        guard let todo = currentPendingTask else { return false }
        return todo.isOverdue
    }

    // MARK: - Initialization

    public init(
        guid: UUID = UUID(),
        userId: String,
        title: String,
        description: String = "",
        privacy: Bool = false,
        storyPoints: Float = 1.0,
        priority: Int = 3,
        frequencyDays: Int = 7,
        created: Date = Date(),
        archived: Bool = false,
        lastUpdated: Date? = nil,
        todoTasks: [TodoTask] = []
    ) {
        self.guid = guid
        self.userId = userId
        self.title = title
        self.description = description
        self.privacy = privacy
        self.storyPoints = storyPoints
        self.priority = priority
        self.frequencyDays = frequencyDays
        self.created = created
        self.archived = archived
        self.lastUpdated = lastUpdated
        self.todoTasks = todoTasks
    }

    // MARK: - Business Logic

    /// Calculate current rank using enhanced algorithm
    public func currentRank(at date: Date = Date()) -> Double {
        guard let todo = currentPendingTask else { return 0 }

        let urgency = calculateUrgency(for: todo, at: date)
        let complexity = sqrt(Double(storyPoints))
        let priorityWeight = Double(priority)
        let circadianBonus = isInMorningHours(date) ? 1.15 : 1.0

        return priorityWeight * urgency * complexity * circadianBonus
    }

    /// Calculate urgency using exponential sigmoid function
    private func calculateUrgency(for todo: TodoTask, at date: Date) -> Double {
        let daysSinceCreation = date.timeIntervalSince(todo.created) / 86400.0
        let k = log(9.0) / 30.0  // 10% → 90% urgency over 30 days
        return 1.0 / (1.0 + exp(-k * (daysSinceCreation - 30.0)))
    }

    /// Check if current time is in morning hours (6am-11am) for circadian bonus
    private func isInMorningHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 6 && hour < 11
    }

    /// Get human-readable urgency status
    public func urgencyStatus(at date: Date = Date()) -> UrgencyStatus {
        guard let todo = currentPendingTask else { return .none }

        let urgency = calculateUrgency(for: todo, at: date)

        switch urgency {
        case 0..<0.3:
            return .low
        case 0.3..<0.6:
            return .medium
        case 0.6..<0.9:
            return .high
        default:
            return .critical
        }
    }

    /// Priority display string
    public var priorityDisplay: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Medium-Low"
        case 3: return "Medium"
        case 4: return "Medium-High"
        case 5: return "High"
        default: return "Medium"
        }
    }
}

// MARK: - Supporting Types

public enum UrgencyStatus: String, Codable {
    case none = "None"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
}
