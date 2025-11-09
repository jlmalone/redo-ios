import Foundation

/// Immutable event in the change log (event sourcing node)
public struct ChangeLogEntry: Identifiable, Codable, Equatable {
    // MARK: - Core Properties

    public let id: String                  // "sha256:<64 hex chars>"
    public let version: Int                // MUST be 1
    public let parents: [String]           // Parent change IDs (DAG structure)
    public let timestamp: LogicalTimestamp
    public let author: AuthorInfo
    public let action: ChangeAction
    public let taskId: String?
    public let data: ChangeData
    public let signature: String?          // Ed25519 signature (128 hex chars)

    // MARK: - Initialization

    public init(
        id: String,
        version: Int = 1,
        parents: [String],
        timestamp: LogicalTimestamp,
        author: AuthorInfo,
        action: ChangeAction,
        taskId: String?,
        data: ChangeData,
        signature: String? = nil
    ) {
        self.id = id
        self.version = version
        self.parents = parents
        self.timestamp = timestamp
        self.author = author
        self.action = action
        self.taskId = taskId
        self.data = data
        self.signature = signature
    }
}

// MARK: - Logical Timestamp

/// Hybrid logical clock (Lamport + wall clock)
public struct LogicalTimestamp: Codable, Equatable {
    public let lamport: Int                // Causal ordering counter
    public let wall: String                // ISO 8601 timestamp

    public init(lamport: Int, wall: String) {
        self.lamport = lamport
        self.wall = wall
    }

    public init(lamport: Int, wallDate: Date) {
        self.lamport = lamport
        self.wall = ISO8601DateFormatter().string(from: wallDate)
    }

    public var wallDate: Date? {
        ISO8601DateFormatter().date(from: wall)
    }
}

// MARK: - Author Info

/// Identity information for change author
public struct AuthorInfo: Codable, Equatable {
    public let userId: String              // First 32 chars of Ed25519 public key
    public let deviceId: String
    public let name: String?
    public let publicKey: String?          // Ed25519 public key (64 hex chars)

    public init(
        userId: String,
        deviceId: String,
        name: String? = nil,
        publicKey: String? = nil
    ) {
        self.userId = userId
        self.deviceId = deviceId
        self.name = name
        self.publicKey = publicKey
    }
}

// MARK: - Change Action

/// Type of change being recorded
public enum ChangeAction: String, Codable, CaseIterable {
    case create = "CREATE"
    case update = "UPDATE"
    case createTodo = "CREATE_TODO"
    case completeTodo = "COMPLETE_TODO"
    case snooze = "SNOOZE"
    case archive = "ARCHIVE"
    case unarchive = "UNARCHIVE"
    case delete = "DELETE"
}

// MARK: - Change Data

/// Flexible payload for change data
public struct ChangeData: Codable, Equatable {
    public let fields: [String: AnyCodable]

    public init(fields: [String: AnyCodable]) {
        self.fields = fields
    }

    public init(dictionary: [String: Any]) {
        self.fields = dictionary.mapValues { AnyCodable($0) }
    }
}

// MARK: - AnyCodable Wrapper

/// Type-erased codable wrapper for flexible JSON encoding
public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported type"
                )
            )
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case let (l as Bool, r as Bool): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as String, r as String): return l == r
        default: return false
        }
    }

    // MARK: - Convenience Accessors

    public var stringValue: String? {
        value as? String
    }

    public var intValue: Int? {
        value as? Int
    }

    public var doubleValue: Double? {
        value as? Double
    }

    public var boolValue: Bool? {
        value as? Bool
    }

    public var arrayValue: [Any]? {
        value as? [Any]
    }

    public var dictionaryValue: [String: Any]? {
        value as? [String: Any]
    }
}
