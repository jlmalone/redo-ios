import SwiftUI
import RedoCore

/// Calendar view showing tasks by deadline
public struct CalendarView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedDate = Date()
    @State private var currentMonth = Date()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Month Selector
                    monthSelector

                    // Calendar Grid
                    calendarGrid

                    Divider()
                        .background(Color.matrixNeonFaint)
                        .padding(.vertical)

                    // Tasks for Selected Date
                    tasksForSelectedDate
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Month Selector

    private var monthSelector: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.matrixNeon)
                    .font(.title3)
            }

            Spacer()

            Text(monthYearText)
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.matrixNeon)
                    .font(.title3)
            }
        }
        .padding()
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: .matrixSpacingSmall) {
            // Weekday Headers
            weekdayHeaders

            // Days Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: .matrixSpacingSmall) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: isSameDay(date, selectedDate),
                            isToday: isSameDay(date, Date()),
                            taskCount: tasksCount(for: date),
                            action: { selectedDate = date }
                        )
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var weekdayHeaders: some View {
        HStack {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Tasks for Selected Date

    private var tasksForSelectedDate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
                Text(selectedDateText)
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixNeon)
                    .padding(.horizontal)

                if filteredTasksForSelectedDate.isEmpty {
                    Text("No tasks for this date")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(filteredTasksForSelectedDate) { task in
                        NavigationLink(destination: TaskDetailView(viewModel: viewModel, task: task)) {
                            CompactTaskCard(task: task)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Helpers

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    private var selectedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }

    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let days = calendar.range(of: .day, in: .month, for: currentMonth)!

        var result: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in days {
            if let date = calendar.date(bySetting: .day, value: day, of: currentMonth) {
                result.append(date)
            }
        }

        return result
    }

    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }

    private func tasksCount(for date: Date) -> Int {
        viewModel.tasks.filter { task in
            guard let todo = task.currentPendingTask else { return false }
            return isSameDay(todo.deadline, date)
        }.count
    }

    private var filteredTasksForSelectedDate: [RedoTask] {
        viewModel.tasks.filter { task in
            guard let todo = task.currentPendingTask else { return false }
            return isSameDay(todo.deadline, selectedDate)
        }
    }

    private func previousMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private func nextMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let taskCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.matrixBody)
                    .foregroundColor(textColor)

                if taskCount > 0 {
                    Circle()
                        .fill(Color.matrixNeon)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private var textColor: Color {
        if isSelected {
            return .matrixBackground
        } else if isToday {
            return .matrixNeon
        } else {
            return .matrixTextPrimary
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return .matrixNeon
        } else if isToday {
            return .matrixNeon.opacity(0.15)
        } else {
            return .matrixBackgroundSecondary
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .matrixNeon
        } else if isToday {
            return .matrixNeon
        } else {
            return .matrixNeonFaint
        }
    }
}

// MARK: - Compact Task Card

struct CompactTaskCard: View {
    let task: RedoTask

    var body: some View {
        HStack(spacing: .matrixSpacingMedium) {
            // Status
            Image(systemName: task.hasPendingTodos ? "circle" : "checkmark.circle.fill")
                .foregroundColor(task.hasPendingTodos ? .matrixNeon : .matrixSuccess)

            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextPrimary)

                if let todo = task.currentPendingTask {
                    Text(todo.deadlineDisplay)
                        .font(.matrixCaption)
                        .foregroundColor(todo.isOverdue ? .matrixError : .matrixTextSecondary)
                }
            }

            Spacer()

            // Priority indicator
            Circle()
                .fill(Color.priorityColor(for: task.priority))
                .frame(width: 8, height: 8)
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder(color: task.isOverdue ? .matrixError : .matrixNeonFaint)
    }
}
