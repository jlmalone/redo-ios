import Foundation

// MARK: - Advanced Analytics Models

/// Productivity trends over time
public struct ProductivityTrend: Identifiable {
    public let id = UUID()
    public let date: Date
    public let completedTasks: Int
    public let completedStoryPoints: Float
    public let averageCompletionTime: TimeInterval  // Average time from creation to completion

    public init(date: Date, completedTasks: Int, completedStoryPoints: Float, averageCompletionTime: TimeInterval) {
        self.date = date
        self.completedTasks = completedTasks
        self.completedStoryPoints = completedStoryPoints
        self.averageCompletionTime = averageCompletionTime
    }
}

/// Time-of-day insights
public struct TimeOfDayInsights {
    public let morningCompletions: Int      // 6am-12pm
    public let afternoonCompletions: Int    // 12pm-6pm
    public let eveningCompletions: Int      // 6pm-12am
    public let nightCompletions: Int        // 12am-6am

    public var mostProductiveTime: TimeOfDay {
        let max = [
            (TimeOfDay.morning, morningCompletions),
            (TimeOfDay.afternoon, afternoonCompletions),
            (TimeOfDay.evening, eveningCompletions),
            (TimeOfDay.night, nightCompletions)
        ].max { $0.1 < $1.1 }

        return max?.0 ?? .morning
    }

    public enum TimeOfDay: String {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case night = "Night"
    }

    public init(morningCompletions: Int, afternoonCompletions: Int, eveningCompletions: Int, nightCompletions: Int) {
        self.morningCompletions = morningCompletions
        self.afternoonCompletions = afternoonCompletions
        self.eveningCompletions = eveningCompletions
        self.nightCompletions = nightCompletions
    }
}

/// Weekly report summary
public struct WeeklyReport {
    public let weekStart: Date
    public let weekEnd: Date
    public let tasksCompleted: Int
    public let tasksCreated: Int
    public let storyPointsCompleted: Float
    public let averageCompletionTime: TimeInterval
    public let mostProductiveDay: Date?
    public let streakDays: Int

    public var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: weekStart)
    }

    public var changeFromPreviousWeek: Int {
        // This would be calculated by comparing with previous week's data
        0
    }

    public init(
        weekStart: Date,
        weekEnd: Date,
        tasksCompleted: Int,
        tasksCreated: Int,
        storyPointsCompleted: Float,
        averageCompletionTime: TimeInterval,
        mostProductiveDay: Date?,
        streakDays: Int
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.tasksCompleted = tasksCompleted
        self.tasksCreated = tasksCreated
        self.storyPointsCompleted = storyPointsCompleted
        self.averageCompletionTime = averageCompletionTime
        self.mostProductiveDay = mostProductiveDay
        self.streakDays = streakDays
    }
}

/// Completion prediction
public struct CompletionPrediction {
    public let targetDate: Date
    public let estimatedCompletionDate: Date
    public let confidence: Double  // 0.0 - 1.0
    public let tasksRemaining: Int
    public let averageDailyVelocity: Double  // Tasks per day

    public var isOnTrack: Bool {
        estimatedCompletionDate <= targetDate
    }

    public var daysAhead: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: estimatedCompletionDate, to: targetDate).day ?? 0
        return days
    }

    public init(
        targetDate: Date,
        estimatedCompletionDate: Date,
        confidence: Double,
        tasksRemaining: Int,
        averageDailyVelocity: Double
    ) {
        self.targetDate = targetDate
        self.estimatedCompletionDate = estimatedCompletionDate
        self.confidence = confidence
        self.tasksRemaining = tasksRemaining
        self.averageDailyVelocity = averageDailyVelocity
    }
}

// MARK: - Advanced Analytics Calculator

public class AdvancedAnalyticsCalculator {
    /// Calculate productivity trends for last N days
    public static func calculateProductivityTrends(from tasks: [RedoTask], days: Int = 7) -> [ProductivityTrend] {
        let calendar = Calendar.current
        let now = Date()

        var trends: [ProductivityTrend] = []

        for dayOffset in 0..<days {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: targetDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            // Get all todos completed on this day
            let completedThisDay = tasks.flatMap { $0.todoTasks }.filter { todo in
                guard let completed = todo.completed else { return false }
                return completed >= dayStart && completed < dayEnd
            }

            let completedCount = completedThisDay.count

            // Calculate story points completed
            let taskIds = Set(completedThisDay.map { $0.taskId })
            let storyPoints = tasks
                .filter { taskIds.contains($0.guid.uuidString) }
                .reduce(Float(0)) { $0 + $1.storyPoints }

            // Calculate average completion time
            var totalTime: TimeInterval = 0
            for todo in completedThisDay {
                if let completed = todo.completed {
                    totalTime += completed.timeIntervalSince(todo.created)
                }
            }
            let avgTime = completedThisDay.isEmpty ? 0 : totalTime / Double(completedThisDay.count)

            trends.append(ProductivityTrend(
                date: dayStart,
                completedTasks: completedCount,
                completedStoryPoints: storyPoints,
                averageCompletionTime: avgTime
            ))
        }

        return trends.reversed()  // Oldest first
    }

    /// Calculate time-of-day insights
    public static func calculateTimeOfDayInsights(from tasks: [RedoTask]) -> TimeOfDayInsights {
        let calendar = Calendar.current
        let completedTodos = tasks.flatMap { $0.todoTasks }.filter { $0.isCompleted }

        var morning = 0
        var afternoon = 0
        var evening = 0
        var night = 0

        for todo in completedTodos {
            guard let completed = todo.completed else { continue }
            let hour = calendar.component(.hour, from: completed)

            switch hour {
            case 6..<12:
                morning += 1
            case 12..<18:
                afternoon += 1
            case 18..<24:
                evening += 1
            default:
                night += 1
            }
        }

        return TimeOfDayInsights(
            morningCompletions: morning,
            afternoonCompletions: afternoon,
            eveningCompletions: evening,
            nightCompletions: night
        )
    }

    /// Calculate weekly report
    public static func calculateWeeklyReport(from tasks: [RedoTask], for weekStart: Date) -> WeeklyReport {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        // Tasks completed this week
        let completedThisWeek = tasks.flatMap { $0.todoTasks }.filter { todo in
            guard let completed = todo.completed else { return false }
            return completed >= weekStart && completed < weekEnd
        }

        let completedCount = completedThisWeek.count

        // Story points completed
        let taskIds = Set(completedThisWeek.map { $0.taskId })
        let storyPoints = tasks
            .filter { taskIds.contains($0.guid.uuidString) }
            .reduce(Float(0)) { $0 + $1.storyPoints }

        // Average completion time
        var totalTime: TimeInterval = 0
        for todo in completedThisWeek {
            if let completed = todo.completed {
                totalTime += completed.timeIntervalSince(todo.created)
            }
        }
        let avgTime = completedThisWeek.isEmpty ? 0 : totalTime / Double(completedThisWeek.count)

        // Most productive day
        var dailyCounts: [Date: Int] = [:]
        for todo in completedThisWeek {
            if let completed = todo.completed {
                let day = calendar.startOfDay(for: completed)
                dailyCounts[day, default: 0] += 1
            }
        }
        let mostProductiveDay = dailyCounts.max { $0.value < $1.value }?.key

        // Streak days (consecutive days with completions)
        let uniqueDays = Set(completedThisWeek.compactMap { todo -> Date? in
            guard let completed = todo.completed else { return nil }
            return calendar.startOfDay(for: completed)
        })
        let streakDays = uniqueDays.count

        // Tasks created this week (approximation based on created date)
        let tasksCreatedThisWeek = tasks.filter { task in
            task.created >= weekStart && task.created < weekEnd
        }.count

        return WeeklyReport(
            weekStart: weekStart,
            weekEnd: weekEnd,
            tasksCompleted: completedCount,
            tasksCreated: tasksCreatedThisWeek,
            storyPointsCompleted: storyPoints,
            averageCompletionTime: avgTime,
            mostProductiveDay: mostProductiveDay,
            streakDays: streakDays
        )
    }

    /// Predict completion date based on historical velocity
    public static func predictCompletion(
        for tasks: [RedoTask],
        targetDate: Date,
        historicalDays: Int = 30
    ) -> CompletionPrediction {
        let calendar = Calendar.current
        let now = Date()

        // Calculate historical daily velocity
        let historicalStart = calendar.date(byAdding: .day, value: -historicalDays, to: now)!
        let historicalCompletions = tasks.flatMap { $0.todoTasks }.filter { todo in
            guard let completed = todo.completed else { return false }
            return completed >= historicalStart && completed < now
        }

        let dailyVelocity = Double(historicalCompletions.count) / Double(historicalDays)

        // Count remaining tasks
        let remaining = tasks.filter { !$0.archived && $0.hasPendingTodos }.count

        // Estimate days to completion
        let estimatedDays = dailyVelocity > 0 ? Int(ceil(Double(remaining) / dailyVelocity)) : remaining * 7
        let estimatedCompletion = calendar.date(byAdding: .day, value: estimatedDays, to: now) ?? now

        // Calculate confidence (higher if more historical data and consistent velocity)
        let confidence = min(1.0, Double(historicalCompletions.count) / 100.0) * 0.8  // 80% max

        return CompletionPrediction(
            targetDate: targetDate,
            estimatedCompletionDate: estimatedCompletion,
            confidence: confidence,
            tasksRemaining: remaining,
            averageDailyVelocity: dailyVelocity
        )
    }
}
