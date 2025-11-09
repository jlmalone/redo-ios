import Foundation
import Intents

// MARK: - Create Task Intent

@available(iOS 16.0, *)
@objc(CreateTaskIntent)
class CreateTaskIntent: INIntent {
    @NSManaged var title: String?
    @NSManaged var taskDescription: String?
    @NSManaged var priority: NSNumber?
}

@available(iOS 16.0, *)
@objc protocol CreateTaskIntentHandling {
    func handle(intent: CreateTaskIntent) async -> CreateTaskIntentResponse
    @objc optional func resolveTitle(for intent: CreateTaskIntent) async -> INStringResolutionResult
    @objc optional func resolvePriority(for intent: CreateTaskIntent) async -> PriorityResolutionResult
}

@available(iOS 16.0, *)
@objc(CreateTaskIntentResponse)
class CreateTaskIntentResponse: INIntentResponse {
    @NSManaged var code: CreateTaskIntentResponseCode
    @NSManaged var taskTitle: String?

    convenience init(code: CreateTaskIntentResponseCode, userActivity: NSUserActivity?) {
        self.init()
        self.code = code
        self.userActivity = userActivity
    }
}

@available(iOS 16.0, *)
@objc enum CreateTaskIntentResponseCode: Int {
    case unspecified = 0
    case ready
    case continueInApp
    case inProgress
    case success
    case failure
    case failureRequiringAppLaunch
}

// MARK: - Complete Task Intent

@available(iOS 16.0, *)
@objc(CompleteTaskIntent)
class CompleteTaskIntent: INIntent {
    @NSManaged var taskTitle: String?
}

@available(iOS 16.0, *)
@objc protocol CompleteTaskIntentHandling {
    func handle(intent: CompleteTaskIntent) async -> CompleteTaskIntentResponse
    @objc optional func provideTaskTitleOptionsCollection(for intent: CompleteTaskIntent) async throws -> INObjectCollection<NSString>
}

@available(iOS 16.0, *)
@objc(CompleteTaskIntentResponse)
class CompleteTaskIntentResponse: INIntentResponse {
    @NSManaged var code: CompleteTaskIntentResponseCode
    @NSManaged var completedTaskTitle: String?

    convenience init(code: CompleteTaskIntentResponseCode, userActivity: NSUserActivity?) {
        self.init()
        self.code = code
        self.userActivity = userActivity
    }
}

@available(iOS 16.0, *)
@objc enum CompleteTaskIntentResponseCode: Int {
    case unspecified = 0
    case ready
    case continueInApp
    case inProgress
    case success
    case failure
    case failureRequiringAppLaunch
}

// MARK: - View Tasks Intent

@available(iOS 16.0, *)
@objc(ViewTasksIntent)
class ViewTasksIntent: INIntent {
    @NSManaged var filter: TaskFilter
}

@available(iOS 16.0, *)
@objc protocol ViewTasksIntentHandling {
    func handle(intent: ViewTasksIntent) async -> ViewTasksIntentResponse
}

@available(iOS 16.0, *)
@objc(ViewTasksIntentResponse)
class ViewTasksIntentResponse: INIntentResponse {
    @NSManaged var code: ViewTasksIntentResponseCode
    @NSManaged var taskCount: NSNumber?
    @NSManaged var taskList: String?

    convenience init(code: ViewTasksIntentResponseCode, userActivity: NSUserActivity?) {
        self.init()
        self.code = code
        self.userActivity = userActivity
    }
}

@available(iOS 16.0, *)
@objc enum ViewTasksIntentResponseCode: Int {
    case unspecified = 0
    case ready
    case continueInApp
    case inProgress
    case success
    case failure
}

// MARK: - Supporting Types

@available(iOS 16.0, *)
@objc enum TaskPriority: Int {
    case unknown = 0
    case low = 1
    case mediumLow = 2
    case medium = 3
    case high = 4
    case urgent = 5

    var displayString: String {
        switch self {
        case .unknown: return "Unknown"
        case .low: return "Low"
        case .mediumLow: return "Medium-Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
}

@available(iOS 16.0, *)
class PriorityResolutionResult: INIntentResolutionResult {
    static func success(with resolvedValue: TaskPriority) -> PriorityResolutionResult {
        let result = PriorityResolutionResult()
        return result
    }

    static func confirmationRequired(with valueToConfirm: TaskPriority) -> PriorityResolutionResult {
        let result = PriorityResolutionResult()
        return result
    }

    static func needsValue() -> Self {
        return PriorityResolutionResult()
    }
}

@available(iOS 16.0, *)
@objc enum TaskFilter: Int {
    case unknown = 0
    case all
    case active
    case overdue
    case highPriority

    var displayString: String {
        switch self {
        case .unknown: return "Unknown"
        case .all: return "All Tasks"
        case .active: return "Active Tasks"
        case .overdue: return "Overdue Tasks"
        case .highPriority: return "High Priority"
        }
    }
}

// MARK: - Intent Extensions
// Note: Suggested invocation phrases are defined in Intents.intentdefinition file
// rather than in code for legacy Intents framework
