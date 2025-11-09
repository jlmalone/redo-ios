import SwiftUI

// MARK: - Accessibility Identifiers

public enum AccessibilityID {
    // Task List
    public static let taskList = "taskList"
    public static let taskCard = "taskCard"
    public static let createTaskButton = "createTaskButton"
    public static let filterButton = "filterButton"
    public static let searchBar = "searchBar"
    public static let selectionModeButton = "selectionModeButton"

    // Task Detail
    public static let completeButton = "completeButton"
    public static let snoozeButton = "snoozeButton"
    public static let archiveButton = "archiveButton"
    public static let deleteButton = "deleteButton"
    public static let editButton = "editButton"

    // Batch Operations
    public static let batchCompleteButton = "batchCompleteButton"
    public static let batchArchiveButton = "batchArchiveButton"
    public static let batchDeleteButton = "batchDeleteButton"

    // Settings
    public static let signInButton = "signInButton"
    public static let signOutButton = "signOutButton"
    public static let exportButton = "exportButton"
    public static let importButton = "importButton"
    public static let clearDataButton = "clearDataButton"

    // Onboarding
    public static let onboardingNextButton = "onboardingNextButton"
    public static let onboardingSkipButton = "onboardingSkipButton"
    public static let onboardingGetStartedButton = "onboardingGetStartedButton"
}

// MARK: - Accessibility Labels

public struct AccessibilityLabels {
    // Task operations
    public static func taskCard(title: String, priority: Int, overdue: Bool) -> String {
        var label = "Task: \(title). Priority \(priority) out of 5."
        if overdue {
            label += " Overdue."
        }
        return label
    }

    public static func priorityButton(_ priority: Int, isSelected: Bool) -> String {
        let selection = isSelected ? "Selected. " : ""
        return "\(selection)Priority \(priority) out of 5"
    }

    public static func sortOption(_ option: String, isSelected: Bool) -> String {
        let selection = isSelected ? "Selected. " : ""
        return "\(selection)Sort by \(option)"
    }

    public static func syncStatus(_ status: String) -> String {
        return "Sync status: \(status)"
    }

    public static func todoTask(deadline: Date, completed: Bool) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let deadlineStr = dateFormatter.string(from: deadline)

        if completed {
            return "Completed task. Deadline was \(deadlineStr)."
        } else {
            return "Pending task. Deadline: \(deadlineStr)."
        }
    }

    // Batch operations
    public static func batchComplete(count: Int) -> String {
        return "Complete \(count) selected task\(count == 1 ? "" : "s")"
    }

    public static func batchArchive(count: Int) -> String {
        return "Archive \(count) selected task\(count == 1 ? "" : "s")"
    }

    public static func batchDelete(count: Int) -> String {
        return "Delete \(count) selected task\(count == 1 ? "" : "s")"
    }
}

// MARK: - Accessibility Hints

public struct AccessibilityHints {
    public static let createTask = "Double tap to create a new task"
    public static let completeTask = "Double tap to mark task as complete"
    public static let snoozeTask = "Double tap to snooze this task"
    public static let archiveTask = "Double tap to archive this task"
    public static let deleteTask = "Double tap to delete this task"
    public static let filterTasks = "Double tap to open filter options"
    public static let editTask = "Double tap to edit task details"
    public static let selectTask = "Double tap to select or deselect this task"
    public static let openTaskDetail = "Double tap to view task details"
    public static let signIn = "Double tap to sign in with Google"
    public static let exportData = "Double tap to export your data"
}

// MARK: - View Modifiers

public extension View {
    /// Add comprehensive accessibility support
    func accessibleLabel(_ label: String, hint: String? = nil, identifier: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityIdentifier(identifier ?? "")
    }

    /// Make element accessible as a button
    func accessibleButton(_ label: String, hint: String? = nil, identifier: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityIdentifier(identifier ?? "")
            .accessibilityAddTraits(.isButton)
    }

    /// Make element accessible as a header
    func accessibleHeader(_ label: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isHeader)
    }

    /// Group accessibility elements
    func accessibilityGroup(label: String? = nil, children: Bool = true) -> some View {
        Group {
            if children {
                self.accessibilityElement(children: .contain)
            } else {
                self.accessibilityElement(children: .ignore)
            }
        }
        .accessibilityLabel(label ?? "")
    }

    /// Add accessibility sorting priority
    func accessibilitySortPriority(_ priority: Double) -> some View {
        self.accessibilitySortPriority(priority)
    }
}

// MARK: - Dynamic Type Support

public extension Font {
    /// Get scaled font that respects user's Dynamic Type settings
    static func matrixScaled(_ style: Font.TextStyle, design: Font.Design = .monospaced) -> Font {
        .system(style, design: design)
    }
}

// MARK: - Reduce Motion Support

public struct ReduceMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let enabledAnimation: Animation
    let disabledAnimation: Animation

    public func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? disabledAnimation : enabledAnimation, value: UUID())
    }
}

public extension View {
    /// Apply animation that respects Reduce Motion preference
    func reduceMotionAnimation(enabled: Animation = .spring(), disabled: Animation = .linear(duration: 0.1)) -> some View {
        modifier(ReduceMotionModifier(enabledAnimation: enabled, disabledAnimation: disabled))
    }
}

// MARK: - High Contrast Support

public extension Color {
    /// Adjust color for high contrast mode
    func highContrastAdjusted(boost: Double = 0.2) -> Color {
        // In production, check @Environment(\.accessibilityDifferentiateWithoutColor)
        // and adjust colors accordingly
        return self
    }
}
