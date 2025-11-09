import Foundation

/// A saved filter preset that can be quickly applied
public struct FilterPreset: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var color: String  // Hex color code

    // Filter criteria
    public var showArchived: Bool
    public var showOnlyOverdue: Bool
    public var showOnlyActive: Bool
    public var selectedPriorities: Set<Int>
    public var searchScope: String  // "both", "title", "description"
    public var sortOption: String  // "rank", "priority", "dueDate", "createdDate", "title"
    public var dateFilterType: String?  // "created", "dueDate", or nil
    public var dateFilterStartDays: Int?  // Days ago from now
    public var dateFilterEndDays: Int?  // Days ago from now (0 = today)

    public var createdAt: Date
    public var usageCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "line.3.horizontal.decrease.circle",
        color: String = "00FFB8",
        showArchived: Bool = false,
        showOnlyOverdue: Bool = false,
        showOnlyActive: Bool = false,
        selectedPriorities: Set<Int> = [],
        searchScope: String = "both",
        sortOption: String = "rank",
        dateFilterType: String? = nil,
        dateFilterStartDays: Int? = nil,
        dateFilterEndDays: Int? = nil,
        createdAt: Date = Date(),
        usageCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.showArchived = showArchived
        self.showOnlyOverdue = showOnlyOverdue
        self.showOnlyActive = showOnlyActive
        self.selectedPriorities = selectedPriorities
        self.searchScope = searchScope
        self.sortOption = sortOption
        self.dateFilterType = dateFilterType
        self.dateFilterStartDays = dateFilterStartDays
        self.dateFilterEndDays = dateFilterEndDays
        self.createdAt = createdAt
        self.usageCount = usageCount
    }

    // MARK: - Computed Properties

    public var isDefault: Bool {
        return DefaultFilterPresets.isDefault(id: id)
    }

    public var description: String {
        var parts: [String] = []

        if showArchived { parts.append("Archived") }
        if showOnlyOverdue { parts.append("Overdue") }
        if showOnlyActive { parts.append("Active") }
        if !selectedPriorities.isEmpty {
            let priorities = selectedPriorities.sorted().map { String($0) }.joined(separator: ",")
            parts.append("Priority \(priorities)")
        }
        if sortOption != "rank" {
            parts.append("Sort: \(sortOption)")
        }

        return parts.isEmpty ? "All tasks" : parts.joined(separator: " • ")
    }
}

// MARK: - Default Presets

public struct DefaultFilterPresets {
    public static let all = FilterPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "All Tasks",
        icon: "list.bullet",
        color: "00FFB8",
        showArchived: false,
        showOnlyOverdue: false,
        showOnlyActive: false,
        selectedPriorities: [],
        searchScope: "both",
        sortOption: "rank"
    )

    public static let today = FilterPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Today",
        icon: "calendar",
        color: "FFC833",
        showArchived: false,
        showOnlyOverdue: false,
        showOnlyActive: true,
        selectedPriorities: [],
        searchScope: "both",
        sortOption: "rank",
        dateFilterType: "dueDate",
        dateFilterStartDays: 0,
        dateFilterEndDays: 0
    )

    public static let urgent = FilterPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Urgent",
        icon: "exclamationmark.triangle",
        color: "FF4444",
        showArchived: false,
        showOnlyOverdue: true,
        showOnlyActive: true,
        selectedPriorities: [4, 5],
        searchScope: "both",
        sortOption: "dueDate"
    )

    public static let highPriority = FilterPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "High Priority",
        icon: "star.fill",
        color: "FF8800",
        showArchived: false,
        showOnlyOverdue: false,
        showOnlyActive: true,
        selectedPriorities: [4, 5],
        searchScope: "both",
        sortOption: "priority"
    )

    public static let thisWeek = FilterPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "This Week",
        icon: "calendar.badge.clock",
        color: "00AAFF",
        showArchived: false,
        showOnlyOverdue: false,
        showOnlyActive: true,
        selectedPriorities: [],
        searchScope: "both",
        sortOption: "dueDate",
        dateFilterType: "dueDate",
        dateFilterStartDays: 0,
        dateFilterEndDays: -7  // Negative for future dates
    )

    public static let defaults: [FilterPreset] = [
        all,
        today,
        urgent,
        highPriority,
        thisWeek
    ]

    public static func isDefault(id: UUID) -> Bool {
        return defaults.contains { $0.id == id }
    }
}

// MARK: - Filter Preset Storage

public class FilterPresetStorage {
    private let userDefaults: UserDefaults
    private let key = "filter_presets"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - CRUD Operations

    public func loadPresets() throws -> [FilterPreset] {
        guard let data = userDefaults.data(forKey: key) else {
            // Return defaults if no saved presets
            return DefaultFilterPresets.defaults
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let savedPresets = try decoder.decode([FilterPreset].self, from: data)

        // Merge defaults with saved (defaults always present)
        var allPresets = DefaultFilterPresets.defaults

        // Add custom presets
        allPresets.append(contentsOf: savedPresets.filter { !$0.isDefault })

        return allPresets
    }

    public func savePreset(_ preset: FilterPreset) throws {
        var presets = try loadPresets()

        // Don't allow saving over defaults
        if preset.isDefault {
            throw FilterPresetError.cannotModifyDefault
        }

        // Update existing or append new
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }

        try savePresets(presets)
    }

    public func deletePreset(_ preset: FilterPreset) throws {
        if preset.isDefault {
            throw FilterPresetError.cannotModifyDefault
        }

        var presets = try loadPresets()
        presets.removeAll { $0.id == preset.id }
        try savePresets(presets)
    }

    public func incrementUsageCount(for presetId: UUID) throws {
        var presets = try loadPresets()

        guard let index = presets.firstIndex(where: { $0.id == presetId }) else {
            return
        }

        presets[index].usageCount += 1
        try savePresets(presets)
    }

    // MARK: - Private Helpers

    private func savePresets(_ presets: [FilterPreset]) throws {
        // Filter out defaults (they're always loaded fresh)
        let customPresets = presets.filter { !$0.isDefault }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(customPresets)
        userDefaults.set(data, forKey: key)
    }
}

// MARK: - Errors

public enum FilterPresetError: Error {
    case cannotModifyDefault
    case presetNotFound
    case invalidPreset

    public var localizedDescription: String {
        switch self {
        case .cannotModifyDefault:
            return "Cannot modify or delete default presets"
        case .presetNotFound:
            return "Filter preset not found"
        case .invalidPreset:
            return "Invalid filter preset configuration"
        }
    }
}
