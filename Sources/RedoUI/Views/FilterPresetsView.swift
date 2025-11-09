import SwiftUI
import RedoCore

/// View for managing saved filter presets
public struct FilterPresetsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var presets: [FilterPreset] = []
    @State private var showingCreatePreset = false
    @State private var showingEditPreset: FilterPreset? = nil
    @State private var errorMessage: String? = nil

    private let presetStorage = FilterPresetStorage()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .matrixSpacingLarge) {
                        // Quick apply section
                        quickApplySection

                        Divider()
                            .background(Color.matrixNeon.opacity(0.3))

                        // Saved presets
                        savedPresetsSection

                        // Custom presets
                        customPresetsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Filter Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.matrixNeon)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreatePreset = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.matrixNeon)
                    }
                }
            }
            .sheet(isPresented: $showingCreatePreset) {
                CreatePresetView(viewModel: viewModel, onSave: { preset in
                    do {
                        try presetStorage.savePreset(preset)
                        loadPresets()
                        HapticManager.shared.success()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                })
            }
            .sheet(item: $showingEditPreset) { preset in
                EditPresetView(preset: preset, onSave: { updated in
                    do {
                        try presetStorage.savePreset(updated)
                        loadPresets()
                        HapticManager.shared.success()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                })
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadPresets()
        }
    }

    // MARK: - Sections

    private var quickApplySection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Quick Apply")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .matrixSpacingSmall) {
                    ForEach(presets.filter { $0.isDefault }) { preset in
                        QuickPresetCard(preset: preset) {
                            applyPreset(preset)
                        }
                    }
                }
            }
        }
    }

    private var savedPresetsSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("Default Presets")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            ForEach(presets.filter { $0.isDefault }) { preset in
                PresetRow(preset: preset) {
                    applyPreset(preset)
                }
            }
        }
    }

    private var customPresetsSection: some View {
        VStack(alignment: .leading, spacing: .matrixSpacingMedium) {
            Text("My Presets")
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)

            let customPresets = presets.filter { !$0.isDefault }

            if customPresets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.matrixTextSecondary.opacity(0.5))

                    Text("No custom presets yet")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextSecondary)

                    Button(action: { showingCreatePreset = true }) {
                        Label("Create Preset", systemImage: "plus.circle")
                            .font(.matrixBodyBold)
                            .foregroundColor(.matrixBackground)
                            .padding()
                            .background(Color.matrixNeon)
                            .cornerRadius(.matrixCornerRadius)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, .matrixSpacingLarge)
            } else {
                ForEach(customPresets.sorted { $0.usageCount > $1.usageCount }) { preset in
                    PresetRow(preset: preset) {
                        applyPreset(preset)
                    }
                    .contextMenu {
                        Button(action: { showingEditPreset = preset }) {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive, action: { deletePreset(preset) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadPresets() {
        do {
            presets = try presetStorage.loadPresets()
        } catch {
            errorMessage = "Failed to load presets: \(error.localizedDescription)"
        }
    }

    private func applyPreset(_ preset: FilterPreset) {
        // Apply all filter settings from preset
        viewModel.showArchived = preset.showArchived
        viewModel.showOnlyOverdue = preset.showOnlyOverdue
        viewModel.showOnlyActive = preset.showOnlyActive
        viewModel.selectedPriorities = preset.selectedPriorities

        // Apply search scope
        switch preset.searchScope {
        case "both": viewModel.searchScope = .both
        case "title": viewModel.searchScope = .title
        case "description": viewModel.searchScope = .description
        default: viewModel.searchScope = .both
        }

        // Apply sort option
        switch preset.sortOption {
        case "rank": viewModel.sortOption = .rank
        case "priority": viewModel.sortOption = .priority
        case "dueDate": viewModel.sortOption = .dueDate
        case "createdDate": viewModel.sortOption = .createdDate
        case "title": viewModel.sortOption = .title
        default: viewModel.sortOption = .rank
        }

        // Apply date filter
        if let filterType = preset.dateFilterType {
            let type: DateFilter.DateFilterType = filterType == "created" ? .created : .dueDate

            let startDate: Date? = preset.dateFilterStartDays.map {
                Calendar.current.date(byAdding: .day, value: -$0, to: Date())
            }

            let endDate: Date? = preset.dateFilterEndDays.map {
                Calendar.current.date(byAdding: .day, value: -$0, to: Date())
            }

            viewModel.dateFilter = DateFilter(
                type: type,
                startDate: startDate,
                endDate: endDate
            )
        } else {
            viewModel.dateFilter = nil
        }

        // Increment usage count
        try? presetStorage.incrementUsageCount(for: preset.id)

        // Haptic feedback
        HapticManager.shared.selectionChanged()

        // Close sheet
        dismiss()
    }

    private func deletePreset(_ preset: FilterPreset) {
        do {
            try presetStorage.deletePreset(preset)
            loadPresets()
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Quick Preset Card

struct QuickPresetCard: View {
    let preset: FilterPreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: preset.color))

                Text(preset.name)
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextPrimary)
                    .lineLimit(1)
            }
            .frame(width: 80, height: 80)
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder(color: Color(hex: preset.color).opacity(0.5))
        }
    }
}

// MARK: - Preset Row

struct PresetRow: View {
    let preset: FilterPreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: .matrixSpacingMedium) {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .foregroundColor(Color(hex: preset.color))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.matrixBodyBold)
                            .foregroundColor(.matrixTextPrimary)

                        if preset.usageCount > 0 {
                            Text("(\(preset.usageCount))")
                                .font(.matrixCaption)
                                .foregroundColor(.matrixTextSecondary)
                        }
                    }

                    Text(preset.description)
                        .font(.matrixCaption)
                        .foregroundColor(.matrixTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.matrixTextSecondary)
            }
            .padding()
            .background(Color.matrixBackgroundSecondary)
            .cornerRadius(.matrixCornerRadius)
            .matrixBorder()
        }
    }
}

// MARK: - Create/Edit Preset View

struct CreatePresetView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    let onSave: (FilterPreset) -> Void

    @State private var name = ""
    @State private var selectedIcon = "line.3.horizontal.decrease.circle"
    @State private var selectedColor = "00FFB8"

    private let icons = [
        "line.3.horizontal.decrease.circle",
        "star.fill",
        "flame.fill",
        "bolt.fill",
        "calendar",
        "clock.fill",
        "flag.fill",
        "bookmark.fill"
    ]

    private let colors = [
        "00FFB8", // Neon green
        "FFC833", // Amber
        "FF4444", // Red
        "FF8800", // Orange
        "00AAFF", // Blue
        "B300FF"  // Purple
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                Form {
                    Section("Preset Name") {
                        TextField("e.g., Morning Review", text: $name)
                            .font(.matrixBody)
                            .foregroundColor(.matrixTextPrimary)
                    }

                    Section("Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                            ForEach(icons, id: \.self) { icon in
                                IconOption(
                                    icon: icon,
                                    isSelected: selectedIcon == icon,
                                    color: Color(hex: selectedColor)
                                ) {
                                    selectedIcon = icon
                                }
                            }
                        }
                    }

                    Section("Color") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                            ForEach(colors, id: \.self) { color in
                                ColorOption(
                                    color: color,
                                    isSelected: selectedColor == color
                                ) {
                                    selectedColor = color
                                }
                            }
                        }
                    }

                    Section("Current Filters") {
                        Text("This preset will save your current filter settings")
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Preset")
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
                        savePreset()
                    }
                    .foregroundColor(.matrixNeon)
                    .disabled(name.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func savePreset() {
        let preset = FilterPreset(
            name: name,
            icon: selectedIcon,
            color: selectedColor,
            showArchived: viewModel.showArchived,
            showOnlyOverdue: viewModel.showOnlyOverdue,
            showOnlyActive: viewModel.showOnlyActive,
            selectedPriorities: viewModel.selectedPriorities,
            searchScope: viewModel.searchScope.rawValue.lowercased(),
            sortOption: viewModel.sortOption.rawValue.lowercased()
        )

        onSave(preset)
        dismiss()
    }
}

struct EditPresetView: View {
    let preset: FilterPreset
    let onSave: (FilterPreset) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: String

    init(preset: FilterPreset, onSave: @escaping (FilterPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _name = State(initialValue: preset.name)
        _selectedIcon = State(initialValue: preset.icon)
        _selectedColor = State(initialValue: preset.color)
    }

    var body: some View {
        // Same as CreatePresetView but for editing
        Text("Edit Preset")
    }
}

struct IconOption: View {
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .matrixBackground : color)
                .frame(width: 60, height: 60)
                .background(isSelected ? color : Color.matrixBackgroundSecondary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color, lineWidth: isSelected ? 3 : 1)
                )
        }
    }
}

struct ColorOption: View {
    let color: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color.matrixNeon, lineWidth: isSelected ? 3 : 0)
                )
        }
    }
}
