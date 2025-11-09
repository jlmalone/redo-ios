import SwiftUI
import RedoCore

/// Task card with Matrix theme styling
public struct MatrixTaskCard: View {
    let task: RedoTask
    let onTap: () -> Void
    let onComplete: () -> Void

    @State private var isPressed = false

    public init(task: RedoTask, onTap: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.task = task
        self.onTap = onTap
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            // Header: Title + Complete Button
            HStack(alignment: .top) {
                // Title with neon glow
                Text(task.title)
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixNeon)
                    .neonGlow(color: .matrixNeon, radius: 6)

                Spacer()

                // Complete button (if has pending todo)
                if task.hasPendingTodos {
                    Button(action: onComplete) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.matrixSuccess)
                    }
                }
            }

            // Description (if not empty)
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.matrixCallout)
                    .foregroundColor(.matrixTextSecondary)
                    .lineLimit(2)
            }

            // Metadata row
            HStack(spacing: .matrixSpacingMedium) {
                // Priority badge
                PriorityBadge(priority: task.priority)

                // Story points
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                    Text("\(Int(task.storyPoints)) pts")
                        .font(.matrixCaption)
                }
                .foregroundColor(.matrixTextSecondary)

                // Frequency
                if task.frequencyDays > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.caption)
                        Text(frequencyText)
                            .font(.matrixCaption)
                    }
                    .foregroundColor(.matrixTextSecondary)
                }

                Spacer()

                // Deadline/overdue status
                if let todo = task.currentPendingTask {
                    DeadlineBadge(date: todo.deadline, isOverdue: todo.isOverdue)
                }
            }

            // Urgency status indicator
            if task.hasPendingTodos {
                UrgencyIndicator(status: task.urgencyStatus().rawValue)
            }
        }
        .padding(.matrixSpacingLarge)
        .background(
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [.matrixBackgroundSecondary, .matrixBackgroundTertiary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle grid pattern overlay (optional)
                if isPressed {
                    Color.matrixNeonFaint
                }
            }
        )
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder(color: isOverdue ? .matrixError : .matrixNeonFaint)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    isPressed = false
                }
                onTap()
            }
        }
    }

    // MARK: - Helpers

    private var isOverdue: Bool {
        task.isOverdue
    }

    private var frequencyText: String {
        switch task.frequencyDays {
        case 1: return "Daily"
        case 7: return "Weekly"
        case 14: return "Bi-weekly"
        case 30: return "Monthly"
        default: return "\(task.frequencyDays)d"
        }
    }
}

// MARK: - Supporting Components

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
            Text(priorityText)
                .font(.matrixCaption)
        }
        .foregroundColor(Color.priorityColor(for: priority))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.priorityColor(for: priority).opacity(0.15))
        .cornerRadius(6)
    }

    private var priorityText: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Med-Low"
        case 3: return "Medium"
        case 4: return "Med-High"
        case 5: return "High"
        default: return "Medium"
        }
    }
}

struct DeadlineBadge: View {
    let date: Date
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                .font(.caption)
            Text(deadlineText)
                .font(.matrixCaption)
        }
        .foregroundColor(isOverdue ? .matrixError : .matrixTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isOverdue ? Color.matrixError : Color.matrixTextSecondary).opacity(0.15))
        .cornerRadius(6)
    }

    private var deadlineText: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0

        if isOverdue {
            return "\(abs(days))d overdue"
        } else if days == 0 {
            return "Today"
        } else if days == 1 {
            return "Tomorrow"
        } else if days < 7 {
            return "\(days)d"
        } else {
            let weeks = days / 7
            return "\(weeks)w"
        }
    }
}

struct UrgencyIndicator: View {
    let status: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.urgencyColor(for: status))
                .frame(width: 8, height: 8)
                .neonGlow(color: Color.urgencyColor(for: status), radius: 4)

            Text("Urgency: \(status)")
                .font(.matrixCaption2)
                .foregroundColor(.matrixTextTertiary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MatrixTaskCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            MatrixTaskCard(
                task: RedoTask(
                    userId: "abc123",
                    title: "Complete weekly review",
                    description: "Review tasks, plan next week, update goals",
                    privacy: false,
                    storyPoints: 3,
                    priority: 5,
                    frequencyDays: 7,
                    created: Date(),
                    archived: false,
                    lastUpdated: nil,
                    todoTasks: [
                        TodoTask(
                            redoParentGuid: UUID(),
                            created: Date(),
                            deadline: Date().addingTimeInterval(-86400),
                            completed: nil
                        )
                    ]
                ),
                onTap: {},
                onComplete: {}
            )

            MatrixTaskCard(
                task: RedoTask(
                    userId: "abc123",
                    title: "Buy milk",
                    description: "",
                    privacy: false,
                    storyPoints: 1,
                    priority: 2,
                    frequencyDays: 0,
                    created: Date(),
                    archived: false,
                    lastUpdated: nil,
                    todoTasks: []
                ),
                onTap: {},
                onComplete: {}
            )
        }
        .padding()
        .background(Color.matrixBackground)
        .previewLayout(.sizeThatFits)
    }
}
#endif
