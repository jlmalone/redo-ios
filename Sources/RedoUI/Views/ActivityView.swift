import SwiftUI
import RedoCore

/// Activity feed showing recent changes
public struct ActivityView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var changes: [ChangeLogEntry] = []
    @State private var groupedChanges: [Date: [ChangeLogEntry]] = [:]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                if changes.isEmpty {
                    emptyState
                } else {
                    activityList
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadChanges()
            }
            .refreshable {
                loadChanges()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: .matrixSpacingLarge) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.matrixNeonDim)
                .neonGlow()

            Text("No Activity Yet")
                .font(.matrixTitle2)
                .foregroundColor(.matrixTextPrimary)

            Text("Your task changes will appear here")
                .font(.matrixBody)
                .foregroundColor(.matrixTextSecondary)
        }
    }

    // MARK: - Activity List

    private var activityList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .matrixSpacingLarge) {
                // Group by date
                ForEach(sortedDates, id: \.self) { date in
                    VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
                        // Date header
                        Text(formatDate(date))
                            .font(.matrixHeadline)
                            .foregroundColor(.matrixNeon)
                            .padding(.horizontal)

                        // Changes for this date
                        ForEach(groupedChanges[date] ?? [], id: \.id) { change in
                            ActivityCard(change: change, tasks: viewModel.tasks)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Helpers

    private var sortedDates: [Date] {
        groupedChanges.keys.sorted(by: >)
    }

    private func loadChanges() {
        do {
            let storage = ChangeLogStorage()
            let allChanges = try storage.getAllChanges(userId: viewModel.userId)

            // Sort by timestamp (most recent first)
            changes = allChanges.sorted { $0.timestamp.lamport > $1.timestamp.lamport }

            // Group by date
            var grouped: [Date: [ChangeLogEntry]] = [:]
            for change in changes {
                if let wallDate = change.timestamp.wallDate {
                    let calendar = Calendar.current
                    let dateKey = calendar.startOfDay(for: wallDate)
                    grouped[dateKey, default: []].append(change)
                }
            }
            groupedChanges = grouped
        } catch {
            print("Failed to load changes: \(error)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Activity Card

struct ActivityCard: View {
    let change: ChangeLogEntry
    let tasks: [RedoTask]

    var body: some View {
        HStack(alignment: .top, spacing: .matrixSpacingMedium) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .cornerRadius(8)

            // Content
            VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                // Action text
                Text(actionText)
                    .font(.matrixBodyBold)
                    .foregroundColor(.matrixTextPrimary)

                // Task title (if found)
                if let taskTitle = findTaskTitle() {
                    Text(taskTitle)
                        .font(.matrixCallout)
                        .foregroundColor(.matrixTextSecondary)
                }

                // Timestamp
                Text(timeAgo)
                    .font(.matrixCaption2)
                    .foregroundColor(.matrixTextTertiary)
            }

            Spacer()
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder(color: iconColor.opacity(0.3))
        .padding(.horizontal)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch change.action {
        case .create:
            return "plus.circle.fill"
        case .update:
            return "pencil.circle.fill"
        case .createTodo:
            return "checklist.unchecked"
        case .completeTodo:
            return "checkmark.circle.fill"
        case .snooze:
            return "moon.zzz.fill"
        case .archive:
            return "archivebox.fill"
        case .unarchive:
            return "tray.and.arrow.up.fill"
        case .delete:
            return "trash.fill"
        }
    }

    private var iconColor: Color {
        switch change.action {
        case .create:
            return .matrixSuccess
        case .update:
            return .matrixCyan
        case .createTodo:
            return .matrixAmber
        case .completeTodo:
            return .matrixSuccess
        case .snooze:
            return .matrixPurple
        case .archive:
            return .matrixTextSecondary
        case .unarchive:
            return .matrixNeon
        case .delete:
            return .matrixError
        }
    }

    private var actionText: String {
        switch change.action {
        case .create:
            return "Created task"
        case .update:
            return "Updated task"
        case .createTodo:
            return "Added TODO"
        case .completeTodo:
            return "Completed TODO"
        case .snooze:
            return "Snoozed task"
        case .archive:
            return "Archived task"
        case .unarchive:
            return "Unarchived task"
        case .delete:
            return "Deleted task"
        }
    }

    private var timeAgo: String {
        guard let wallDate = change.timestamp.wallDate else {
            return "Unknown time"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: wallDate, relativeTo: Date())
    }

    private func findTaskTitle() -> String? {
        guard let taskId = change.taskId else { return nil }

        // Try to find task in current tasks
        if let task = tasks.first(where: { $0.guid.uuidString == taskId }) {
            return task.title
        }

        // Otherwise, try to get title from change data
        if change.action == .create {
            return change.data.fields["title"]?.stringValue
        }

        return nil
    }
}

// MARK: - Preview

#if DEBUG
struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityView(viewModel: AppViewModel())
    }
}
#endif
