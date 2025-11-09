import SwiftUI
import WidgetKit
import RedoCore

/// Widget view showing top priority tasks
struct TaskListWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskListEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallTaskListWidget(entry: entry)
        case .systemMedium:
            MediumTaskListWidget(entry: entry)
        case .systemLarge:
            LargeTaskListWidget(entry: entry)
        default:
            SmallTaskListWidget(entry: entry)
        }
    }
}

// MARK: - Small Widget (Single Task)

struct SmallTaskListWidget: View {
    let entry: TaskListEntry

    var body: some View {
        ZStack {
            // Matrix background
            Color(hex: "020B09")

            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "00FFB8"))
                        .font(.system(size: 14, weight: .bold))

                    Text("REDO")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFB8"))

                    Spacer()

                    Text("\(entry.totalCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "80BFA3"))
                }

                Divider()
                    .background(Color(hex: "00FFB8").opacity(0.3))

                // Top task
                if let task = entry.tasks.first {
                    VStack(alignment: .leading, spacing: 4) {
                        // Priority indicator
                        HStack(spacing: 4) {
                            ForEach(0..<task.priority, id: \.self) { _ in
                                Circle()
                                    .fill(priorityColor(for: task.priority))
                                    .frame(width: 6, height: 6)
                            }
                        }

                        // Title
                        Text(task.title)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(hex: "B8FFE6"))
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)

                        Spacer()

                        // Overdue indicator
                        if task.isOverdue {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                Text("OVERDUE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(Color(hex: "FF4444"))
                        }
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("No active tasks")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(hex: "80BFA3"))
                        Spacer()
                    }
                }
            }
            .padding(12)
        }
    }

    private func priorityColor(for priority: Int) -> Color {
        switch priority {
        case 1: return Color(hex: "00FF88")      // Low - green
        case 2: return Color(hex: "00AAFF")      // Medium-low - blue
        case 3: return Color(hex: "FFC833")      // Medium - amber
        case 4: return Color(hex: "FF8800")      // High - orange
        case 5: return Color(hex: "FF4444")      // Urgent - red
        default: return Color(hex: "80BFA3")     // Default - dim
        }
    }
}

// MARK: - Medium Widget (3 Tasks)

struct MediumTaskListWidget: View {
    let entry: TaskListEntry

    var body: some View {
        ZStack {
            Color(hex: "020B09")

            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "00FFB8"))

                    Text("TOP TASKS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFB8"))

                    Spacer()

                    Text("\(entry.totalCount) total")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: "80BFA3"))
                }

                Divider()
                    .background(Color(hex: "00FFB8").opacity(0.3))

                // Task list
                if entry.tasks.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: "00FFB8").opacity(0.3))
                            Text("All caught up!")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(hex: "80BFA3"))
                        }
                        Spacer()
                    }
                    Spacer()
                } else {
                    ForEach(entry.tasks.prefix(3), id: \.guid) { task in
                        WidgetTaskRow(task: task)
                    }

                    if entry.tasks.count > 3 {
                        Text("+\(entry.tasks.count - 3) more")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "80BFA3"))
                            .padding(.top, 4)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Large Widget (5 Tasks + Stats)

struct LargeTaskListWidget: View {
    let entry: TaskListEntry

    var body: some View {
        ZStack {
            Color(hex: "020B09")

            VStack(alignment: .leading, spacing: 12) {
                // Header with stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "00FFB8"))

                        Text("REDO")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "00FFB8"))

                        Spacer()
                    }

                    HStack(spacing: 16) {
                        StatBadge(
                            icon: "circle.fill",
                            value: "\(entry.tasks.filter { !$0.archived }.count)",
                            label: "Active",
                            color: Color(hex: "00FFB8")
                        )

                        StatBadge(
                            icon: "exclamationmark.triangle.fill",
                            value: "\(entry.tasks.filter { $0.isOverdue }.count)",
                            label: "Overdue",
                            color: Color(hex: "FF4444")
                        )

                        StatBadge(
                            icon: "star.fill",
                            value: "\(entry.tasks.filter { $0.priority >= 4 }.count)",
                            label: "High Priority",
                            color: Color(hex: "FFC833")
                        )
                    }
                }

                Divider()
                    .background(Color(hex: "00FFB8").opacity(0.3))

                // Task list
                if entry.tasks.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 48))
                                .foregroundColor(Color(hex: "00FFB8").opacity(0.3))
                            Text("All tasks completed!")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "B8FFE6"))
                            Text("Great work! 🎉")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(hex: "80BFA3"))
                        }
                        Spacer()
                    }
                    Spacer()
                } else {
                    ForEach(entry.tasks.prefix(5), id: \.guid) { task in
                        WidgetTaskRow(task: task, showDescription: true)
                    }

                    if entry.tasks.count > 5 {
                        HStack {
                            Spacer()
                            Text("+\(entry.tasks.count - 5) more tasks")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(hex: "80BFA3"))
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

// MARK: - Widget Task Row

struct WidgetTaskRow: View {
    let task: RedoTask
    var showDescription: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Priority dots
            VStack(spacing: 2) {
                ForEach(0..<task.priority, id: \.self) { _ in
                    Circle()
                        .fill(priorityColor(for: task.priority))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 8)

            // Task info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "B8FFE6"))
                        .lineLimit(1)

                    if task.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(hex: "FF4444"))
                    }
                }

                if showDescription && !task.description.isEmpty {
                    Text(task.description)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "80BFA3"))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func priorityColor(for priority: Int) -> Color {
        switch priority {
        case 1: return Color(hex: "00FF88")
        case 2: return Color(hex: "00AAFF")
        case 3: return Color(hex: "FFC833")
        case 4: return Color(hex: "FF8800")
        case 5: return Color(hex: "FF4444")
        default: return Color(hex: "80BFA3")
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .foregroundColor(color)

            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex: "80BFA3"))
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
