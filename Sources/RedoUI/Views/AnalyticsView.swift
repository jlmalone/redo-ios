import SwiftUI
import RedoCore

/// Analytics dashboard showing productivity insights
public struct AnalyticsView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .matrixSpacingLarge) {
                        // Summary Stats
                        summarySection

                        // Streak Card
                        streakCard

                        // Productivity Trend
                        productivityTrendSection

                        // Time of Day Insights
                        timeOfDaySection

                        // Weekly Report
                        weeklyReportSection

                        // Priority Distribution
                        priorityDistributionSection

                        // Task Velocity
                        taskVelocitySection

                        // Story Points
                        storyPointsSection

                        // Completion Prediction
                        completionPredictionSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            Text("Overview")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: .matrixSpacingMedium) {
                StatCard(
                    title: "Total Tasks",
                    value: "\(analytics.totalTasks)",
                    color: .matrixNeon,
                    icon: "checkmark.circle"
                )

                StatCard(
                    title: "Active",
                    value: "\(analytics.activeTasks)",
                    color: .matrixCyan,
                    icon: "circle"
                )

                StatCard(
                    title: "Completed",
                    value: "\(analytics.completedTasks)",
                    color: .matrixSuccess,
                    icon: "checkmark.circle.fill"
                )

                StatCard(
                    title: "Overdue",
                    value: "\(analytics.overdueTasks)",
                    color: .matrixError,
                    icon: "exclamationmark.triangle"
                )
            }
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        VStack(spacing: .matrixSpacingMedium) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.matrixAmber)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(analytics.currentStreak) Day Streak")
                        .font(.matrixTitle2)
                        .foregroundColor(.matrixNeon)

                    Text("Keep the momentum going!")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextSecondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder(color: analytics.currentStreak > 0 ? .matrixAmber : .matrixNeonFaint)

            // Best Streak
            HStack {
                Text("Best Streak")
                    .font(.matrixCallout)
                    .foregroundColor(.matrixTextSecondary)

                Spacer()

                Text("\(analytics.bestStreak) days")
                    .font(.matrixBodyBold)
                    .foregroundColor(.matrixAmber)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Priority Distribution

    private var priorityDistributionSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Priority Distribution")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            VStack(spacing: .matrixSpacingSmall) {
                ForEach(1...5, id: \.self) { priority in
                    PriorityBar(
                        priority: priority,
                        count: analytics.tasksByPriority[priority] ?? 0,
                        total: analytics.totalActiveTasks
                    )
                }
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }

    // MARK: - Task Velocity

    private var taskVelocitySection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Task Velocity")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            VStack(spacing: .matrixSpacingMedium) {
                VelocityRow(
                    period: "This Week",
                    completed: analytics.completedThisWeek,
                    icon: "calendar"
                )

                VelocityRow(
                    period: "This Month",
                    completed: analytics.completedThisMonth,
                    icon: "calendar.badge.clock"
                )

                VelocityRow(
                    period: "All Time",
                    completed: analytics.completedAllTime,
                    icon: "infinity"
                )
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }

    // MARK: - Story Points

    private var storyPointsSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Story Points")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            VStack(spacing: .matrixSpacingMedium) {
                // Total Points
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundColor(.matrixNeon)

                    Text("Total Points")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)

                    Spacer()

                    Text(String(format: "%.0f", analytics.totalStoryPoints))
                        .font(.matrixTitle3)
                        .foregroundColor(.matrixNeon)
                }

                Divider()
                    .background(Color.matrixNeonFaint)

                // Completed vs Pending
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Completed")
                            .font(.matrixCallout)
                            .foregroundColor(.matrixSuccess)

                        Text(String(format: "%.0f pts", analytics.completedStoryPoints))
                            .font(.matrixTitle3)
                            .foregroundColor(.matrixSuccess)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Pending")
                            .font(.matrixCallout)
                            .foregroundColor(.matrixTextSecondary)

                        Text(String(format: "%.0f pts", analytics.pendingStoryPoints))
                            .font(.matrixTitle3)
                            .foregroundColor(.matrixTextSecondary)
                    }
                }

                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.matrixBackgroundSecondary)
                            .frame(height: 8)

                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.matrixSuccess)
                            .frame(
                                width: geometry.size.width * CGFloat(analytics.storyPointsCompletionRate),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                // Completion Rate
                Text("\(Int(analytics.storyPointsCompletionRate * 100))% Complete")
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }

    // MARK: - Productivity Trend

    private var productivityTrendSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("7-Day Trend")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            let trends = AdvancedAnalyticsCalculator.calculateProductivityTrends(from: viewModel.tasks, days: 7)

            VStack(spacing: .matrixSpacingSmall) {
                // Chart
                ProductivityChart(trends: trends)
                    .frame(height: 120)

                // Legend
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.matrixSuccess)
                            .frame(width: 8, height: 8)
                        Text("Tasks Completed")
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextSecondary)
                    }

                    Spacer()

                    if let avgTasks = trends.isEmpty ? nil : trends.map({ $0.completedTasks }).reduce(0, +) / trends.count {
                        Text("Avg: \(avgTasks) tasks/day")
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextSecondary)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }

    // MARK: - Time of Day Section

    private var timeOfDaySection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Peak Performance")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            let insights = AdvancedAnalyticsCalculator.calculateTimeOfDayInsights(from: viewModel.tasks)

            VStack(spacing: .matrixSpacingSmall) {
                TimeOfDayBar(label: "Morning (6am-12pm)", count: insights.morningCompletions, total: insights.morningCompletions + insights.afternoonCompletions + insights.eveningCompletions + insights.nightCompletions, icon: "sunrise.fill", color: .yellow)
                TimeOfDayBar(label: "Afternoon (12pm-6pm)", count: insights.afternoonCompletions, total: insights.morningCompletions + insights.afternoonCompletions + insights.eveningCompletions + insights.nightCompletions, icon: "sun.max.fill", color: .orange)
                TimeOfDayBar(label: "Evening (6pm-12am)", count: insights.eveningCompletions, total: insights.morningCompletions + insights.afternoonCompletions + insights.eveningCompletions + insights.nightCompletions, icon: "sunset.fill", color: .purple)
                TimeOfDayBar(label: "Night (12am-6am)", count: insights.nightCompletions, total: insights.morningCompletions + insights.afternoonCompletions + insights.eveningCompletions + insights.nightCompletions, icon: "moon.stars.fill", color: .blue)
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }

    // MARK: - Weekly Report

    private var weeklyReportSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("This Week")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let report = AdvancedAnalyticsCalculator.calculateWeeklyReport(from: viewModel.tasks, for: weekStart)

            VStack(spacing: .matrixSpacingMedium) {
                // Completed vs Created
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Completed")
                            .font(.matrixCallout)
                            .foregroundColor(.matrixSuccess)
                        Text("\(report.tasksCompleted)")
                            .font(.matrixTitle2)
                            .foregroundColor(.matrixSuccess)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Created")
                            .font(.matrixCallout)
                            .foregroundColor(.matrixCyan)
                        Text("\(report.tasksCreated)")
                            .font(.matrixTitle2)
                            .foregroundColor(.matrixCyan)
                    }
                }

                Divider().background(Color.matrixNeonFaint)

                // Story Points
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundColor(.matrixAmber)
                    Text("Story Points")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)

                    Spacer()

                    Text(String(format: "%.0f pts", report.storyPointsCompleted))
                        .font(.matrixTitle3)
                        .foregroundColor(.matrixAmber)
                }

                // Streak Days
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.matrixAmber)
                    Text("Active Days")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)

                    Spacer()

                    Text("\(report.streakDays) / 7")
                        .font(.matrixTitle3)
                        .foregroundColor(.matrixNeon)
                }
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }

    // MARK: - Completion Prediction

    private var completionPredictionSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Completion Forecast")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            // Use end of current month as target
            let calendar = Calendar.current
            let monthEnd = calendar.dateInterval(of: .month, for: Date())?.end ?? Date()
            let prediction = AdvancedAnalyticsCalculator.predictCompletion(for: viewModel.tasks, targetDate: monthEnd)

            VStack(spacing: .matrixSpacingMedium) {
                // Remaining tasks
                HStack {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.matrixCyan)
                    Text("Tasks Remaining")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)

                    Spacer()

                    Text("\(prediction.tasksRemaining)")
                        .font(.matrixTitle2)
                        .foregroundColor(.matrixCyan)
                }

                // Daily velocity
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(.matrixNeon)
                    Text("Daily Velocity")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)

                    Spacer()

                    Text(String(format: "%.1f tasks/day", prediction.averageDailyVelocity))
                        .font(.matrixBodyBold)
                        .foregroundColor(.matrixNeon)
                }

                Divider().background(Color.matrixNeonFaint)

                // Prediction
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: prediction.isOnTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(prediction.isOnTrack ? .matrixSuccess : .matrixWarning)

                        Text(prediction.isOnTrack ? "On Track" : "Behind Schedule")
                            .font(.matrixBodyBold)
                            .foregroundColor(prediction.isOnTrack ? .matrixSuccess : .matrixWarning)

                        Spacer()

                        Text("\(abs(prediction.daysAhead)) days \(prediction.isOnTrack ? "ahead" : "behind")")
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextSecondary)
                    }

                    Text("Estimated completion: \(formatDate(prediction.estimatedCompletionDate))")
                        .font(.matrixCaption)
                        .foregroundColor(.matrixTextSecondary)

                    Text("Confidence: \(Int(prediction.confidence * 100))%")
                        .font(.matrixCaption2)
                        .foregroundColor(.matrixTextTertiary)
                }
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder(color: prediction.isOnTrack ? .matrixSuccess.opacity(0.3) : .matrixWarning.opacity(0.3))
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Analytics Computed Property

    private var analytics: AnalyticsData {
        AnalyticsData.calculate(from: viewModel.tasks)
    }
}

// MARK: - Analytics Data

struct AnalyticsData {
    let totalTasks: Int
    let activeTasks: Int
    let completedTasks: Int
    let overdueTasks: Int
    let currentStreak: Int
    let bestStreak: Int
    let tasksByPriority: [Int: Int]
    let totalActiveTasks: Int
    let completedThisWeek: Int
    let completedThisMonth: Int
    let completedAllTime: Int
    let totalStoryPoints: Float
    let completedStoryPoints: Float
    let pendingStoryPoints: Float
    let storyPointsCompletionRate: Double

    static func calculate(from tasks: [RedoTask]) -> AnalyticsData {
        let calendar = Calendar.current
        let now = Date()

        // Basic counts
        let total = tasks.count
        let active = tasks.filter { !$0.archived }.count
        let overdue = tasks.filter { task in
            guard let todo = task.currentPendingTask else { return false }
            return todo.isOverdue
        }.count

        // Completed tasks
        let completedTodos = tasks.flatMap { $0.todoTasks }.filter { $0.isCompleted }
        let completedCount = completedTodos.count

        // Streaks
        let streaks = calculateStreaks(from: completedTodos)

        // Priority distribution (active tasks only)
        let activeTasks = tasks.filter { !$0.archived }
        var priorityMap: [Int: Int] = [:]
        for task in activeTasks {
            priorityMap[task.priority, default: 0] += 1
        }

        // Task velocity
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!

        let thisWeek = completedTodos.filter { $0.completed ?? .distantPast >= weekAgo }.count
        let thisMonth = completedTodos.filter { $0.completed ?? .distantPast >= monthAgo }.count
        let allTime = completedCount

        // Story points
        let totalPoints = tasks.reduce(Float(0)) { $0 + $1.storyPoints }
        let completedPoints = tasks.filter { !$0.hasPendingTodos }.reduce(Float(0)) { $0 + $1.storyPoints }
        let pendingPoints = tasks.filter { $0.hasPendingTodos }.reduce(Float(0)) { $0 + $1.storyPoints }
        let completionRate = totalPoints > 0 ? Double(completedPoints / totalPoints) : 0.0

        return AnalyticsData(
            totalTasks: total,
            activeTasks: active,
            completedTasks: completedCount,
            overdueTasks: overdue,
            currentStreak: streaks.current,
            bestStreak: streaks.best,
            tasksByPriority: priorityMap,
            totalActiveTasks: active,
            completedThisWeek: thisWeek,
            completedThisMonth: thisMonth,
            completedAllTime: allTime,
            totalStoryPoints: totalPoints,
            completedStoryPoints: completedPoints,
            pendingStoryPoints: pendingPoints,
            storyPointsCompletionRate: completionRate
        )
    }

    private static func calculateStreaks(from todos: [TodoTask]) -> (current: Int, best: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group completions by date
        var completionDates = Set<Date>()
        for todo in todos {
            if let completed = todo.completed {
                let day = calendar.startOfDay(for: completed)
                completionDates.insert(day)
            }
        }

        // Calculate current streak
        var currentStreak = 0
        var checkDate = today
        while completionDates.contains(checkDate) {
            currentStreak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        // Calculate best streak
        let sortedDates = completionDates.sorted()
        var bestStreak = 0
        var tempStreak = 0
        var previousDate: Date?

        for date in sortedDates {
            if let prev = previousDate {
                let daysBetween = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if daysBetween == 1 {
                    tempStreak += 1
                } else {
                    bestStreak = max(bestStreak, tempStreak)
                    tempStreak = 1
                }
            } else {
                tempStreak = 1
            }
            previousDate = date
        }
        bestStreak = max(bestStreak, tempStreak)

        return (current: currentStreak, best: bestStreak)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: .matrixSpacingSmall) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text(value)
                .font(.matrixTitle2)
                .foregroundColor(color)

            Text(title)
                .font(.matrixCaption)
                .foregroundColor(.matrixTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder(color: color.opacity(0.3))
    }
}

struct PriorityBar: View {
    let priority: Int
    let count: Int
    let total: Int

    private var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0.0
    }

    var body: some View {
        HStack(spacing: .matrixSpacingMedium) {
            // Priority label
            Text("\(priority)")
                .font(.matrixBodyBold)
                .foregroundColor(Color.priorityColor(for: priority))
                .frame(width: 30, alignment: .center)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.matrixBackground)
                        .frame(height: 20)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.priorityColor(for: priority).opacity(0.6))
                        .frame(
                            width: geometry.size.width * CGFloat(percentage),
                            height: 20
                        )
                }
            }
            .frame(height: 20)

            // Count
            Text("\(count)")
                .font(.matrixCallout)
                .foregroundColor(.matrixTextPrimary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct VelocityRow: View {
    let period: String
    let completed: Int
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.matrixCyan)
                .frame(width: 24)

            Text(period)
                .font(.matrixBody)
                .foregroundColor(.matrixTextPrimary)

            Spacer()

            Text("\(completed)")
                .font(.matrixTitle3)
                .foregroundColor(.matrixSuccess)

            Text("tasks")
                .font(.matrixCaption)
                .foregroundColor(.matrixTextSecondary)
        }
    }
}

// MARK: - Productivity Chart

struct ProductivityChart: View {
    let trends: [ProductivityTrend]

    var body: some View {
        GeometryReader { geometry in
            let maxTasks = trends.map { $0.completedTasks }.max() ?? 1
            let barWidth = geometry.size.width / CGFloat(trends.count) - 4

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(trends.indices, id: \.self) { index in
                    let trend = trends[index]
                    let height = CGFloat(trend.completedTasks) / CGFloat(maxTasks) * geometry.size.height

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.matrixSuccess, Color.matrixSuccess.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: barWidth, height: max(height, 4))

                        Text(dayLabel(for: trend.date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.matrixTextTertiary)
                    }
                }
            }
        }
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(1))
    }
}

// MARK: - Time of Day Bar

struct TimeOfDayBar: View {
    let label: String
    let count: Int
    let total: Int
    let icon: String
    let color: Color

    private var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)

                Text(label)
                    .font(.matrixCallout)
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                Text("\(count)")
                    .font(.matrixBodyBold)
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.matrixBackground)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.7))
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsView(viewModel: AppViewModel())
    }
}
#endif
