import SwiftUI
import RedoCore

/// Main task list view with Matrix theme
public struct TaskListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingCreateTask = false
    @State private var showingFilters = false
    @State private var showingPresets = false
    @State private var isSelectionMode = false
    @State private var selectedTasks = Set<UUID>()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                // Matrix background
                Color.matrixBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    SearchBar(text: $viewModel.searchText)
                        .padding()

                    // Task list
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.filteredTasks.isEmpty {
                        emptyStateView
                    } else {
                        taskListContent
                    }
                }
            }
            .navigationTitle("REDO")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectionMode {
                        Button(action: {
                            isSelectionMode = false
                            selectedTasks.removeAll()
                        }) {
                            Text("Cancel")
                                .foregroundColor(.matrixNeon)
                        }
                    } else {
                        syncStatusView
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if !isSelectionMode {
                            Button(action: {
                                isSelectionMode = true
                                HapticManager.shared.selectionChanged()
                            }) {
                                Image(systemName: "checkmark.circle")
                                    .font(.title3)
                                    .foregroundColor(.matrixNeon)
                            }
                            .accessibilityLabel("Selection mode")
                            .accessibilityHint("Double tap to enter selection mode")
                            .accessibilityIdentifier(AccessibilityID.selectionModeButton)

                            Button(action: { showingPresets = true }) {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.title3)
                                    .foregroundColor(.matrixNeon)
                            }
                            .accessibilityLabel("Filter presets")
                            .accessibilityHint("Double tap to view saved filter presets")

                            filterButton
                            createButton
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateTask) {
                CreateTaskView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingFilters) {
                AdvancedFilterView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPresets) {
                FilterPresetsView(viewModel: viewModel)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.matrixNeon)
                .scaleEffect(1.5)

            Text("Reconstructing state...")
                .font(.matrixBody)
                .foregroundColor(.matrixTextSecondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundColor(.matrixNeonDim)
                .neonGlow()

            Text(viewModel.searchText.isEmpty ? "No tasks yet" : "No matching tasks")
                .font(.matrixTitle2)
                .foregroundColor(.matrixTextPrimary)

            Text("Tap + to create your first task")
                .font(.matrixBody)
                .foregroundColor(.matrixTextSecondary)

            Button(action: { showingCreateTask = true }) {
                Label("Create Task", systemImage: "plus.circle.fill")
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixBackground)
                    .padding()
                    .background(Color.matrixNeon)
                    .cornerRadius(.matrixCornerRadius)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var taskListContent: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: .matrixSpacingMedium) {
                    ForEach(viewModel.filteredTasks) { task in
                        if isSelectionMode {
                            // Selection mode - show checkbox
                            Button(action: {
                                toggleSelection(task)
                            }) {
                                HStack(spacing: .matrixSpacingMedium) {
                                    Image(systemName: selectedTasks.contains(task.guid) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundColor(selectedTasks.contains(task.guid) ? .matrixNeon : .matrixTextSecondary)

                                    MatrixTaskCard(
                                        task: task,
                                        onTap: {},
                                        onComplete: {}
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Normal mode - navigation link
                            NavigationLink(destination: TaskDetailView(viewModel: viewModel, task: task)) {
                                MatrixTaskCard(
                                    task: task,
                                    onTap: {
                                        HapticManager.shared.buttonTapped()
                                    },
                                    onComplete: {
                                        Task {
                                            try? await viewModel.completeTask(task)
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AccessibilityLabels.taskCard(
                                title: task.title,
                                priority: task.priority,
                                overdue: task.isOverdue
                            ))
                            .accessibilityHint(AccessibilityHints.openTaskDetail)
                            .accessibilityIdentifier("\(AccessibilityID.taskCard)_\(task.guid.uuidString)")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.7)),
                                removal: .opacity.animation(.easeOut(duration: 0.2))
                            ))
                        }
                    }
                }
                .padding()
                .padding(.bottom, isSelectionMode && !selectedTasks.isEmpty ? 80 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.filteredTasks.count)
            }
            .refreshable {
                // Pull to refresh - reconstruct state and sync
                do {
                    try await viewModel.reconstructState()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }

            // Batch action buttons (bottom bar)
            if isSelectionMode && !selectedTasks.isEmpty {
                VStack {
                    Spacer()

                    HStack(spacing: .matrixSpacingMedium) {
                        // Complete button
                        Button(action: batchComplete) {
                            Label("\(selectedTasks.count) Complete", systemImage: "checkmark.circle.fill")
                                .font(.matrixBodyBold)
                                .foregroundColor(.matrixBackground)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.matrixSuccess)
                                .cornerRadius(.matrixCornerRadius)
                        }
                        .accessibilityLabel(AccessibilityLabels.batchComplete(count: selectedTasks.count))
                        .accessibilityHint(AccessibilityHints.completeTask)
                        .accessibilityIdentifier(AccessibilityID.batchCompleteButton)

                        // Archive button
                        Button(action: batchArchive) {
                            Label("Archive", systemImage: "archivebox.fill")
                                .font(.matrixBodyBold)
                                .foregroundColor(.matrixBackground)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.matrixAmber)
                                .cornerRadius(.matrixCornerRadius)
                        }
                        .accessibilityLabel(AccessibilityLabels.batchArchive(count: selectedTasks.count))
                        .accessibilityHint(AccessibilityHints.archiveTask)
                        .accessibilityIdentifier(AccessibilityID.batchArchiveButton)

                        // Delete button
                        Button(action: batchDelete) {
                            Image(systemName: "trash.fill")
                                .font(.title3)
                                .foregroundColor(.matrixBackground)
                                .frame(width: 50, height: 50)
                                .background(Color.matrixError)
                                .cornerRadius(.matrixCornerRadius)
                        }
                        .accessibilityLabel(AccessibilityLabels.batchDelete(count: selectedTasks.count))
                        .accessibilityHint(AccessibilityHints.deleteTask)
                        .accessibilityIdentifier(AccessibilityID.batchDeleteButton)
                    }
                    .padding()
                    .background(Color.matrixBackgroundSecondary)
                    .matrixBorder(color: .matrixNeon)
                }
                .transition(.move(edge: .bottom))
            }
        }
    }

    private var syncStatusView: some View {
        HStack(spacing: 6) {
            switch viewModel.syncStatus {
            case .idle:
                Image(systemName: "cloud")
                    .foregroundColor(.matrixTextSecondary)
            case .syncing:
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.matrixNeon)
            case .synced:
                Image(systemName: "cloud.fill")
                    .foregroundColor(.matrixSuccess)
            case .failed:
                Image(systemName: "cloud.slash")
                    .foregroundColor(.matrixError)
            }
        }
        .font(.caption)
    }

    private var filterButton: some View {
        Button(action: { showingFilters = true }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundColor(.matrixNeon)

                // Active filter count badge
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.matrixBackground)
                        .padding(3)
                        .background(Circle().fill(Color.matrixAmber))
                        .offset(x: 8, y: -8)
                }
            }
        }
        .accessibilityLabel(activeFilterCount > 0 ? "Filters: \(activeFilterCount) active" : "Filters")
        .accessibilityHint(AccessibilityHints.filterTasks)
        .accessibilityIdentifier(AccessibilityID.filterButton)
    }

    private var hasActiveFilters: Bool {
        viewModel.showArchived ||
        viewModel.showOnlyOverdue ||
        viewModel.showOnlyActive ||
        !viewModel.selectedPriorities.isEmpty ||
        viewModel.selectedPriority != nil ||
        viewModel.searchScope != .both ||
        viewModel.sortOption != .rank ||
        viewModel.dateFilter != nil
    }

    private var activeFilterCount: Int {
        var count = 0
        if viewModel.showArchived { count += 1 }
        if viewModel.showOnlyOverdue { count += 1 }
        if viewModel.showOnlyActive { count += 1 }
        if !viewModel.selectedPriorities.isEmpty { count += 1 }
        if viewModel.selectedPriority != nil { count += 1 }
        if viewModel.searchScope != .both { count += 1 }
        if viewModel.sortOption != .rank { count += 1 }
        if viewModel.dateFilter != nil { count += 1 }
        return count
    }

    private var createButton: some View {
        Button(action: { showingCreateTask = true }) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundColor(.matrixNeon)
                .neonGlow(radius: 8)
        }
        .accessibilityLabel("Create task")
        .accessibilityHint(AccessibilityHints.createTask)
        .accessibilityIdentifier(AccessibilityID.createTaskButton)
    }

    // MARK: - Batch Operations

    private func toggleSelection(_ task: RedoTask) {
        if selectedTasks.contains(task.guid) {
            selectedTasks.remove(task.guid)
        } else {
            selectedTasks.insert(task.guid)
        }
        HapticManager.shared.selectionChanged()
    }

    private func batchComplete() {
        let tasks = viewModel.filteredTasks.filter { selectedTasks.contains($0.guid) }

        Task {
            do {
                try await viewModel.completeTasks(tasks)
                isSelectionMode = false
                selectedTasks.removeAll()
            } catch {
                viewModel.errorMessage = "Failed to complete tasks: \(error.localizedDescription)"
            }
        }
    }

    private func batchArchive() {
        let tasks = viewModel.filteredTasks.filter { selectedTasks.contains($0.guid) }

        Task {
            do {
                try await viewModel.archiveTasks(tasks)
                isSelectionMode = false
                selectedTasks.removeAll()
            } catch {
                viewModel.errorMessage = "Failed to archive tasks: \(error.localizedDescription)"
            }
        }
    }

    private func batchDelete() {
        let tasks = viewModel.filteredTasks.filter { selectedTasks.contains($0.guid) }

        Task {
            do {
                try await viewModel.deleteTasks(tasks)
                isSelectionMode = false
                selectedTasks.removeAll()
            } catch {
                viewModel.errorMessage = "Failed to delete tasks: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.matrixNeon)
                .font(.headline)

            TextField("Search tasks...", text: $text)
                .font(.matrixBody)
                .foregroundColor(.matrixTextPrimary)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .accessibilityLabel("Search tasks")
                .accessibilityHint("Enter text to search for tasks")
                .accessibilityIdentifier(AccessibilityID.searchBar)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.matrixTextSecondary)
                }
            }
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }
}

// MARK: - Filter View

struct FilterView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                VStack(spacing: .matrixSpacingLarge) {
                    // Show archived toggle
                    Toggle("Show Archived", isOn: $viewModel.showArchived)
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)
                        .tint(.matrixNeon)
                        .padding()
                        .background(Color.matrixBackgroundSecondary)
                        .cornerRadius(.matrixCornerRadius)
                        .matrixBorder()

                    // Priority filter
                    VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
                        Text("Priority")
                            .font(.matrixHeadline)
                            .foregroundColor(.matrixNeon)

                        HStack(spacing: .matrixSpacingSmall) {
                            ForEach([1, 2, 3, 4, 5], id: \.self) { priority in
                                PriorityFilterButton(
                                    priority: priority,
                                    isSelected: viewModel.selectedPriority == priority,
                                    action: {
                                        viewModel.selectedPriority = viewModel.selectedPriority == priority ? nil : priority
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.matrixBackgroundSecondary)
                    .cornerRadius(.matrixCornerRadius)
                    .matrixBorder()

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Filters")
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

struct PriorityFilterButton: View {
    let priority: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(priority)")
                .font(.matrixBodyBold)
                .foregroundColor(isSelected ? .matrixBackground : Color.priorityColor(for: priority))
                .frame(width: 50, height: 50)
                .background(isSelected ? Color.priorityColor(for: priority) : Color.matrixBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.priorityColor(for: priority), lineWidth: 2)
                )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TaskListView_Previews: PreviewProvider {
    static var previews: some View {
        TaskListView(viewModel: AppViewModel())
    }
}
#endif
