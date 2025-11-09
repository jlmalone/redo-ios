import SwiftUI
import RedoCore

/// Advanced filtering and sorting view with multi-criteria support
public struct AdvancedFilterView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showingDateFilter = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .matrixSpacingLarge) {
                        // Quick toggles
                        quickTogglesSection

                        // Priority filter (multi-select)
                        prioritySection

                        // Search scope
                        searchScopeSection

                        // Sort options
                        sortSection

                        // Date filters
                        dateFilterSection

                        // Active filter count
                        if activeFilterCount > 0 {
                            clearFiltersButton
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Filters & Sort")
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

    // MARK: - Sections

    private var quickTogglesSection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            Text("Quick Filters")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: .matrixSpacingSmall) {
                FilterToggle(
                    icon: "archivebox",
                    title: "Show Archived",
                    isOn: $viewModel.showArchived,
                    color: .matrixTextSecondary
                )

                FilterToggle(
                    icon: "exclamationmark.triangle",
                    title: "Overdue Only",
                    isOn: $viewModel.showOnlyOverdue,
                    color: .matrixError
                )

                FilterToggle(
                    icon: "play.circle",
                    title: "Active Only",
                    isOn: $viewModel.showOnlyActive,
                    color: .matrixSuccess
                )
            }
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }

    private var prioritySection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            HStack {
                Text("Priority")
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixNeon)

                Spacer()

                if !viewModel.selectedPriorities.isEmpty {
                    Button("Clear") {
                        viewModel.selectedPriorities.removeAll()
                        HapticManager.shared.selectionChanged()
                    }
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)
                }
            }

            HStack(spacing: .matrixSpacingSmall) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { priority in
                    MultiSelectPriorityButton(
                        priority: priority,
                        isSelected: viewModel.selectedPriorities.contains(priority),
                        action: {
                            if viewModel.selectedPriorities.contains(priority) {
                                viewModel.selectedPriorities.remove(priority)
                            } else {
                                viewModel.selectedPriorities.insert(priority)
                            }
                            HapticManager.shared.selectionChanged()
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }

    private var searchScopeSection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            Text("Search In")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Search Scope", selection: $viewModel.searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .background(Color.matrixBackgroundSecondary)
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }

    private var sortSection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            Text("Sort By")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(SortOption.allCases) { option in
                SortOptionButton(
                    option: option,
                    isSelected: viewModel.sortOption == option,
                    action: {
                        viewModel.sortOption = option
                        HapticManager.shared.selectionChanged()
                    }
                )
            }
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }

    private var dateFilterSection: some View {
        VStack(spacing: .matrixSpacingMedium) {
            HStack {
                Text("Date Range")
                    .font(.matrixHeadline)
                    .foregroundColor(.matrixNeon)

                Spacer()

                if viewModel.dateFilter != nil {
                    Button("Clear") {
                        viewModel.dateFilter = nil
                        HapticManager.shared.selectionChanged()
                    }
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)
                }
            }

            if let dateFilter = viewModel.dateFilter {
                VStack(spacing: .matrixSpacingSmall) {
                    // Filter type picker
                    Picker("Date Type", selection: Binding(
                        get: { dateFilter.type },
                        set: { newType in
                            viewModel.dateFilter = DateFilter(
                                type: newType,
                                startDate: dateFilter.startDate,
                                endDate: dateFilter.endDate
                            )
                        }
                    )) {
                        ForEach(DateFilter.DateFilterType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Date pickers
                    DateRangePicker(
                        startDate: Binding(
                            get: { dateFilter.startDate },
                            set: { newStart in
                                viewModel.dateFilter = DateFilter(
                                    type: dateFilter.type,
                                    startDate: newStart,
                                    endDate: dateFilter.endDate
                                )
                            }
                        ),
                        endDate: Binding(
                            get: { dateFilter.endDate },
                            set: { newEnd in
                                viewModel.dateFilter = DateFilter(
                                    type: dateFilter.type,
                                    startDate: dateFilter.startDate,
                                    endDate: newEnd
                                )
                            }
                        )
                    )
                }
            } else {
                Button(action: {
                    viewModel.dateFilter = DateFilter(
                        type: .created,
                        startDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
                        endDate: Date()
                    )
                    HapticManager.shared.selectionChanged()
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundColor(.matrixNeon)
                        Text("Add Date Filter")
                            .font(.matrixBody)
                            .foregroundColor(.matrixTextPrimary)
                        Spacer()
                    }
                    .padding()
                    .background(Color.matrixBackground)
                    .cornerRadius(.matrixCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: .matrixCornerRadius)
                            .stroke(Color.matrixNeon.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding()
        .background(Color.matrixBackgroundSecondary)
        .cornerRadius(.matrixCornerRadius)
        .matrixBorder()
    }

    private var clearFiltersButton: some View {
        Button(action: clearAllFilters) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                Text("Clear All Filters (\(activeFilterCount))")
            }
            .font(.matrixBodyBold)
            .foregroundColor(.matrixBackground)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.matrixAmber)
            .cornerRadius(.matrixCornerRadius)
            .neonGlow(color: .matrixAmber, radius: 8)
        }
    }

    // MARK: - Helpers

    private var activeFilterCount: Int {
        var count = 0
        if viewModel.showArchived { count += 1 }
        if viewModel.showOnlyOverdue { count += 1 }
        if viewModel.showOnlyActive { count += 1 }
        if !viewModel.selectedPriorities.isEmpty { count += 1 }
        if viewModel.searchScope != .both { count += 1 }
        if viewModel.sortOption != .rank { count += 1 }
        if viewModel.dateFilter != nil { count += 1 }
        return count
    }

    private func clearAllFilters() {
        viewModel.showArchived = false
        viewModel.showOnlyOverdue = false
        viewModel.showOnlyActive = false
        viewModel.selectedPriorities.removeAll()
        viewModel.searchScope = .both
        viewModel.sortOption = .rank
        viewModel.dateFilter = nil
        HapticManager.shared.success()
    }
}

// MARK: - Filter Toggle

struct FilterToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: .matrixSpacingMedium) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)

                Text(title)
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextPrimary)
            }
        }
        .tint(.matrixNeon)
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(isOn ? Color.matrixNeon.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Multi-Select Priority Button

struct MultiSelectPriorityButton: View {
    let priority: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(priority)")
                    .font(.matrixTitle3)
                    .foregroundColor(isSelected ? .matrixBackground : Color.priorityColor(for: priority))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.matrixBackground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? Color.priorityColor(for: priority) : Color.matrixBackground)
            .cornerRadius(.matrixCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: .matrixCornerRadius)
                    .stroke(Color.priorityColor(for: priority), lineWidth: isSelected ? 3 : 2)
            )
        }
    }
}

// MARK: - Sort Option Button

struct SortOptionButton: View {
    let option: SortOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(isSelected ? .matrixBackground : .matrixNeon)
                    .frame(width: 24)

                Text(option.rawValue)
                    .font(isSelected ? .matrixBodyBold : .matrixBody)
                    .foregroundColor(isSelected ? .matrixBackground : .matrixTextPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.matrixBackground)
                }
            }
            .padding()
            .background(isSelected ? Color.matrixNeon : Color.matrixBackground)
            .cornerRadius(.matrixCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: .matrixCornerRadius)
                    .stroke(isSelected ? Color.clear : Color.matrixNeon.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var iconName: String {
        switch option {
        case .rank: return "brain.head.profile"
        case .priority: return "exclamationmark.3"
        case .dueDate: return "calendar.badge.clock"
        case .createdDate: return "calendar.badge.plus"
        case .title: return "textformat.abc"
        }
    }
}

// MARK: - Date Range Picker

struct DateRangePicker: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?

    var body: some View {
        VStack(spacing: .matrixSpacingSmall) {
            // Start date
            VStack(alignment: .leading, spacing: 4) {
                Text("From")
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)

                if let start = startDate {
                    HStack {
                        DatePicker("", selection: Binding(
                            get: { start },
                            set: { startDate = $0 }
                        ), displayedComponents: [.date])
                        .labelsHidden()
                        .colorScheme(.dark)

                        Spacer()

                        Button(action: { startDate = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.matrixTextSecondary)
                        }
                    }
                } else {
                    Button(action: { startDate = Date() }) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundColor(.matrixNeon)
                            Text("Set Start Date")
                                .font(.matrixCaption)
                                .foregroundColor(.matrixTextSecondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.matrixBackground)
            .cornerRadius(8)

            // End date
            VStack(alignment: .leading, spacing: 4) {
                Text("To")
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)

                if let end = endDate {
                    HStack {
                        DatePicker("", selection: Binding(
                            get: { end },
                            set: { endDate = $0 }
                        ), displayedComponents: [.date])
                        .labelsHidden()
                        .colorScheme(.dark)

                        Spacer()

                        Button(action: { endDate = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.matrixTextSecondary)
                        }
                    }
                } else {
                    Button(action: { endDate = Date() }) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundColor(.matrixNeon)
                            Text("Set End Date")
                                .font(.matrixCaption)
                                .foregroundColor(.matrixTextSecondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.matrixBackground)
            .cornerRadius(8)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AdvancedFilterView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedFilterView(viewModel: AppViewModel())
    }
}
#endif
