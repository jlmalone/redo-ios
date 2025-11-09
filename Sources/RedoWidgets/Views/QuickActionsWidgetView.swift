import SwiftUI
import WidgetKit

/// Quick stats widget showing task counts
struct QuickActionsWidgetView: View {
    let entry: QuickStatsEntry

    var body: some View {
        ZStack {
            // Matrix background with gradient
            LinearGradient(
                colors: [
                    Color(hex: "020B09"),
                    Color(hex: "0A1815")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(Color(hex: "00FFB8"))
                        .font(.system(size: 12, weight: .bold))

                    Text("STATS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFB8"))

                    Spacer()
                }

                // Stats grid
                VStack(spacing: 8) {
                    // Active tasks
                    StatRow(
                        icon: "circle.fill",
                        label: "Active",
                        value: "\(entry.activeCount)",
                        color: Color(hex: "00FFB8")
                    )

                    // Overdue tasks
                    if entry.overdueCount > 0 {
                        StatRow(
                            icon: "exclamationmark.triangle.fill",
                            label: "Overdue",
                            value: "\(entry.overdueCount)",
                            color: Color(hex: "FF4444")
                        )
                    }

                    // Completed today
                    StatRow(
                        icon: "checkmark.circle.fill",
                        label: "Done Today",
                        value: "\(entry.completedToday)",
                        color: Color(hex: "00FF88")
                    )
                }

                Spacer()

                // Motivational message
                if entry.completedToday > 0 {
                    Text("Great progress!")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "80BFA3"))
                } else if entry.overdueCount > 0 {
                    Text("Time to catch up")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "FF4444"))
                } else {
                    Text("Stay focused")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "80BFA3"))
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "B8FFE6"))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
