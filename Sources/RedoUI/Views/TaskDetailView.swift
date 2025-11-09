import SwiftUI
import RedoCore

/// Detailed task view with edit, history, and TODO management
public struct TaskDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let task: RedoTask

    @Environment(\.dismiss) var dismiss
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingHistory = false
    @State private var showingCreateTodo = false

    public init(viewModel: AppViewModel, task: RedoTask) {
        self.viewModel = viewModel
        self.task = task
    }

    public var body: some View {
        ZStack {
            Color.matrixBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .matrixSpacingLarge) {
                    // Header Section
                    headerSection

                    Divider()
                        .background(Color.matrixNeonFaint)

                    // Metadata Section
                    metadataSection

                    Divider()
                        .background(Color.matrixNeonFaint)

                    // TODO History Section
                    todoHistorySection

                    Divider()
                        .background(Color.matrixNeonFaint)

                    // Actions Section
                    actionsSection
                }
                .padding()
            }
        }
        .navigationTitle("Task Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { isEditing = true }) {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(action: { showingHistory = true }) {
                        Label("View History", systemImage: "clock")
                    }

                    Button(action: {
                        Task {
                            try? await viewModel.archiveTask(task)
                            dismiss()
                        }
                    }) {
                        Label(
                            task.archived ? "Unarchive" : "Archive",
                            systemImage: task.archived ? "tray.and.arrow.up" : "tray.and.arrow.down"
                        )
                    }

                    Divider()

                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.matrixNeon)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditTaskView(viewModel: viewModel, task: task)
        }
        .sheet(isPresented: $showingHistory) {
            TaskHistoryView(task: task)
        }
        .sheet(isPresented: $showingCreateTodo) {
            CreateTodoView(viewModel: viewModel, task: task)
        }
        .alert("Delete Task?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    try? await viewModel.deleteTask(task)
                    dismiss()
                }
            }
        } message: {
            Text("This task will be permanently deleted. This action cannot be undone.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            // Title
            Text(task.title)
                .font(.matrixTitle2)
                .foregroundColor(.matrixNeon)
                .neonGlow()

            // Description (if present)
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextPrimary)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Metadata")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            // Priority
            MetadataRow(
                label: "Priority",
                value: task.priorityDisplay,
                color: Color.priorityColor(for: task.priority)
            )

            // Story Points
            MetadataRow(
                label: "Story Points",
                value: "\(Int(task.storyPoints)) pts",
                color: .matrixTextPrimary
            )

            // Recurrence
            MetadataRow(
                label: "Recurrence",
                value: frequencyText,
                color: .matrixTextPrimary
            )

            // Created
            MetadataRow(
                label: "Created",
                value: formatDate(task.created),
                color: .matrixTextSecondary
            )

            // Last Updated
            if let lastUpdated = task.lastUpdated {
                MetadataRow(
                    label: "Last Updated",
                    value: formatDate(lastUpdated),
                    color: .matrixTextSecondary
                )
            }

            // Status
            MetadataRow(
                label: "Status",
                value: task.archived ? "Archived" : "Active",
                color: task.archived ? .matrixTextSecondary : .matrixSuccess
            )
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }

    private var todoHistorySection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            HStack {
                Text("TODO History")
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixNeon)

                Spacer()

                Button(action: {
                    showingCreateTodo = true
                    HapticManager.shared.buttonTapped()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.matrixNeon)
                        .font(.title3)
                }

                Text("\(task.todoTasks.count) total")
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)
            }

            if task.todoTasks.isEmpty {
                Text("No TODOs yet")
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(task.todoTasks.sorted(by: { $0.created > $1.created })) { todo in
                    TodoHistoryCard(todo: todo)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            // Complete Button
            if task.hasPendingTodos {
                Button(action: {
                    Task {
                        try? await viewModel.completeTask(task)
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Complete Current TODO")
                    }
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixBackground)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.matrixSuccess)
                    .cornerRadius(.matrixCornerRadius)
                    .neonGlow(color: .matrixSuccess)
                }

                // Snooze Button with Quick Actions
                Menu {
                    Button(action: {
                        Task {
                            try? await viewModel.snoozeTask(task, days: 1)
                        }
                    }) {
                        Label("Snooze 1 Day", systemImage: "moon")
                    }

                    Button(action: {
                        Task {
                            try? await viewModel.snoozeTask(task, days: 3)
                        }
                    }) {
                        Label("Snooze 3 Days", systemImage: "moon.stars")
                    }

                    Button(action: {
                        Task {
                            try? await viewModel.snoozeTask(task, days: 7)
                        }
                    }) {
                        Label("Snooze 1 Week", systemImage: "calendar.badge.clock")
                    }

                    Button(action: {
                        Task {
                            try? await viewModel.snoozeTask(task, days: 14)
                        }
                    }) {
                        Label("Snooze 2 Weeks", systemImage: "calendar")
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock.badge.exclamationmark")
                        Text("Snooze Task")
                    }
                    .font(.matrixBody)
                    .foregroundColor(.matrixAmber)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.matrixBackgroundSecondary)
                    .cornerRadius(.matrixCornerRadius)
                    .matrixBorder(color: .matrixAmber)
                }
            }

            // Archive/Unarchive Button
            Button(action: {
                Task {
                    try? await viewModel.archiveTask(task)
                }
            }) {
                HStack {
                    Image(systemName: task.archived ? "tray.and.arrow.up" : "tray.and.arrow.down")
                    Text(task.archived ? "Unarchive Task" : "Archive Task")
                }
                .font(.matrixBody)
                .foregroundColor(.matrixNeon)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.matrixBackgroundSecondary)
                .cornerRadius(.matrixCornerRadius)
                .matrixBorder()
            }
        }
    }

    // MARK: - Helpers

    private var frequencyText: String {
        switch task.frequencyDays {
        case 0: return "One-time"
        case 1: return "Daily"
        case 7: return "Weekly"
        case 14: return "Bi-weekly"
        case 30: return "Monthly"
        default: return "Every \(task.frequencyDays) days"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Views

struct MetadataRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.matrixCallout)
                .foregroundColor(.matrixTextSecondary)

            Spacer()

            Text(value)
                .font(.matrixBodyBold)
                .foregroundColor(color)
        }
    }
}

struct TodoHistoryCard: View {
    let todo: TodoTask

    var body: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
            HStack {
                // Status icon
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .matrixSuccess : .matrixTextSecondary)

                // Deadline
                Text(formatDate(todo.deadline))
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                // Overdue indicator
                if todo.isOverdue {
                    Text("OVERDUE")
                        .font(.matrixCaption2)
                        .foregroundColor(.matrixError)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.matrixError.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            // Completion info
            if let completed = todo.completed {
                Text("Completed \(formatDate(completed))")
                    .font(.matrixCaption)
                    .foregroundColor(.matrixSuccess)
            }

            // Notes
            if !todo.notes.isEmpty {
                Text(todo.notes)
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            todo.isCompleted
                ? Color.matrixSuccess.opacity(0.05)
                : Color.matrixBackgroundSecondary
        )
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder(color: todo.isCompleted ? .matrixSuccess.opacity(0.3) : .matrixNeonFaint)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Edit Task View

struct EditTaskView: View {
    @ObservedObject var viewModel: AppViewModel
    let task: RedoTask

    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var description: String
    @State private var priority: Int
    @State private var storyPoints: Float
    @State private var frequencyDays: Int

    init(viewModel: AppViewModel, task: RedoTask) {
        self.viewModel = viewModel
        self.task = task

        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description)
        _priority = State(initialValue: task.priority)
        _storyPoints = State(initialValue: task.storyPoints)
        _frequencyDays = State(initialValue: task.frequencyDays)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                Form {
                    Section("Title") {
                        TextField("Task title", text: $title)
                    }

                    Section("Description") {
                        TextEditor(text: $description)
                            .frame(height: 100)
                    }

                    Section("Priority") {
                        Picker("Priority", selection: $priority) {
                            Text("Low").tag(1)
                            Text("Medium-Low").tag(2)
                            Text("Medium").tag(3)
                            Text("Medium-High").tag(4)
                            Text("High").tag(5)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Story Points") {
                        Slider(value: $storyPoints, in: 1...13, step: 1)
                        Text("\(Int(storyPoints)) points")
                    }

                    Section("Recurrence") {
                        Picker("Frequency", selection: $frequencyDays) {
                            Text("One-time").tag(0)
                            Text("Daily").tag(1)
                            Text("Weekly").tag(7)
                            Text("Bi-weekly").tag(14)
                            Text("Monthly").tag(30)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.matrixTextSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            try? await viewModel.updateTask(
                                taskId: task.guid,
                                title: title,
                                description: description,
                                priority: priority,
                                storyPoints: storyPoints,
                                frequencyDays: frequencyDays
                            )
                            dismiss()
                        }
                    }
                    .foregroundColor(.matrixNeon)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Create TODO View

struct CreateTodoView: View {
    @ObservedObject var viewModel: AppViewModel
    let task: RedoTask

    @Environment(\.dismiss) var dismiss

    @State private var deadline = Date().addingTimeInterval(86400) // Tomorrow
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                Form {
                    Section("Deadline") {
                        DatePicker("When is this due?", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                    }

                    Section("Notes (Optional)") {
                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add TODO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.matrixTextSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        saveTodo()
                    }
                    .foregroundColor(.matrixNeon)
                    .disabled(isSaving)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveTodo() {
        isSaving = true

        Task {
            do {
                try await viewModel.createTodo(for: task, deadline: deadline, notes: notes)
                dismiss()
            } catch {
                viewModel.errorMessage = "Failed to create TODO: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

// MARK: - Task History View

struct TaskHistoryView: View {
    let task: RedoTask

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
                        Text("Change history and DAG visualization coming soon...")
                            .font(.matrixBody)
                            .foregroundColor(.matrixTextSecondary)
                            .padding()
                    }
                }
            }
            .navigationTitle("Task History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.matrixNeon)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
