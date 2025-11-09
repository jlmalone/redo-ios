import Foundation

/// File-based storage for change log entries (like localStorage in web app)
public class ChangeLogStorage {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let fileName = "redo_changes.json"
    private let userDefaults = UserDefaults.standard

    private var fileURL: URL {
        get throws {
            try fileManager
                .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(fileName)
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Get all changes for a user
    /// - Parameter userId: User ID (first 32 chars of public key)
    /// - Returns: Array of change log entries
    public func getAllChanges(userId: String) throws -> [ChangeLogEntry] {
        let allChanges = try loadChanges()

        // Filter by author userId
        return allChanges.filter { $0.author.userId == userId }
    }

    /// Get all changes (all users)
    /// - Returns: Array of all change log entries
    public func getAllChanges() throws -> [ChangeLogEntry] {
        try loadChanges()
    }

    /// Save new changes (append to existing)
    /// - Parameters:
    ///   - userId: User ID
    ///   - newChanges: New changes to append
    /// - Returns: True if successful
    @discardableResult
    public func saveChanges(userId: String, newChanges: [ChangeLogEntry]) throws -> Bool {
        var allChanges = try loadChanges()

        // Deduplicate by ID
        let existingIds = Set(allChanges.map { $0.id })
        let uniqueNewChanges = newChanges.filter { !existingIds.contains($0.id) }

        // Append new changes
        allChanges.append(contentsOf: uniqueNewChanges)

        // Save to file
        try saveChanges(allChanges)

        return true
    }

    /// Get changes after a specific change ID
    /// - Parameters:
    ///   - userId: User ID
    ///   - afterId: Change ID to start after
    /// - Returns: Array of changes after the specified ID
    public func getChangesAfter(userId: String, afterId: String) throws -> [ChangeLogEntry] {
        let allChanges = try getAllChanges(userId: userId)

        // Sort by Lamport clock
        let sorted = allChanges.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

        // Find index of afterId
        guard let afterIndex = sorted.firstIndex(where: { $0.id == afterId }) else {
            // If afterId not found, return all changes
            return sorted
        }

        // Return changes after afterId
        return Array(sorted.dropFirst(afterIndex + 1))
    }

    /// Delete all changes for a user
    /// - Parameter userId: User ID
    /// - Returns: True if successful
    @discardableResult
    public func deleteAllChanges(userId: String) throws -> Bool {
        var allChanges = try loadChanges()

        // Remove changes for this user
        allChanges.removeAll { $0.author.userId == userId }

        // Save updated list
        try saveChanges(allChanges)

        return true
    }

    /// Delete all changes (all users)
    /// - Returns: True if successful
    @discardableResult
    public func deleteAllChanges() throws -> Bool {
        let url = try fileURL

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        return true
    }

    /// Get storage statistics
    /// - Returns: Dictionary of statistics
    public func getStats() throws -> [String: Any] {
        let allChanges = try loadChanges()
        let url = try fileURL

        var stats: [String: Any] = [
            "totalChanges": allChanges.count,
            "fileSize": 0,
            "lastModified": Date()
        ]

        if let attributes = try? fileManager.attributesOfItem(atPath: url.path) {
            stats["fileSize"] = attributes[.size] as? Int64 ?? 0
            stats["lastModified"] = attributes[.modificationDate] as? Date ?? Date()
        }

        // Count changes by user
        let userCounts = Dictionary(grouping: allChanges, by: { $0.author.userId })
            .mapValues { $0.count }
        stats["changesByUser"] = userCounts

        return stats
    }

    // MARK: - Private Helpers

    private func loadChanges() throws -> [ChangeLogEntry] {
        let url = try fileURL

        // If file doesn't exist, return empty array
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)

        // If file is empty, return empty array
        guard !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        return try decoder.decode([ChangeLogEntry].self, from: data)
    }

    private func saveChanges(_ changes: [ChangeLogEntry]) throws {
        let url = try fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(changes)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Export/Import

    /// Export changes to JSON string
    /// - Returns: JSON string of all changes
    public func exportToJSON() throws -> String {
        let allChanges = try loadChanges()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(allChanges)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw StorageError.exportFailed
        }

        return jsonString
    }

    /// Import changes from JSON string
    /// - Parameter jsonString: JSON string of changes
    /// - Returns: Number of changes imported
    @discardableResult
    public func importFromJSON(_ jsonString: String) throws -> Int {
        guard let data = jsonString.data(using: .utf8) else {
            throw StorageError.importFailed
        }

        let decoder = JSONDecoder()
        let importedChanges = try decoder.decode([ChangeLogEntry].self, from: data)

        var allChanges = try loadChanges()

        // Deduplicate
        let existingIds = Set(allChanges.map { $0.id })
        let uniqueChanges = importedChanges.filter { !existingIds.contains($0.id) }

        // Append and save
        allChanges.append(contentsOf: uniqueChanges)
        try saveChanges(allChanges)

        return uniqueChanges.count
    }
}

// MARK: - Errors

public enum StorageError: Error, LocalizedError {
    case fileNotFound
    case exportFailed
    case importFailed
    case corruptedData

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Change log file not found"
        case .exportFailed:
            return "Failed to export changes to JSON"
        case .importFailed:
            return "Failed to import changes from JSON"
        case .corruptedData:
            return "Change log data is corrupted"
        }
    }
}
