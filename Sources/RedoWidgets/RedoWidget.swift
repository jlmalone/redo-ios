import WidgetKit
import SwiftUI
import RedoCore

/// Main widget entry point
@main
struct RedoWidgets: WidgetBundle {
    var body: some Widget {
        TaskListWidget()
        QuickActionsWidget()
    }
}

// MARK: - Task List Widget

struct TaskListWidget: Widget {
    let kind: String = "TaskListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskListProvider()) { entry in
            TaskListWidgetView(entry: entry)
        }
        .configurationDisplayName("Task List")
        .description("View your top priority tasks at a glance")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled() // iOS 17+ for edge-to-edge content
    }
}

// MARK: - Quick Actions Widget

struct QuickActionsWidget: Widget {
    let kind: String = "QuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Stats")
        .description("See your task statistics and quick actions")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline Providers

struct TaskListProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskListEntry {
        TaskListEntry(date: Date(), tasks: sampleTasks(), totalCount: 12)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskListEntry) -> Void) {
        let entry = TaskListEntry(date: Date(), tasks: sampleTasks(), totalCount: 12)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskListEntry>) -> Void) {
        // Load actual tasks from storage
        let tasks = loadTopTasks(limit: 5)
        let totalCount = loadTotalTaskCount()

        let entry = TaskListEntry(
            date: Date(),
            tasks: tasks,
            totalCount: totalCount
        )

        // Update every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func loadTopTasks(limit: Int) -> [RedoTask] {
        do {
            let storage = ChangeLogStorage()
            let reconstructor = StateReconstructor()

            // Get user ID from keychain
            let keychain = KeychainService()
            guard let userId = try? keychain.loadUserId() else {
                return []
            }

            // Load and reconstruct tasks
            let changes = try storage.getAllChanges(userId: userId)
            let allTasks = try reconstructor.reconstructTasks(from: changes)

            // Filter and sort
            let activeTasks = allTasks
                .filter { !$0.archived && $0.hasPendingTodos }
                .sorted { $0.currentRank() > $1.currentRank() }

            return Array(activeTasks.prefix(limit))
        } catch {
            print("Widget error loading tasks: \(error)")
            return []
        }
    }

    private func loadTotalTaskCount() -> Int {
        do {
            let storage = ChangeLogStorage()
            let reconstructor = StateReconstructor()
            let keychain = KeychainService()

            guard let userId = try? keychain.loadUserId() else { return 0 }

            let changes = try storage.getAllChanges(userId: userId)
            let tasks = try reconstructor.reconstructTasks(from: changes)

            return tasks.filter { !$0.archived }.count
        } catch {
            return 0
        }
    }

    private func sampleTasks() -> [RedoTask] {
        let userId = "sample_user_id"
        return [
            RedoTask(
                userId: userId,
                title: "Complete project proposal",
                description: "Finish the Q1 proposal",
                priority: 5,
                frequencyDays: 0
            ),
            RedoTask(
                userId: userId,
                title: "Review pull requests",
                description: "Check team's code",
                priority: 4,
                frequencyDays: 7
            ),
            RedoTask(
                userId: userId,
                title: "Update documentation",
                description: "Add API docs",
                priority: 3,
                frequencyDays: 0
            )
        ]
    }
}

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStatsEntry {
        QuickStatsEntry(date: Date(), activeCount: 8, overdueCount: 2, completedToday: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStatsEntry) -> Void) {
        let entry = QuickStatsEntry(date: Date(), activeCount: 8, overdueCount: 2, completedToday: 5)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStatsEntry>) -> Void) {
        let stats = loadStats()

        let entry = QuickStatsEntry(
            date: Date(),
            activeCount: stats.active,
            overdueCount: stats.overdue,
            completedToday: stats.completedToday
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func loadStats() -> (active: Int, overdue: Int, completedToday: Int) {
        do {
            let storage = ChangeLogStorage()
            let reconstructor = StateReconstructor()
            let keychain = KeychainService()

            guard let userId = try? keychain.loadUserId() else {
                return (0, 0, 0)
            }

            let changes = try storage.getAllChanges(userId: userId)
            let tasks = try reconstructor.reconstructTasks(from: changes)

            let active = tasks.filter { !$0.archived && $0.hasPendingTodos }.count
            let overdue = tasks.filter { $0.isOverdue }.count

            // Count completions today
            let today = Calendar.current.startOfDay(for: Date())
            let completedToday = changes.filter { change in
                guard change.action == .completeTodo else { return false }
                let changeDate = Calendar.current.startOfDay(for: ISO8601DateFormatter().date(from: change.timestamp.wall) ?? Date())
                return changeDate == today
            }.count

            return (active, overdue, completedToday)
        } catch {
            return (0, 0, 0)
        }
    }
}

// MARK: - Timeline Entries

struct TaskListEntry: TimelineEntry {
    let date: Date
    let tasks: [RedoTask]
    let totalCount: Int
}

struct QuickStatsEntry: TimelineEntry {
    let date: Date
    let activeCount: Int
    let overdueCount: Int
    let completedToday: Int
}
