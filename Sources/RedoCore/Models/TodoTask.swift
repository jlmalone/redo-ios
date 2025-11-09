import Foundation

/// Individual work instance created from a RedoTask template
public struct TodoTask: Identifiable, Codable, Equatable {
    // MARK: - Core Properties

    public let guid: UUID
    public let redoParentGuid: UUID
    public let created: Date
    public var notes: String
    public var deadline: Date
    public var completed: Date?

    // MARK: - Computed Properties

    public var id: UUID { guid }

    public var isPending: Bool {
        completed == nil
    }

    public var isCompleted: Bool {
        completed != nil
    }

    public var isOverdue: Bool {
        guard isPending else { return false }
        return deadline < Date()
    }

    public var daysUntilDeadline: Int {
        let interval = deadline.timeIntervalSince(Date())
        return Int(interval / 86400.0)
    }

    public var daysSinceCreation: Double {
        Date().timeIntervalSince(created) / 86400.0
    }

    // MARK: - Initialization

    public init(
        guid: UUID = UUID(),
        redoParentGuid: UUID,
        created: Date = Date(),
        notes: String = "",
        deadline: Date,
        completed: Date? = nil
    ) {
        self.guid = guid
        self.redoParentGuid = redoParentGuid
        self.created = created
        self.notes = notes
        self.deadline = deadline
        self.completed = completed
    }

    // MARK: - Business Logic

    /// Calculate rank (urgency score) using exponential sigmoid
    public func rank(at date: Date = Date()) -> Double {
        let daysSince = date.timeIntervalSince(created) / 86400.0
        let k = log(9.0) / 30.0
        return 1.0 / (1.0 + exp(-k * (daysSince - 30.0)))
    }

    /// Get deadline status display string
    public var deadlineDisplay: String {
        let days = daysUntilDeadline

        if isOverdue {
            return "\(abs(days)) day\(abs(days) == 1 ? "" : "s") overdue"
        } else if days == 0 {
            return "Due today"
        } else if days == 1 {
            return "Due tomorrow"
        } else if days < 7 {
            return "Due in \(days) days"
        } else {
            let weeks = days / 7
            return "Due in \(weeks) week\(weeks == 1 ? "" : "s")"
        }
    }
}
