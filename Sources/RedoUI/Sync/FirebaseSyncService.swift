import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Firebase cloud sync service (matches web app architecture)
public class FirebaseSyncService {

    // MARK: - Properties

    private let db = Firestore.firestore()
    private let userId: String          // Google OAuth ID (NOT crypto userId)
    private let deviceId: String
    private var listener: ListenerRegistration?

    // MARK: - Initialization

    public init(userId: String, deviceId: String) {
        self.userId = userId
        self.deviceId = deviceId
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Sync Operations

    /// Bidirectional sync with Firebase
    /// - Parameter localChanges: Local changes to push
    /// - Returns: Sync response with acknowledged and missing changes
    public func syncChanges(localChanges: [ChangeLogEntry]) async throws -> SyncResponse {
        // 1. Push local changes to Firebase
        try await pushChanges(localChanges)

        // 2. Pull remote changes from Firebase
        let remoteChanges = try await pullChanges()

        // 3. Find changes we don't have locally
        let localIds = Set(localChanges.map { $0.id })
        let missingChanges = remoteChanges.filter { !localIds.contains($0.id) }

        return SyncResponse(
            acknowledgedChangeIds: localChanges.map { $0.id },
            missingChanges: missingChanges,
            serverLastKnownIds: ["firebase": remoteChanges.last?.id ?? ""]
        )
    }

    // MARK: - Push Changes

    private func pushChanges(_ changes: [ChangeLogEntry]) async throws {
        guard !changes.isEmpty else { return }

        let batch = db.batch()
        var ownedNodeIds: [String] = []

        for change in changes {
            // Validate change before pushing
            let validator = ChangeLogValidator()
            guard validator.isValidV1Node(change) else {
                print("⚠️ Skipping invalid change: \(change.id)")
                continue
            }

            // CRITICAL: Use global nodes collection (not per-user subcollection)
            // This matches current web/Android architecture
            let nodeRef = db.collection("nodes").document(change.id)

            let nodeData: [String: Any] = [
                "id": change.id,
                "version": change.version,
                "parents": change.parents,
                "timestamp": [
                    "lamport": change.timestamp.lamport,
                    "wall": change.timestamp.wall
                ],
                "author": [
                    "userId": change.author.userId,  // Crypto userId (first 32 of public key)
                    "deviceId": change.author.deviceId,
                    "name": change.author.name ?? "",
                    "publicKey": change.author.publicKey ?? ""
                ],
                "action": change.action.rawValue,
                "taskId": change.taskId ?? "",
                "data": encodeChangeData(change.data),
                "signature": change.signature ?? "",
                "accessList": [userId],  // Google OAuth ID for access control
                "createdAt": FieldValue.serverTimestamp()
            ]

            batch.setData(nodeData, forDocument: nodeRef, merge: true)
            ownedNodeIds.append(change.id)
        }

        // Update user's ownedNodes array
        // CRITICAL: Use Google OAuth ID for user document path
        let userRef = db.collection("users").document(userId)
        batch.setData([
            "ownedNodes": FieldValue.arrayUnion(ownedNodeIds)
        ], forDocument: userRef, merge: true)

        try await batch.commit()
    }

    // MARK: - Pull Changes

    private func pullChanges() async throws -> [ChangeLogEntry] {
        // Get user's ownedNodes array
        let userDoc = try await db.collection("users").document(userId).getDocument()

        guard let data = userDoc.data(),
              let ownedNodes = data["ownedNodes"] as? [String] else {
            return []
        }

        guard !ownedNodes.isEmpty else {
            return []
        }

        var allChanges: [ChangeLogEntry] = []

        // Firebase limit: 10 items per 'in' query, so batch into chunks
        for batch in ownedNodes.chunked(into: 10) {
            let snapshot = try await db.collection("nodes")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()

            for document in snapshot.documents {
                if let change = parseChangeLogEntry(from: document.data()) {
                    allChanges.append(change)
                }
            }
        }

        return allChanges
    }

    // MARK: - Real-Time Sync

    /// Start real-time sync listener
    /// - Parameter onChange: Callback when changes are detected
    public func startRealtimeSync(onChange: @escaping ([ChangeLogEntry]) -> Void) {
        // Listen to changes in nodes collection where accessList contains userId
        listener = db.collection("nodes")
            .whereField("accessList", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Firestore listener error: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                let changes = documents.compactMap { self.parseChangeLogEntry(from: $0.data()) }
                onChange(changes)
            }
    }

    /// Stop real-time sync listener
    public func stopRealtimeSync() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Helpers

    private func parseChangeLogEntry(from data: [String: Any]) -> ChangeLogEntry? {
        guard let id = data["id"] as? String,
              let version = data["version"] as? Int,
              let parents = data["parents"] as? [String],
              let timestampData = data["timestamp"] as? [String: Any],
              let lamport = timestampData["lamport"] as? Int,
              let wall = timestampData["wall"] as? String,
              let authorData = data["author"] as? [String: Any],
              let authorUserId = authorData["userId"] as? String,
              let authorDeviceId = authorData["deviceId"] as? String,
              let actionStr = data["action"] as? String,
              let action = ChangeAction(rawValue: actionStr),
              let dataFields = data["data"] as? [String: Any] else {
            return nil
        }

        let timestamp = LogicalTimestamp(lamport: lamport, wall: wall)
        let author = AuthorInfo(
            userId: authorUserId,
            deviceId: authorDeviceId,
            name: authorData["name"] as? String,
            publicKey: authorData["publicKey"] as? String
        )
        let changeData = ChangeData(dictionary: dataFields)
        let signature = data["signature"] as? String
        let taskId = data["taskId"] as? String

        return ChangeLogEntry(
            id: id,
            version: version,
            parents: parents,
            timestamp: timestamp,
            author: author,
            action: action,
            taskId: taskId,
            data: changeData,
            signature: signature
        )
    }

    private func encodeChangeData(_ data: ChangeData) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in data.fields {
            result[key] = encodeAnyCodable(value)
        }

        return result
    }

    private func encodeAnyCodable(_ value: AnyCodable) -> Any {
        switch value.value {
        case let string as String:
            return string
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let bool as Bool:
            return bool
        case let array as [Any]:
            return array.map { AnyCodable($0) }.map { encodeAnyCodable($0) }
        case let dictionary as [String: Any]:
            return dictionary.mapValues { encodeAnyCodable(AnyCodable($0)) }
        case is NSNull:
            return NSNull()
        default:
            return value.value
        }
    }

    // MARK: - Stats

    /// Get sync statistics
    /// - Returns: Dictionary of statistics
    public func getStats() async throws -> [String: Any] {
        let userDoc = try await db.collection("users").document(userId).getDocument()

        var stats: [String: Any] = [
            "userId": userId,
            "deviceId": deviceId
        ]

        if let data = userDoc.data(),
           let ownedNodes = data["ownedNodes"] as? [String] {
            stats["nodeCount"] = ownedNodes.count
        }

        return stats
    }
}

// MARK: - Sync Response

public struct SyncResponse: Codable {
    public let acknowledgedChangeIds: [String]
    public let missingChanges: [ChangeLogEntry]
    public let serverLastKnownIds: [String: String]

    public init(acknowledgedChangeIds: [String], missingChanges: [ChangeLogEntry], serverLastKnownIds: [String: String]) {
        self.acknowledgedChangeIds = acknowledgedChangeIds
        self.missingChanges = missingChanges
        self.serverLastKnownIds = serverLastKnownIds
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Import ChangeLogValidator

import RedoCore
