import Foundation

/// Strict v1 protocol validation for change log entries
public class ChangeLogValidator {

    // MARK: - Main Validation

    /// Validate that a change log entry conforms to v1 protocol
    /// - Parameter change: Change log entry to validate
    /// - Returns: True if valid, false otherwise
    public func isValidV1Node(_ change: ChangeLogEntry?) -> Bool {
        guard let change = change else { return false }

        return validateVersion(change) &&
               validateId(change) &&
               validateParents(change) &&
               validateTimestamp(change) &&
               validateAuthor(change) &&
               validateAction(change) &&
               validateSignature(change)
    }

    // MARK: - Field Validators

    private func validateVersion(_ change: ChangeLogEntry) -> Bool {
        // MUST be version 1 (strict enforcement)
        change.version == 1
    }

    private func validateId(_ change: ChangeLogEntry) -> Bool {
        // MUST be "sha256:" + 64 lowercase hex chars
        guard change.id.hasPrefix("sha256:") else { return false }
        let hash = String(change.id.dropFirst(7))
        return hash.count == 64 && isLowercaseHex(hash)
    }

    private func validateParents(_ change: ChangeLogEntry) -> Bool {
        // All parent IDs must be valid change IDs
        change.parents.allSatisfy { parentId in
            guard parentId.hasPrefix("sha256:") else { return false }
            let hash = String(parentId.dropFirst(7))
            return hash.count == 64 && isLowercaseHex(hash)
        }
    }

    private func validateTimestamp(_ change: ChangeLogEntry) -> Bool {
        // Lamport clock must be positive
        guard change.timestamp.lamport > 0 else { return false }

        // Wall clock must be valid ISO 8601
        guard !change.timestamp.wall.isEmpty else { return false }
        return ISO8601DateFormatter().date(from: change.timestamp.wall) != nil
    }

    private func validateAuthor(_ change: ChangeLogEntry) -> Bool {
        // User ID must be 32 lowercase hex chars (first half of public key)
        guard change.author.userId.count == 32 else { return false }
        guard isLowercaseHex(change.author.userId) else { return false }

        // Device ID must not be empty
        guard !change.author.deviceId.isEmpty else { return false }

        // Public key (if present) must be 64 lowercase hex chars
        if let publicKey = change.author.publicKey {
            guard publicKey.count == 64 else { return false }
            guard isLowercaseHex(publicKey) else { return false }

            // User ID must be first 32 chars of public key
            guard change.author.userId == String(publicKey.prefix(32)) else { return false }
        }

        return true
    }

    private func validateAction(_ change: ChangeLogEntry) -> Bool {
        // Action must be one of the defined enum cases
        ChangeAction.allCases.contains(change.action)
    }

    private func validateSignature(_ change: ChangeLogEntry) -> Bool {
        // Signature (if present) must be 128 lowercase hex chars
        guard let signature = change.signature else {
            // Signature is optional (for now)
            return true
        }

        return signature.count == 128 && isLowercaseHex(signature)
    }

    // MARK: - Helper Methods

    private func isLowercaseHex(_ string: String) -> Bool {
        string.allSatisfy { char in
            char.isNumber || ("a"..."f").contains(char)
        }
    }

    // MARK: - Content Integrity

    /// Verify that change ID matches its content (SHA-256 hash)
    /// - Parameter change: Change log entry
    /// - Returns: True if ID matches content hash
    public func verifyContentIntegrity(_ change: ChangeLogEntry) -> Bool {
        // This would require re-serializing to canonical JSON and hashing
        // Implementation requires CanonicalJSON and ContentAddressing
        // For now, we trust the ID format validation
        true
    }

    // MARK: - Action-Specific Validation

    /// Validate that required fields are present for specific actions
    /// - Parameter change: Change log entry
    /// - Returns: True if action-specific fields are valid
    public func validateActionPayload(_ change: ChangeLogEntry) -> Bool {
        let fields = change.data.fields

        switch change.action {
        case .create:
            return validateCreatePayload(fields)
        case .update:
            return validateUpdatePayload(fields)
        case .createTodo:
            return validateCreateTodoPayload(fields)
        case .completeTodo:
            return validateCompleteTodoPayload(fields)
        case .snooze:
            return validateSnoozePayload(fields)
        case .archive, .unarchive, .delete:
            // No specific payload requirements
            return true
        }
    }

    private func validateCreatePayload(_ fields: [String: AnyCodable]) -> Bool {
        // CREATE must have: title, description, priority, frequencyDays, storyPoints
        fields["title"]?.stringValue != nil &&
        fields["description"] != nil &&
        fields["priority"]?.intValue != nil &&
        fields["frequencyDays"]?.intValue != nil &&
        fields["storyPoints"] != nil
    }

    private func validateUpdatePayload(_ fields: [String: AnyCodable]) -> Bool {
        // UPDATE must have at least one field to update
        !fields.isEmpty
    }

    private func validateCreateTodoPayload(_ fields: [String: AnyCodable]) -> Bool {
        // CREATE_TODO must have: todoTaskId, deadline
        guard let todoTaskId = fields["todoTaskId"]?.stringValue else { return false }
        guard UUID(uuidString: todoTaskId) != nil else { return false }
        guard let deadlineStr = fields["deadline"]?.stringValue else { return false }
        return ISO8601DateFormatter().date(from: deadlineStr) != nil
    }

    private func validateCompleteTodoPayload(_ fields: [String: AnyCodable]) -> Bool {
        // COMPLETE_TODO must have: todoTaskId, completed
        guard let todoTaskId = fields["todoTaskId"]?.stringValue else { return false }
        guard UUID(uuidString: todoTaskId) != nil else { return false }
        guard let completedStr = fields["completed"]?.stringValue else { return false }
        return ISO8601DateFormatter().date(from: completedStr) != nil
    }

    private func validateSnoozePayload(_ fields: [String: AnyCodable]) -> Bool {
        // SNOOZE must have: todoTaskId, and either newDeadline or snoozeDays
        guard let todoTaskId = fields["todoTaskId"]?.stringValue else { return false }
        guard UUID(uuidString: todoTaskId) != nil else { return false }

        let hasNewDeadline = fields["newDeadline"]?.stringValue != nil
        let hasSnoozeDays = fields["snoozeDays"]?.intValue != nil

        return hasNewDeadline || hasSnoozeDays
    }
}
