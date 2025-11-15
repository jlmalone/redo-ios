# Redo iOS - Database Schema Documentation

**Version:** 1.0.0
**Last Updated:** January 2025
**Author:** Redo iOS Development Team
**Architecture:** Event Sourcing + Local-First + Cross-Platform Sync

---

## Table of Contents

1. [Overview](#overview)
2. [Storage Architecture](#storage-architecture)
3. [Database Schemas](#database-schemas)
   - [Local File Storage](#local-file-storage)
   - [Firebase Firestore](#firebase-firestore)
   - [iOS Keychain](#ios-keychain)
4. [Entity-Relationship Diagrams](#entity-relationship-diagrams)
5. [Data Models](#data-models)
6. [Sample Queries](#sample-queries)
7. [Migration Documentation](#migration-documentation)
8. [Performance Documentation](#performance-documentation)
9. [Integration Documentation](#integration-documentation)
10. [Security & Privacy](#security--privacy)

---

## Overview

The Redo iOS application uses a **hybrid event-sourced architecture** with three distinct storage layers:

1. **Local File Storage** - Primary source of truth (JSON file)
2. **Firebase Firestore** - Cloud sync and multi-device support
3. **iOS Keychain** - Secure cryptographic key storage

This architecture follows the **local-first** paradigm where all operations are instant and work offline, with background sync to the cloud.

### Key Principles

- **Event Sourcing**: All changes are immutable events stored in a change log
- **Content Addressing**: All change IDs are SHA-256 hashes of canonical JSON
- **State Reconstruction**: Current state is always derived by replaying the change log
- **No Caching**: Never cache task state - always reconstruct from events
- **Instant Operations**: All local operations complete in <50ms
- **Background Sync**: Cloud sync happens asynchronously without blocking UI

---

## Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│                   (AppViewModel, Views)                       │
└───────────┬───────────────────────────┬─────────────────────┘
            │                           │
            ▼                           ▼
┌───────────────────────┐   ┌──────────────────────┐
│  StateReconstructor   │   │  FirebaseSyncService │
│  (Event Replay)       │   │  (Background Sync)   │
└───────────┬───────────┘   └──────────┬───────────┘
            │                           │
            ▼                           ▼
┌───────────────────────┐   ┌──────────────────────┐
│  ChangeLogStorage     │   │   Firestore Cloud    │
│  (Local JSON File)    │   │   (Global nodes/)    │
└───────────────────────┘   └──────────────────────┘
            │
            ▼
┌───────────────────────┐
│   Keychain Service    │
│  (Cryptographic Keys) │
└───────────────────────┘
```

### Data Flow

1. **Write Path**: User Action → Create ChangeLogEntry → Sign with Ed25519 → Save to Local Storage → Background Push to Firebase
2. **Read Path**: Load from Local Storage → Validate → Sort by Lamport Clock → Replay Events → Reconstruct State
3. **Sync Path**: Pull from Firebase → Merge with Local → Deduplicate → Reconstruct State

---

## Database Schemas

### Local File Storage

**File Location**: `~/Library/Application Support/{AppID}/Documents/redo_changes.json`
**Format**: JSON Array of ChangeLogEntry objects
**Encoding**: UTF-8
**Serialization**: JSONEncoder with `.sortedKeys` and `.prettyPrinted`

#### Schema

```json
[
  {
    "id": "sha256:abc123...",
    "version": 1,
    "parents": ["sha256:def456..."],
    "timestamp": {
      "lamport": 5,
      "wall": "2025-01-15T10:30:00Z"
    },
    "author": {
      "userId": "abc123...",
      "deviceId": "iPhone-14-Pro",
      "name": "John Doe",
      "publicKey": "abc123def456..."
    },
    "action": "CREATE",
    "taskId": "550e8400-e29b-41d4-a716-446655440000",
    "data": {
      "fields": {
        "title": "Complete project documentation",
        "description": "Write comprehensive docs",
        "privacy": false,
        "storyPoints": 3.0,
        "priority": 4,
        "frequencyDays": 7
      }
    },
    "signature": "abc123def456..."
  }
]
```

#### Field Specifications

| Field | Type | Required | Format | Description |
|-------|------|----------|--------|-------------|
| `id` | String | Yes | `sha256:{64 lowercase hex}` | Content-addressed change ID |
| `version` | Integer | Yes | Must be `1` | Protocol version (v1 only) |
| `parents` | Array[String] | Yes | Array of change IDs | Parent changes (DAG) |
| `timestamp.lamport` | Integer | Yes | > 0 | Lamport logical clock |
| `timestamp.wall` | String | Yes | ISO 8601 | Wall clock timestamp |
| `author.userId` | String | Yes | 32 lowercase hex | First 32 chars of public key |
| `author.deviceId` | String | Yes | Any string | Device identifier |
| `author.name` | String | No | Any string | Human-readable name |
| `author.publicKey` | String | No | 64 lowercase hex | Ed25519 public key |
| `action` | Enum | Yes | See ChangeAction | Type of change |
| `taskId` | String | No | UUID | Task GUID (if applicable) |
| `data.fields` | Object | Yes | Key-value pairs | Action-specific data |
| `signature` | String | No | 128 lowercase hex | Ed25519 signature |

#### ChangeAction Enum

```swift
enum ChangeAction: String {
    case create = "CREATE"
    case update = "UPDATE"
    case createTodo = "CREATE_TODO"
    case completeTodo = "COMPLETE_TODO"
    case snooze = "SNOOZE"
    case archive = "ARCHIVE"
    case unarchive = "UNARCHIVE"
    case delete = "DELETE"
}
```

#### Indexes

**Primary Key**: `id` (unique, content-addressed SHA-256 hash)
**Secondary Indexes**:
- `author.userId` - Filter changes by user
- `timestamp.lamport` - Sort for causal ordering
- `taskId` - Find all changes for a task
- `action` - Filter by action type

#### Constraints

1. **Uniqueness**: No duplicate `id` values (enforced via deduplication on save)
2. **Immutability**: Once written, entries are never modified
3. **Validation**: All entries must pass strict v1 validation before storage
4. **Causality**: Parents must exist before children (enforced by Lamport clock)

#### Storage Operations

**Implemented in**: `Sources/RedoCore/Storage/ChangeLogStorage.swift`

```swift
class ChangeLogStorage {
    // Read operations
    func getAllChanges(userId: String) throws -> [ChangeLogEntry]
    func getAllChanges() throws -> [ChangeLogEntry]
    func getChangesAfter(userId: String, afterId: String) throws -> [ChangeLogEntry]

    // Write operations
    func saveChanges(userId: String, newChanges: [ChangeLogEntry]) throws -> Bool

    // Delete operations
    func deleteAllChanges(userId: String) throws -> Bool
    func deleteAllChanges() throws -> Bool

    // Export/Import
    func exportToJSON() throws -> String
    func importFromJSON(_ jsonString: String) throws -> Int

    // Statistics
    func getStats() throws -> [String: Any]
}
```

---

### Firebase Firestore

**Database Type**: NoSQL Document Database
**Mode**: Production
**Region**: us-central1
**Real-time**: Enabled

#### Collections

##### 1. `nodes/` (Global Collection)

**Purpose**: Store all change log entries with access control
**Path**: `/nodes/{changeId}`
**Document ID**: SHA-256 content hash (e.g., `sha256:abc123...`)

**Schema**:

```typescript
{
  id: string,                    // "sha256:{64 hex}" - matches document ID
  version: number,               // Must be 1
  parents: string[],             // Array of parent change IDs
  timestamp: {
    lamport: number,             // Lamport clock (> 0)
    wall: string                 // ISO 8601 timestamp
  },
  author: {
    userId: string,              // Crypto userId (first 32 of public key)
    deviceId: string,            // Device identifier
    name?: string,               // Optional display name
    publicKey?: string           // Ed25519 public key (64 hex)
  },
  action: string,                // ChangeAction enum value
  taskId?: string,               // UUID of task (if applicable)
  data: {
    [key: string]: any          // Action-specific fields
  },
  signature?: string,            // Ed25519 signature (128 hex)
  accessList: string[],          // Google OAuth IDs with access
  createdAt: Timestamp           // Firestore server timestamp
}
```

**Field Types**:

| Field | Firestore Type | Indexed | Description |
|-------|----------------|---------|-------------|
| `id` | string | Yes (auto) | Document ID |
| `version` | number | No | Protocol version |
| `parents` | array | No | Parent change IDs |
| `timestamp.lamport` | number | Yes | For ordering |
| `timestamp.wall` | string | Yes | For time-based queries |
| `author.userId` | string | Yes | Filter by user |
| `action` | string | Yes | Filter by action |
| `taskId` | string | Yes | Find task changes |
| `accessList` | array | Yes | Security rules |
| `createdAt` | timestamp | Yes | Server timestamp |

**Indexes**:

```
Collection: nodes
Composite Indexes:
  - accessList (ARRAY) + timestamp.lamport (ASC)
  - accessList (ARRAY) + timestamp.wall (DESC)
  - author.userId (ASC) + action (ASC) + timestamp.lamport (ASC)
  - taskId (ASC) + timestamp.lamport (ASC)
```

**Security Rules**:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /nodes/{nodeId} {
      // Users can read nodes they have access to
      allow read: if request.auth != null
                  && request.auth.uid in resource.data.accessList;

      // Users can create nodes with themselves in accessList
      allow create: if request.auth != null
                    && request.auth.uid in request.resource.data.accessList
                    && request.resource.data.version == 1;

      // Nodes are immutable after creation
      allow update, delete: if false;
    }
  }
}
```

##### 2. `users/` Collection

**Purpose**: Track user metadata and owned nodes
**Path**: `/users/{googleOAuthId}`
**Document ID**: Google OAuth subject ID (e.g., `105903...`)

**Schema**:

```typescript
{
  ownedNodes: string[],          // Array of node IDs this user owns
  lastSyncAt?: Timestamp,        // Last sync timestamp
  deviceIds?: string[],          // Registered device IDs
  createdAt?: Timestamp,         // Account creation
  displayName?: string,          // User display name
  email?: string                 // User email
}
```

**Field Types**:

| Field | Firestore Type | Indexed | Description |
|-------|----------------|---------|-------------|
| `ownedNodes` | array | Yes | Node IDs for this user |
| `lastSyncAt` | timestamp | Yes | Last sync time |
| `deviceIds` | array | No | Device identifiers |
| `createdAt` | timestamp | Yes | Account creation |

**Indexes**:

```
Collection: users
Single Field Indexes:
  - ownedNodes (ARRAY)
  - lastSyncAt (DESC)
  - createdAt (DESC)
```

**Security Rules**:

```javascript
match /users/{userId} {
  // Users can read their own document
  allow read: if request.auth != null && request.auth.uid == userId;

  // Users can update their own document
  allow write: if request.auth != null && request.auth.uid == userId;
}
```

#### Firebase Operations

**Implemented in**: `Sources/RedoUI/Sync/FirebaseSyncService.swift`

```swift
class FirebaseSyncService {
    // Sync operations
    func syncChanges(localChanges: [ChangeLogEntry]) async throws -> SyncResponse

    // Push/Pull
    private func pushChanges(_ changes: [ChangeLogEntry]) async throws
    private func pullChanges() async throws -> [ChangeLogEntry]

    // Real-time sync
    func startRealtimeSync(onChange: @escaping ([ChangeLogEntry]) -> Void)
    func stopRealtimeSync()

    // Statistics
    func getStats() async throws -> [String: Any]
}
```

#### Batch Operations

**Firebase Limit**: 10 items per `in` query

**Batching Strategy**:
```swift
// Split ownedNodes into chunks of 10
for batch in ownedNodes.chunked(into: 10) {
    let snapshot = try await db.collection("nodes")
        .whereField(FieldPath.documentID(), in: batch)
        .getDocuments()
    // Process batch...
}
```

---

### iOS Keychain

**Service**: `com.salient.vision.redo`
**Security Level**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
**Storage Class**: `kSecClassGenericPassword`

#### Schema

| Key | Type | Size | Description |
|-----|------|------|-------------|
| `ed25519_private_key` | String | 64 hex chars | Ed25519 private key |
| `ed25519_public_key` | String | 64 hex chars | Ed25519 public key |
| `user_id` | String | 32 hex chars | Crypto user ID (first 32 of public key) |
| `device_id` | String | Variable | Device identifier (UUID or custom) |
| `google_access_token` | String | Variable | Google OAuth access token |
| `firebase_token` | String | Variable | Firebase custom auth token |

#### Keychain Operations

**Implemented in**: `Sources/RedoCore/Storage/KeychainService.swift`

```swift
class KeychainService {
    // Generic operations
    func save(data: Data, forKey key: String) throws
    func save(string: String, forKey key: String) throws
    func load(forKey key: String) throws -> Data?
    func loadString(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
    func exists(forKey key: String) -> Bool
    func deleteAll() throws

    // Redo-specific convenience methods
    func savePrivateKey(_ privateKey: String) throws
    func loadPrivateKey() throws -> String?
    func savePublicKey(_ publicKey: String) throws
    func loadPublicKey() throws -> String?
    func saveUserId(_ userId: String) throws
    func loadUserId() throws -> String?
    func saveDeviceId(_ deviceId: String) throws
    func loadDeviceId() throws -> String?
}
```

#### Security Attributes

```swift
let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.salient.vision.redo",
    kSecAttrAccount: key,
    kSecValueData: data,
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
]
```

**Access Policy**:
- Data encrypted at rest by iOS
- Accessible only when device is unlocked
- Not backed up to iCloud (device-only)
- Persists across app reinstalls
- Deleted when app is uninstalled

---

## Entity-Relationship Diagrams

### Conceptual Model

```
┌─────────────────┐
│   ChangeLogEntry│
│   (Event Node)  │
├─────────────────┤
│ PK: id          │
│    version      │
│    parents[]    │◄────┐
│    timestamp    │     │ Parent-Child
│    author       │     │ Relationship
│    action       │     │ (DAG)
│    taskId       │     │
│    data         │     │
│    signature    │─────┘
└────────┬────────┘
         │
         │ Reconstructs
         │
         ▼
┌─────────────────┐
│    RedoTask     │
│   (Template)    │
├─────────────────┤
│ PK: guid        │
│    userId       │
│    title        │
│    description  │
│    priority     │
│    frequency    │
│    archived     │
└────────┬────────┘
         │
         │ 1:N
         │ Has Many
         ▼
┌─────────────────┐
│    TodoTask     │
│  (Instance)     │
├─────────────────┤
│ PK: guid        │
│ FK: redoParent  │
│    created      │
│    deadline     │
│    completed    │
│    notes        │
└─────────────────┘
```

### Physical Storage Model

```
┌──────────────────────────────────────────────────────────┐
│                    Local File System                     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ redo_changes.json                                  │ │
│  │ ┌────────────────────────────────────────────────┐ │ │
│  │ │ ChangeLogEntry[]                               │ │ │
│  │ │ - Sorted by Lamport clock                      │ │ │
│  │ │ - Deduplicated by ID                           │ │ │
│  │ │ - Immutable append-only                        │ │ │
│  │ └────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                           │
                           │ Sync
                           ▼
┌──────────────────────────────────────────────────────────┐
│                    Firebase Firestore                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Collection: nodes/                                 │ │
│  │ ┌────────────────────────────────────────────────┐ │ │
│  │ │ Document: sha256:abc123...                     │ │ │
│  │ │ - Same schema as ChangeLogEntry                │ │ │
│  │ │ - Additional: accessList[], createdAt          │ │ │
│  │ └────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Collection: users/                                 │ │
│  │ ┌────────────────────────────────────────────────┐ │ │
│  │ │ Document: {googleOAuthId}                      │ │ │
│  │ │ - ownedNodes: [nodeId1, nodeId2, ...]          │ │ │
│  │ │ - lastSyncAt: Timestamp                        │ │ │
│  │ └────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                           │
                           │ References
                           ▼
┌──────────────────────────────────────────────────────────┐
│                      iOS Keychain                        │
│                                                          │
│  Service: com.salient.vision.redo                        │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ed25519_private_key  → String (64 hex)             │ │
│  │ ed25519_public_key   → String (64 hex)             │ │
│  │ user_id              → String (32 hex)             │ │
│  │ device_id            → String (UUID)               │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### Event Sourcing Flow

```
User Action
    │
    ▼
┌─────────────────────┐
│ Create Change Entry │
│ - Generate UUID     │
│ - Increment Lamport │
│ - Add timestamp     │
│ - Set action/data   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Sign with Ed25519   │
│ - Canonical JSON    │
│ - SHA-256 hash      │
│ - Ed25519 signature │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Save to Local File  │
│ - Append to array   │
│ - Deduplicate       │
│ - Write atomically  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Background Sync     │
│ - Push to Firebase  │
│ - Update ownedNodes │
│ - Pull remote       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Reconstruct State   │
│ - Load all changes  │
│ - Sort by Lamport   │
│ - Validate each     │
│ - Replay actions    │
│ - Build tasks       │
└─────────────────────┘
```

---

## Data Models

### ChangeLogEntry

**Definition**: Immutable event in the change log (event sourcing node)
**File**: `Sources/RedoCore/Models/ChangeLogEntry.swift`

```swift
public struct ChangeLogEntry: Identifiable, Codable, Equatable {
    public let id: String                  // "sha256:<64 hex chars>"
    public let version: Int                // MUST be 1
    public let parents: [String]           // Parent change IDs (DAG)
    public let timestamp: LogicalTimestamp
    public let author: AuthorInfo
    public let action: ChangeAction
    public let taskId: String?
    public let data: ChangeData
    public let signature: String?          // Ed25519 signature
}
```

### LogicalTimestamp

**Definition**: Hybrid logical clock (Lamport + wall clock)
**File**: `Sources/RedoCore/Models/ChangeLogEntry.swift:43-62`

```swift
public struct LogicalTimestamp: Codable, Equatable {
    public let lamport: Int                // Causal ordering counter
    public let wall: String                // ISO 8601 timestamp

    public var wallDate: Date?             // Parsed wall clock
}
```

### AuthorInfo

**Definition**: Identity information for change author
**File**: `Sources/RedoCore/Models/ChangeLogEntry.swift:64-84`

```swift
public struct AuthorInfo: Codable, Equatable {
    public let userId: String              // First 32 chars of Ed25519 public key
    public let deviceId: String
    public let name: String?
    public let publicKey: String?          // Ed25519 public key (64 hex)
}
```

### ChangeData

**Definition**: Flexible payload for change data
**File**: `Sources/RedoCore/Models/ChangeLogEntry.swift:100-113`

```swift
public struct ChangeData: Codable, Equatable {
    public let fields: [String: AnyCodable]
}
```

### RedoTask

**Definition**: Recurring task template that generates TodoTask instances
**File**: `Sources/RedoCore/Models/RedoTask.swift`

```swift
public struct RedoTask: Identifiable, Codable, Equatable {
    public let guid: UUID
    public let userId: String              // Crypto userId
    public var title: String
    public var description: String
    public var privacy: Bool               // true = private
    public var storyPoints: Float
    public var priority: Int               // 1-5
    public var frequencyDays: Int          // 0 = one-time, 7 = weekly
    public let created: Date
    public var archived: Bool
    public var lastUpdated: Date?
    public var todoTasks: [TodoTask]
}
```

### TodoTask

**Definition**: Individual work instance created from a RedoTask template
**File**: `Sources/RedoCore/Models/TodoTask.swift`

```swift
public struct TodoTask: Identifiable, Codable, Equatable {
    public let guid: UUID
    public let redoParentGuid: UUID
    public let created: Date
    public var notes: String
    public var deadline: Date
    public var completed: Date?
}
```

---

## Sample Queries

### Local File Storage Queries

#### 1. Get All Changes for Current User

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""
let changes = try storage.getAllChanges(userId: userId)
```

**Time Complexity**: O(n) where n = total changes
**Expected Performance**: <10ms for 1000 changes

#### 2. Get Changes After Specific ID

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""
let afterId = "sha256:abc123..."
let changes = try storage.getChangesAfter(userId: userId, afterId: afterId)
```

**Use Case**: Incremental sync, pagination
**Time Complexity**: O(n log n) due to sorting

#### 3. Save New Changes (with Deduplication)

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""
let newChanges: [ChangeLogEntry] = [/* ... */]
try storage.saveChanges(userId: userId, newChanges: newChanges)
```

**Deduplication**: Automatic by change ID
**Atomic Write**: Uses `.atomic` option

#### 4. Get Storage Statistics

```swift
let storage = ChangeLogStorage()
let stats = try storage.getStats()

// Returns:
// {
//   "totalChanges": 150,
//   "fileSize": 256000,
//   "lastModified": Date(),
//   "changesByUser": {
//     "abc123...": 150
//   }
// }
```

#### 5. Export All Changes to JSON

```swift
let storage = ChangeLogStorage()
let json = try storage.exportToJSON()
// Share via UIActivityViewController or save to Files app
```

#### 6. Import Changes from JSON

```swift
let storage = ChangeLogStorage()
let jsonString = /* ... from file or clipboard ... */
let importedCount = try storage.importFromJSON(jsonString)
print("Imported \(importedCount) new changes")
```

#### 7. Delete All Changes for User

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""
try storage.deleteAllChanges(userId: userId)
```

#### 8. Get Changes for Specific Task

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""
let taskId = "550e8400-e29b-41d4-a716-446655440000"

let allChanges = try storage.getAllChanges(userId: userId)
let taskChanges = allChanges.filter { $0.taskId == taskId }
    .sorted { $0.timestamp.lamport < $1.timestamp.lamport }
```

#### 9. Get Changes by Action Type

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""

let allChanges = try storage.getAllChanges(userId: userId)
let createChanges = allChanges.filter { $0.action == .create }
let completions = allChanges.filter { $0.action == .completeTodo }
```

#### 10. Get Changes in Date Range

```swift
let storage = ChangeLogStorage()
let userId = try keychain.loadUserId() ?? ""
let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

let allChanges = try storage.getAllChanges(userId: userId)
let recentChanges = allChanges.filter { entry in
    guard let wallDate = entry.timestamp.wallDate else { return false }
    return wallDate >= startDate
}
```

---

### Firebase Firestore Queries

#### 11. Sync Local Changes to Firebase

```swift
let sync = FirebaseSyncService(userId: googleOAuthId, deviceId: deviceId)
let storage = ChangeLogStorage()
let localChanges = try storage.getAllChanges(userId: cryptoUserId)

let response = try await sync.syncChanges(localChanges: localChanges)
print("Acknowledged: \(response.acknowledgedChangeIds.count)")
print("Missing: \(response.missingChanges.count)")
```

#### 12. Pull All Remote Changes

```swift
let sync = FirebaseSyncService(userId: googleOAuthId, deviceId: deviceId)
let remoteChanges = try await sync.pullChanges()

// Save to local storage
let storage = ChangeLogStorage()
try storage.saveChanges(userId: cryptoUserId, newChanges: remoteChanges)
```

#### 13. Get Nodes by Access List (Firestore Query)

```firestore
db.collection("nodes")
  .where("accessList", "array-contains", googleOAuthId)
  .orderBy("timestamp.lamport", "ascending")
  .limit(100)
  .get()
```

**Swift Equivalent**:
```swift
let snapshot = try await db.collection("nodes")
    .whereField("accessList", arrayContains: googleOAuthId)
    .order(by: "timestamp.lamport", descending: false)
    .limit(to: 100)
    .getDocuments()
```

#### 14. Get User's Owned Nodes

```swift
let userDoc = try await db.collection("users")
    .document(googleOAuthId)
    .getDocument()

let ownedNodes = userDoc.data()?["ownedNodes"] as? [String] ?? []
```

#### 15. Get Nodes by ID (Batched)

```swift
let ownedNodes: [String] = /* ... */

var allChanges: [ChangeLogEntry] = []
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
```

#### 16. Start Real-Time Sync Listener

```swift
let sync = FirebaseSyncService(userId: googleOAuthId, deviceId: deviceId)

sync.startRealtimeSync { changes in
    // New changes detected
    let storage = ChangeLogStorage()
    try? storage.saveChanges(userId: cryptoUserId, newChanges: changes)

    // Trigger UI refresh
    NotificationCenter.default.post(name: .tasksDidChange, object: nil)
}
```

#### 17. Get Sync Statistics

```swift
let sync = FirebaseSyncService(userId: googleOAuthId, deviceId: deviceId)
let stats = try await sync.getStats()

// Returns:
// {
//   "userId": "105903...",
//   "deviceId": "iPhone-14-Pro",
//   "nodeCount": 150
// }
```

#### 18. Query Nodes by Action Type

```firestore
db.collection("nodes")
  .where("accessList", "array-contains", googleOAuthId)
  .where("action", "==", "CREATE")
  .orderBy("timestamp.lamport", "ascending")
  .get()
```

#### 19. Query Recent Nodes (Last 24 Hours)

```firestore
const yesterday = new Date(Date.now() - 86400000);
db.collection("nodes")
  .where("accessList", "array-contains", googleOAuthId)
  .where("createdAt", ">=", yesterday)
  .orderBy("createdAt", "descending")
  .get()
```

#### 20. Query Nodes for Specific Task

```firestore
db.collection("nodes")
  .where("accessList", "array-contains", googleOAuthId)
  .where("taskId", "==", "550e8400-e29b-41d4-a716-446655440000")
  .orderBy("timestamp.lamport", "ascending")
  .get()
```

---

### iOS Keychain Queries

#### 21. Save Private Key

```swift
let keychain = KeychainService()
let privateKey = "abc123def456..." // 64 hex chars
try keychain.savePrivateKey(privateKey)
```

#### 22. Load Private Key

```swift
let keychain = KeychainService()
if let privateKey = try keychain.loadPrivateKey() {
    print("Private key: \(privateKey)")
} else {
    print("No private key found")
}
```

#### 23. Save Public Key

```swift
let keychain = KeychainService()
let publicKey = "abc123def456..." // 64 hex chars
try keychain.savePublicKey(publicKey)
```

#### 24. Load Public Key

```swift
let keychain = KeychainService()
if let publicKey = try keychain.loadPublicKey() {
    print("Public key: \(publicKey)")
}
```

#### 25. Save and Load User ID

```swift
let keychain = KeychainService()

// Derive from public key
let userId = String(publicKey.prefix(32))
try keychain.saveUserId(userId)

// Load later
let savedUserId = try keychain.loadUserId()
```

#### 26. Save and Load Device ID

```swift
let keychain = KeychainService()
let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
try keychain.saveDeviceId(deviceId)

let savedDeviceId = try keychain.loadDeviceId()
```

#### 27. Check if Key Exists

```swift
let keychain = KeychainService()
if keychain.exists(forKey: "ed25519_private_key") {
    print("Private key already exists")
} else {
    // Generate new keypair
}
```

#### 28. Delete Specific Key

```swift
let keychain = KeychainService()
try keychain.delete(forKey: "ed25519_private_key")
```

#### 29. Delete All Keys (Sign Out)

```swift
let keychain = KeychainService()
try keychain.deleteAll()
```

#### 30. Save Generic Data

```swift
let keychain = KeychainService()
let token = "eyJhbGciOiJSUzI1NiIsImtpZCI6..."
try keychain.save(string: token, forKey: "google_access_token")
```

---

### State Reconstruction Queries

#### 31. Reconstruct All Tasks from Changes

```swift
let storage = ChangeLogStorage()
let reconstructor = StateReconstructor()

let userId = try keychain.loadUserId() ?? ""
let changes = try storage.getAllChanges(userId: userId)
let tasks = try reconstructor.reconstructTasks(from: changes)
```

**Time Complexity**: O(n * m) where n = changes, m = avg changes per task
**Expected Performance**: <100ms for 1000 changes

#### 32. Get Active (Non-Archived) Tasks

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let activeTasks = tasks.filter { !$0.archived }
```

#### 33. Get Tasks with Pending Todos

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let pendingTasks = tasks.filter { $0.hasPendingTodos }
```

#### 34. Get Overdue Tasks

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let overdueTasks = tasks.filter { $0.isOverdue }
```

#### 35. Get Tasks Sorted by Rank (Priority)

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let sortedTasks = tasks.sorted { $0.currentRank() > $1.currentRank() }
```

#### 36. Get Tasks by Priority Level

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let highPriority = tasks.filter { $0.priority >= 4 }
```

#### 37. Get Recurring Tasks

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let recurring = tasks.filter { $0.isRecurring }
```

#### 38. Get One-Time Tasks

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let oneTime = tasks.filter { $0.frequencyDays == 0 }
```

#### 39. Get Tasks by Story Points Range

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let quickTasks = tasks.filter { $0.storyPoints <= 2.0 }
let complexTasks = tasks.filter { $0.storyPoints >= 5.0 }
```

#### 40. Get Tasks by Urgency Status

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let criticalTasks = tasks.filter { $0.urgencyStatus() == .critical }
```

---

### TodoTask Queries

#### 41. Get All Pending Todos Across Tasks

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let allPendingTodos = tasks.flatMap { $0.todoTasks.filter { $0.isPending } }
```

#### 42. Get Completed Todos in Date Range

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

let recentCompletions = tasks.flatMap { task in
    task.todoTasks.filter { todo in
        guard let completed = todo.completed else { return false }
        return completed >= startDate
    }
}
```

#### 43. Get Todos Due Today

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())
let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

let todayTodos = tasks.flatMap { task in
    task.todoTasks.filter { todo in
        todo.isPending &&
        todo.deadline >= today &&
        todo.deadline < tomorrow
    }
}
```

#### 44. Get Todos Due This Week

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

let weekTodos = tasks.flatMap { task in
    task.todoTasks.filter { todo in
        todo.isPending && todo.deadline <= endOfWeek
    }
}
```

#### 45. Get Overdue Todos

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let overdueTodos = tasks.flatMap { task in
    task.todoTasks.filter { $0.isOverdue }
}
```

#### 46. Get Todos Sorted by Deadline

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let allTodos = tasks.flatMap { $0.todoTasks.filter { $0.isPending } }
let sortedByDeadline = allTodos.sorted { $0.deadline < $1.deadline }
```

#### 47. Get Todos Sorted by Rank (Urgency)

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let allTodos = tasks.flatMap { $0.todoTasks.filter { $0.isPending } }
let sortedByRank = allTodos.sorted { $0.rank() > $1.rank() }
```

#### 48. Get Completion Rate for Task

```swift
let task = tasks.first { $0.guid == targetGuid }
let totalTodos = task.todoTasks.count
let completedTodos = task.todoTasks.filter { $0.isCompleted }.count
let completionRate = totalTodos > 0 ? Double(completedTodos) / Double(totalTodos) : 0.0
```

#### 49. Get Average Completion Time

```swift
let completedTodos = tasks.flatMap { task in
    task.todoTasks.filter { $0.isCompleted }
}

let totalCompletionTime = completedTodos.reduce(0.0) { sum, todo in
    guard let completed = todo.completed else { return sum }
    return sum + completed.timeIntervalSince(todo.created)
}

let avgCompletionTime = completedTodos.isEmpty ? 0 :
    totalCompletionTime / Double(completedTodos.count) / 86400.0 // days
```

#### 50. Get Todos with Notes

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let todosWithNotes = tasks.flatMap { task in
    task.todoTasks.filter { !$0.notes.isEmpty }
}
```

---

### Advanced Analytics Queries

#### 51. Get Daily Completion Streak

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let completedTodos = tasks.flatMap { task in
    task.todoTasks.filter { $0.isCompleted }
}.sorted { ($0.completed ?? Date()) > ($1.completed ?? Date()) }

var streak = 0
var currentDate = Date()
let calendar = Calendar.current

for todo in completedTodos {
    guard let completed = todo.completed else { continue }
    let completedDay = calendar.startOfDay(for: completed)
    let currentDay = calendar.startOfDay(for: currentDate)

    if calendar.dateComponents([.day], from: completedDay, to: currentDay).day == 0 {
        streak += 1
        currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
    } else {
        break
    }
}
```

#### 52. Get Completion Rate by Priority

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
var ratesByPriority: [Int: Double] = [:]

for priority in 1...5 {
    let tasksAtPriority = tasks.filter { $0.priority == priority }
    let allTodos = tasksAtPriority.flatMap { $0.todoTasks }
    let completed = allTodos.filter { $0.isCompleted }.count
    let total = allTodos.count

    ratesByPriority[priority] = total > 0 ? Double(completed) / Double(total) : 0.0
}
```

#### 53. Get Most Productive Hours

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let completions = tasks.flatMap { task in
    task.todoTasks.compactMap { $0.completed }
}

var hourCounts: [Int: Int] = [:]
for completion in completions {
    let hour = Calendar.current.component(.hour, from: completion)
    hourCounts[hour, default: 0] += 1
}

let mostProductiveHour = hourCounts.max(by: { $0.value < $1.value })?.key
```

#### 54. Get Task Velocity (Story Points per Week)

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

let recentCompletions = tasks.flatMap { task in
    task.todoTasks.filter { todo in
        guard let completed = todo.completed else { return false }
        return completed >= oneWeekAgo
    }.map { (task, $0) }
}

let totalStoryPoints = recentCompletions.reduce(0.0) { sum, pair in
    sum + pair.0.storyPoints
}
```

#### 55. Get Burndown Data

```swift
let tasks = try reconstructor.reconstructTasks(from: changes)
let pendingStoryPoints = tasks.filter { $0.hasPendingTodos }
    .reduce(0.0) { sum, task in sum + task.storyPoints }

let totalStoryPoints = tasks.reduce(0.0) { sum, task in
    sum + task.storyPoints * Float(task.todoTasks.count)
}

let completedStoryPoints = totalStoryPoints - pendingStoryPoints
let burndownPercentage = totalStoryPoints > 0 ?
    Double(completedStoryPoints) / Double(totalStoryPoints) : 0.0
```

---

## Migration Documentation

### Migration Strategy

The Redo iOS app uses **event sourcing with immutable change logs**, which provides natural migration capabilities:

1. **No Database Migrations Required**: State is always reconstructed from events
2. **Forward Compatibility**: New action types are added to `ChangeAction` enum
3. **Backward Compatibility**: Old events remain valid indefinitely
4. **Schema Evolution**: Changes to data models don't require migrations

### Version History

#### v1.0.0 - Initial Release (January 2025)

**Local Storage**:
- File: `redo_changes.json` (JSON array)
- Format: v1 protocol (ONLY version accepted)
- Validation: Strict v1 enforcement via `ChangeLogValidator`

**Firebase Schema**:
- Collections: `nodes/`, `users/`
- Document IDs: SHA-256 content hashes
- Access Control: `accessList` array with Google OAuth IDs

**Keychain Schema**:
- Service: `com.salient.vision.redo`
- Keys: `ed25519_private_key`, `ed25519_public_key`, `user_id`, `device_id`

**Data Models**:
- `ChangeLogEntry`: Event sourcing node
- `RedoTask`: Task template
- `TodoTask`: Task instance

**Actions Supported**:
- `CREATE`, `UPDATE`, `DELETE`
- `CREATE_TODO`, `COMPLETE_TODO`, `SNOOZE`
- `ARCHIVE`, `UNARCHIVE`

### Schema Changes (Historical)

#### Migration from v0 to v1 (Pre-Release)

**Changes**:
1. Switched from Base58 encoding to lowercase hex
2. Removed legacy `users/{oauthId}/changes/` subcollection
3. Adopted global `nodes/` collection
4. Separated crypto `userId` from Google OAuth ID

**Migration Script** (Not needed for iOS - web/Android only):
```typescript
// Web app migration (for reference)
async function migrateToV1() {
  const oldNodes = await db.collection('users/{uid}/changes').get();
  const batch = db.batch();

  for (const doc of oldNodes.docs) {
    const data = doc.data();
    // Convert Base58 to hex
    data.id = convertBase58ToHex(data.id);
    data.signature = convertBase58ToHex(data.signature);

    // Move to global collection
    const nodeRef = db.collection('nodes').doc(data.id);
    batch.set(nodeRef, data);
  }

  await batch.commit();
}
```

### Rollback Procedures

#### Rollback Local Storage

```swift
// Export before risky operation
let storage = ChangeLogStorage()
let backup = try storage.exportToJSON()
try backup.write(to: backupURL, atomically: true, encoding: .utf8)

// Rollback if needed
let backupJSON = try String(contentsOf: backupURL, encoding: .utf8)
try storage.deleteAllChanges()
try storage.importFromJSON(backupJSON)
```

#### Rollback Firebase Changes

**Not Recommended**: Firebase nodes are immutable. Rollback by creating compensating events:

```swift
// Instead of deleting bad change, create UNDO change
let undoChange = ChangeLogEntry(
    // ...
    action: .update,  // Revert to previous state
    taskId: originalTaskId,
    data: ChangeData(fields: previousValues)
)
```

#### Rollback Keychain

```swift
// Keychain has no rollback - keys are regenerated
let keychain = KeychainService()
try keychain.deleteAll()

// Generate new keypair
let ed25519 = Ed25519Manager()
let (privateKey, publicKey) = try ed25519.generateKeypair()
try keychain.savePrivateKey(privateKey)
try keychain.savePublicKey(publicKey)
```

### Data Migration Scripts

#### Export for Backup

```swift
func exportAllData() throws -> URL {
    let storage = ChangeLogStorage()
    let json = try storage.exportToJSON()

    let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first!

    let backupURL = documentsURL.appendingPathComponent(
        "redo_backup_\(Date().timeIntervalSince1970).json"
    )

    try json.write(to: backupURL, atomically: true, encoding: .utf8)
    return backupURL
}
```

#### Import from Backup

```swift
func importFromBackup(url: URL) throws -> Int {
    let storage = ChangeLogStorage()
    let json = try String(contentsOf: url, encoding: .utf8)
    let importedCount = try storage.importFromJSON(json)
    return importedCount
}
```

#### Cross-Platform Migration (iOS ↔ Web ↔ Android)

**Export from iOS**:
```swift
let storage = ChangeLogStorage()
let json = try storage.exportToJSON()
// Share via AirDrop, email, or cloud storage
```

**Import to Web**:
```typescript
// In browser console or script
const changes = JSON.parse(exportedJSON);
for (const change of changes) {
  await db.collection('nodes').doc(change.id).set(change);
}
```

**Import to Android**:
```kotlin
val changes = Json.decodeFromString<List<ChangeLogEntry>>(exportedJSON)
for (change in changes) {
    storage.saveChanges(userId, listOf(change))
}
```

### Breaking Changes Policy

**ZERO TOLERANCE**: The v1 protocol is frozen and immutable.

**If breaking changes are needed** (v2 protocol):
1. Create new `version: 2` schema in PROTOCOL.md
2. Update `ChangeLogValidator` to accept both v1 and v2
3. Maintain backward compatibility with v1 indefinitely
4. Provide migration tools in all apps
5. Document migration in MIGRATION.md

**Never**:
- Change v1 field formats (hex encoding, ISO 8601, etc.)
- Remove v1 action types
- Modify v1 validation rules
- Break cross-platform compatibility

---

## Performance Documentation

### Index Usage and Rationale

#### Local File Storage Indexes

**Primary Index**: Change ID (`id`)
- **Type**: Content-addressed SHA-256 hash
- **Uniqueness**: Guaranteed by cryptographic hash
- **Performance**: O(1) deduplication via `Set<String>`
- **Rationale**: Prevents duplicate changes across devices

**Secondary Indexes** (In-Memory):
1. **`author.userId`** - O(n) filter
   - Used for: Getting user's changes
   - Optimization: Could cache in memory after first load

2. **`timestamp.lamport`** - O(n log n) sort
   - Used for: Causal ordering during replay
   - Optimization: Keep sorted during append

3. **`taskId`** - O(n) filter
   - Used for: Task history view
   - Optimization: Build index during reconstruction

**Rationale for No Persistent Indexes**:
- File size is small (<1MB for 1000 changes)
- Linear scan is fast enough (<10ms)
- Indexes would complicate append-only model
- Event sourcing requires full replay anyway

#### Firebase Firestore Indexes

**Composite Indexes** (Required for Queries):

1. **`accessList` (ARRAY) + `timestamp.lamport` (ASC)**
   - Query: Get all nodes for user, sorted by causal order
   - Usage: Primary sync operation
   - Cardinality: High (one per user)

2. **`accessList` (ARRAY) + `timestamp.wall` (DESC)**
   - Query: Get recent nodes for user
   - Usage: Real-time sync, activity feed
   - Cardinality: High

3. **`taskId` (ASC) + `timestamp.lamport` (ASC)**
   - Query: Get change history for specific task
   - Usage: Task detail view, audit log
   - Cardinality: Medium (one per task)

4. **`author.userId` (ASC) + `action` (ASC) + `timestamp.lamport` (ASC)**
   - Query: Get specific action types by user
   - Usage: Analytics, debugging
   - Cardinality: Low (rarely used)

**Single Field Indexes** (Auto-Created):
- `id` - Document ID (free index)
- `accessList` - Array membership
- `createdAt` - Timestamp queries

**Index Size Estimates**:
- 1,000 nodes × 4 composite indexes × 100 bytes = ~400 KB
- Negligible compared to document storage

### Query Optimization Notes

#### Local Storage Optimization

**Optimization 1**: Cache Reconstructed State
```swift
class AppViewModel {
    private var cachedTasks: [RedoTask] = []
    private var lastReconstructionTime: Date?

    func loadTasks() async throws {
        let changes = try storage.getAllChanges(userId: userId)

        // Only reconstruct if changes updated
        if shouldReconstruct(changes) {
            cachedTasks = try reconstructor.reconstructTasks(from: changes)
            lastReconstructionTime = Date()
        }
    }
}
```

**Trade-offs**:
- **Pro**: Faster UI updates (no replay)
- **Con**: Cache invalidation complexity
- **Recommendation**: Use sparingly, prefer always-reconstruct

**Optimization 2**: Lazy Loading for Large Change Logs
```swift
func loadChangesLazily(batchSize: Int = 100) throws -> [ChangeLogEntry] {
    let allChanges = try storage.getAllChanges()

    // Return first batch
    return Array(allChanges.prefix(batchSize))
}
```

**Trade-offs**:
- **Pro**: Faster initial load
- **Con**: Incomplete state reconstruction
- **Recommendation**: Only for read-only views (history)

**Optimization 3**: Incremental Reconstruction
```swift
func reconstructIncremental(
    existingTasks: [RedoTask],
    newChanges: [ChangeLogEntry]
) throws -> [RedoTask] {
    // Only replay new changes
    var tasks = existingTasks
    for change in newChanges.sorted(by: { $0.timestamp.lamport < $1.timestamp.lamport }) {
        try applyChange(change, to: &tasks)
    }
    return tasks
}
```

**Trade-offs**:
- **Pro**: O(m) instead of O(n) for m new changes
- **Con**: Must track "last processed Lamport clock"
- **Recommendation**: Use for background sync updates

#### Firebase Optimization

**Optimization 1**: Batched Fetches
```swift
// Instead of fetching 1000 nodes individually...
for nodeId in ownedNodes {
    let doc = try await db.collection("nodes").document(nodeId).getDocument()
}

// Batch into groups of 10
for batch in ownedNodes.chunked(into: 10) {
    let snapshot = try await db.collection("nodes")
        .whereField(FieldPath.documentID(), in: batch)
        .getDocuments()
}
```

**Performance**: 1000 nodes fetched in 100 requests (~5-10 seconds) vs 1000 requests (~50+ seconds)

**Optimization 2**: Real-Time Listener with Filtering
```swift
// Listen only to changes since last sync
db.collection("nodes")
    .whereField("accessList", arrayContains: userId)
    .whereField("timestamp.lamport", isGreaterThan: lastLamport)
    .addSnapshotListener { snapshot, error in
        // Only new changes
    }
```

**Optimization 3**: Pagination for History View
```swift
var lastDocument: DocumentSnapshot?

func loadNextPage(limit: Int = 20) async throws -> [ChangeLogEntry] {
    var query = db.collection("nodes")
        .whereField("accessList", arrayContains: userId)
        .order(by: "timestamp.wall", descending: true)
        .limit(to: limit)

    if let last = lastDocument {
        query = query.start(afterDocument: last)
    }

    let snapshot = try await query.getDocuments()
    lastDocument = snapshot.documents.last

    return snapshot.documents.compactMap { parseChangeLogEntry(from: $0.data()) }
}
```

### Scaling Considerations

#### Local Storage Scaling

**Current Limits**:
- Max file size: Unlimited (iOS has no practical limit)
- Max changes: ~100,000 before performance degrades
- Max file size: ~100 MB for 100,000 changes
- Reconstruction time: ~1 second for 100,000 changes

**Scaling Strategies**:

1. **Archival** (After 1 Year):
   ```swift
   func archiveOldChanges(olderThan: Date) throws {
       let allChanges = try storage.getAllChanges()
       let recentChanges = allChanges.filter { entry in
           guard let wallDate = entry.timestamp.wallDate else { return false }
           return wallDate >= olderThan
       }
       let archivedChanges = allChanges.filter { entry in
           guard let wallDate = entry.timestamp.wallDate else { return true }
           return wallDate < olderThan
       }

       // Save archived to separate file
       let archiveURL = getArchiveURL(for: olderThan)
       try saveToArchive(archivedChanges, url: archiveURL)

       // Keep only recent in main file
       try storage.deleteAllChanges()
       try storage.saveChanges(userId: userId, newChanges: recentChanges)
   }
   ```

2. **Compression**:
   ```swift
   func compressChangeLog() throws {
       let json = try storage.exportToJSON()
       let data = json.data(using: .utf8)!
       let compressed = try (data as NSData).compressed(using: .lzfse) as Data

       // Save compressed version
       try compressed.write(to: getCompressedURL())
   }
   ```

3. **Snapshotting** (Future):
   - Take periodic snapshots of reconstructed state
   - Store snapshot + changes since snapshot
   - Reconstruct from snapshot instead of full replay
   - **Trade-off**: Complexity vs performance

#### Firebase Scaling

**Current Limits**:
- Max document size: 1 MB (current avg: 1 KB)
- Max writes per second: 500 (current: <10)
- Max reads per day: 50,000 (free tier)
- Max collection size: Unlimited

**Scaling Strategies**:

1. **Sharding by User** (Already Implemented):
   - Each user has `ownedNodes` array
   - Queries filtered by `accessList`
   - No cross-user queries needed

2. **Sharding by Time** (Future):
   ```
   nodes_2025_01/
   nodes_2025_02/
   nodes_2025_03/
   ```
   - Pros: Faster queries for recent data
   - Cons: Complex cross-shard queries

3. **Caching with Cloud Functions**:
   ```typescript
   // Precompute aggregates
   export const updateUserStats = functions.firestore
       .document('nodes/{nodeId}')
       .onCreate(async (snap, context) => {
           const node = snap.data();
           await db.collection('users')
               .doc(node.author.userId)
               .update({
                   totalNodes: FieldValue.increment(1),
                   lastActivity: FieldValue.serverTimestamp()
               });
       });
   ```

### Backup and Recovery Procedures

#### Automated Backup Strategy

**Daily Backup** (Background Task):
```swift
func scheduleDailyBackup() {
    let request = BGProcessingTaskRequest(identifier: "com.salient.vision.redo.backup")
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false

    try? BGTaskScheduler.shared.submit(request)
}

func handleBackupTask(task: BGProcessingTask) {
    task.expirationHandler = {
        task.setTaskCompleted(success: false)
    }

    Task {
        do {
            let backupURL = try exportAllData()
            try uploadToiCloud(backupURL)
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }
}
```

#### iCloud Backup

**Automatic** (via iOS):
- Change log file in `Documents/` is backed up to iCloud
- Keychain is backed up separately (encrypted)
- Restoration happens automatically on new device

**Manual Export**:
```swift
func exportToiCloudDrive() throws {
    let storage = ChangeLogStorage()
    let json = try storage.exportToJSON()

    let iCloudURL = FileManager.default.url(
        forUbiquityContainerIdentifier: nil
    )?.appendingPathComponent("Documents/redo_backup.json")

    guard let url = iCloudURL else {
        throw BackupError.iCloudUnavailable
    }

    try json.write(to: url, atomically: true, encoding: .utf8)
}
```

#### Firebase Backup

**Firestore Export** (Admin SDK):
```bash
gcloud firestore export gs://redo-backups/$(date +%Y%m%d)
```

**Scheduled Backups** (Cloud Scheduler):
```yaml
name: daily-firestore-backup
schedule: "0 2 * * *"  # 2 AM daily
timezone: "America/Los_Angeles"
target:
  uri: https://firestore.googleapis.com/v1/projects/redo-prod/databases/(default):exportDocuments
  method: POST
  body: |
    {
      "outputUriPrefix": "gs://redo-backups/$(date +%Y%m%d)",
      "collectionIds": ["nodes", "users"]
    }
```

#### Recovery Procedures

**Scenario 1: Corrupted Local Storage**

```swift
func recoverFromCorruption() async throws {
    // 1. Try to salvage valid changes
    let storage = ChangeLogStorage()
    var allChanges: [ChangeLogEntry] = []

    do {
        allChanges = try storage.getAllChanges()
    } catch {
        print("Local storage corrupted, attempting recovery...")

        // 2. Pull from Firebase
        let sync = FirebaseSyncService(userId: googleOAuthId, deviceId: deviceId)
        allChanges = try await sync.pullChanges()

        // 3. Reconstruct local storage
        try storage.deleteAllChanges()
        try storage.saveChanges(userId: cryptoUserId, newChanges: allChanges)
    }
}
```

**Scenario 2: Lost Keychain (Device Reset)**

```swift
func recoverFromKeychainLoss() throws {
    let keychain = KeychainService()

    // 1. Generate new keypair
    let ed25519 = Ed25519Manager()
    let (privateKey, publicKey) = try ed25519.generateKeypair()

    // 2. Save to Keychain
    try keychain.savePrivateKey(privateKey)
    try keychain.savePublicKey(publicKey)

    // 3. Derive new userId
    let userId = String(publicKey.prefix(32))
    try keychain.saveUserId(userId)

    // ⚠️ WARNING: Cannot access old Firebase data (different userId)
    // User must re-authenticate or import from backup
}
```

**Scenario 3: Firebase Account Loss**

```swift
func recoverFromFirebaseLoss() async throws {
    // 1. Export local changes
    let storage = ChangeLogStorage()
    let localChanges = try storage.getAllChanges()

    // 2. Create new Firebase account
    try await Auth.auth().signIn(with: credential)

    // 3. Push all local changes to new account
    let sync = FirebaseSyncService(
        userId: Auth.auth().currentUser!.uid,
        deviceId: deviceId
    )
    try await sync.syncChanges(localChanges: localChanges)
}
```

#### Point-in-Time Recovery

**Recover to Specific Date**:
```swift
func recoverToDate(_ targetDate: Date) throws -> [RedoTask] {
    let storage = ChangeLogStorage()
    let allChanges = try storage.getAllChanges()

    // Filter changes before target date
    let filteredChanges = allChanges.filter { entry in
        guard let wallDate = entry.timestamp.wallDate else { return false }
        return wallDate <= targetDate
    }

    // Reconstruct state as of that date
    let reconstructor = StateReconstructor()
    return try reconstructor.reconstructTasks(from: filteredChanges)
}
```

---

## Integration Documentation

### How Applications Use the Database

#### Application Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                         │
│        (TaskListView, CreateTaskView, TaskDetailView)        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                       AppViewModel                           │
│                (MVVM - Published State)                      │
└─┬──────────────────┬─────────────────┬──────────────────────┘
  │                  │                 │
  ▼                  ▼                 ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────────┐
│StateRecon    │ │ChangeLog    │ │FirebaseSync      │
│structor      │ │Storage      │ │Service           │
└──────────────┘ └─────────────┘ └──────────────────┘
```

#### Integration Patterns

**Pattern 1: Load Tasks on App Launch**

```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var tasks: [RedoTask] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let storage = ChangeLogStorage()
    private let reconstructor = StateReconstructor()
    private let keychain = KeychainService()

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 1. Get userId from Keychain
            guard let userId = try keychain.loadUserId() else {
                throw AppError.notAuthenticated
            }

            // 2. Load changes from local storage
            let changes = try storage.getAllChanges(userId: userId)

            // 3. Reconstruct state
            tasks = try reconstructor.reconstructTasks(from: changes)

            // 4. Background sync
            Task {
                await syncWithFirebase()
            }
        } catch {
            self.error = error
        }
    }
}
```

**Pattern 2: Create New Task**

```swift
extension AppViewModel {
    func createTask(
        title: String,
        description: String,
        priority: Int,
        storyPoints: Float,
        frequencyDays: Int
    ) async throws {
        // 1. Get user identity
        guard let userId = try keychain.loadUserId(),
              let deviceId = try keychain.loadDeviceId() else {
            throw AppError.notAuthenticated
        }

        // 2. Create change entry
        let taskId = UUID()
        let lamport = getNextLamportClock()

        let change = ChangeLogEntry(
            id: "", // Will be computed
            version: 1,
            parents: getLatestChangeIds(),
            timestamp: LogicalTimestamp(lamport: lamport, wallDate: Date()),
            author: AuthorInfo(
                userId: userId,
                deviceId: deviceId,
                publicKey: try keychain.loadPublicKey()
            ),
            action: .create,
            taskId: taskId.uuidString,
            data: ChangeData(fields: [
                "title": AnyCodable(title),
                "description": AnyCodable(description),
                "priority": AnyCodable(priority),
                "storyPoints": AnyCodable(Double(storyPoints)),
                "frequencyDays": AnyCodable(frequencyDays)
            ])
        )

        // 3. Sign change
        let signedChange = try signChange(change)

        // 4. Save to local storage
        try storage.saveChanges(userId: userId, newChanges: [signedChange])

        // 5. Reload tasks (reconstruct)
        await loadTasks()

        // 6. Background sync
        Task {
            await syncWithFirebase()
        }
    }
}
```

**Pattern 3: Complete Todo**

```swift
extension AppViewModel {
    func completeTodo(_ todo: TodoTask, for task: RedoTask, notes: String = "") async throws {
        guard let userId = try keychain.loadUserId(),
              let deviceId = try keychain.loadDeviceId() else {
            throw AppError.notAuthenticated
        }

        let lamport = getNextLamportClock()
        let completed = Date()

        let change = ChangeLogEntry(
            id: "",
            version: 1,
            parents: getLatestChangeIds(),
            timestamp: LogicalTimestamp(lamport: lamport, wallDate: completed),
            author: AuthorInfo(userId: userId, deviceId: deviceId),
            action: .completeTodo,
            taskId: task.guid.uuidString,
            data: ChangeData(fields: [
                "todoTaskId": AnyCodable(todo.guid.uuidString),
                "completed": AnyCodable(ISO8601DateFormatter().string(from: completed)),
                "notes": AnyCodable(notes)
            ])
        )

        let signedChange = try signChange(change)
        try storage.saveChanges(userId: userId, newChanges: [signedChange])

        await loadTasks()
        Task { await syncWithFirebase() }
    }
}
```

### Common Query Patterns

#### Pattern: Filter and Sort Tasks

```swift
extension AppViewModel {
    var activeTasks: [RedoTask] {
        tasks.filter { !$0.archived }
    }

    var overdueTasks: [RedoTask] {
        tasks.filter { $0.isOverdue }
    }

    var sortedByRank: [RedoTask] {
        tasks.sorted { $0.currentRank() > $1.currentRank() }
    }

    var sortedByPriority: [RedoTask] {
        tasks.sorted { $0.priority > $1.priority }
    }

    func tasks(withPriority priority: Int) -> [RedoTask] {
        tasks.filter { $0.priority == priority }
    }
}
```

#### Pattern: Analytics Aggregations

```swift
extension AppViewModel {
    var totalStoryPoints: Float {
        tasks.reduce(0) { $0 + $1.storyPoints }
    }

    var completionRate: Double {
        let allTodos = tasks.flatMap { $0.todoTasks }
        let completed = allTodos.filter { $0.isCompleted }.count
        return allTodos.isEmpty ? 0 : Double(completed) / Double(allTodos.count)
    }

    var averageCompletionTime: TimeInterval {
        let completedTodos = tasks.flatMap { $0.todoTasks.filter { $0.isCompleted } }
        let totalTime = completedTodos.reduce(0.0) { sum, todo in
            guard let completed = todo.completed else { return sum }
            return sum + completed.timeIntervalSince(todo.created)
        }
        return completedTodos.isEmpty ? 0 : totalTime / Double(completedTodos.count)
    }
}
```

### Transaction Boundaries

**CRITICAL**: All operations are single-change atomic. No multi-change transactions.

#### Atomic Operation: Single Change

```swift
// ✅ GOOD: One change = one atomic operation
func archiveTask(_ task: RedoTask) async throws {
    let change = ChangeLogEntry(
        // ...
        action: .archive,
        taskId: task.guid.uuidString
    )

    try storage.saveChanges(userId: userId, newChanges: [change])
}
```

#### Non-Atomic Operation: Multiple Changes

```swift
// ⚠️ CAUTION: Not atomic across changes, but eventual consistency guaranteed
func updateTaskAndCompleteTodo(
    task: RedoTask,
    newTitle: String,
    todo: TodoTask
) async throws {
    // Change 1: Update task
    let updateChange = ChangeLogEntry(
        // ...
        action: .update,
        data: ChangeData(fields: ["title": AnyCodable(newTitle)])
    )

    // Change 2: Complete todo
    let completeChange = ChangeLogEntry(
        // ...
        action: .completeTodo,
        parents: [updateChange.id],  // Establish causality
        data: ChangeData(fields: ["todoTaskId": AnyCodable(todo.guid.uuidString)])
    )

    // Both saved atomically to local storage
    try storage.saveChanges(userId: userId, newChanges: [updateChange, completeChange])

    // ⚠️ But Firebase push is eventual (may fail partially)
}
```

**Transaction Guarantees**:
1. **Local Storage**: Atomic write to file (all or nothing)
2. **Firebase**: Eventually consistent (may require retries)
3. **Causality**: Preserved via `parents` array and Lamport clock
4. **Ordering**: Guaranteed by Lamport clock during reconstruction

### Concurrency Handling

#### Multi-Device Sync

**Conflict Resolution**: Last-Write-Wins (LWW) based on Lamport clock

```swift
// Device A: Lamport = 5
let changeA = ChangeLogEntry(
    timestamp: LogicalTimestamp(lamport: 5, wallDate: Date()),
    action: .update,
    data: ChangeData(fields: ["title": AnyCodable("Title A")])
)

// Device B: Lamport = 6 (Device B's clock was ahead)
let changeB = ChangeLogEntry(
    timestamp: LogicalTimestamp(lamport: 6, wallDate: Date()),
    action: .update,
    data: ChangeData(fields: ["title": AnyCodable("Title B")])
)

// After sync and reconstruction:
// Device A and B both have: title = "Title B" (higher Lamport wins)
```

#### Concurrent Writes to Same Task

**Scenario**: Two devices update same task simultaneously

```
Device A (Lamport=10):  UPDATE title="Do laundry"
Device B (Lamport=11):  UPDATE priority=5

After sync:
- Both changes exist in log
- Reconstruction applies in Lamport order
- Final state: title="Do laundry", priority=5
```

**Code**:
```swift
func handleConcurrentUpdates() async throws {
    // 1. Device A creates change
    let changeA = ChangeLogEntry(
        timestamp: LogicalTimestamp(lamport: 10, wallDate: Date()),
        action: .update,
        taskId: taskId,
        data: ChangeData(fields: ["title": AnyCodable("Do laundry")])
    )
    try storage.saveChanges(userId: userId, newChanges: [changeA])

    // 2. Device B creates change (concurrently, different field)
    let changeB = ChangeLogEntry(
        timestamp: LogicalTimestamp(lamport: 11, wallDate: Date()),
        action: .update,
        taskId: taskId,
        data: ChangeData(fields: ["priority": AnyCodable(5)])
    )

    // 3. After sync, both devices reconstruct with both changes
    // Result: Both fields updated (no conflict)
}
```

#### Handling Lamport Clock Sync

**On receiving remote changes**:
```swift
func updateLamportClock(remoteChanges: [ChangeLogEntry]) {
    let maxRemoteLamport = remoteChanges.map { $0.timestamp.lamport }.max() ?? 0

    // Update local clock to max(local, remote) + 1
    currentLamport = max(currentLamport, maxRemoteLamport) + 1
}
```

#### Race Conditions

**Scenario**: User creates task while sync is in progress

```swift
class AppViewModel {
    private let syncQueue = DispatchQueue(label: "com.redo.sync", qos: .background)
    private var isSyncing = false

    func createTask(...) async throws {
        // 1. Always write to local storage first (instant)
        let change = /* ... */
        try storage.saveChanges(userId: userId, newChanges: [change])

        // 2. Reload tasks immediately (show optimistic update)
        await loadTasks()

        // 3. Sync in background (may conflict with ongoing sync)
        syncQueue.async {
            if !self.isSyncing {
                self.isSyncing = true
                Task {
                    await self.syncWithFirebase()
                    self.isSyncing = false
                }
            }
        }
    }
}
```

**Optimistic UI Updates**:
```swift
func completeTask(_ task: RedoTask) async throws {
    // 1. Update UI immediately (optimistic)
    if let index = tasks.firstIndex(where: { $0.guid == task.guid }) {
        var updatedTask = tasks[index]
        updatedTask.todoTasks[0].completed = Date()
        tasks[index] = updatedTask
    }

    // 2. Create change in background
    Task {
        let change = /* ... */
        try? storage.saveChanges(userId: userId, newChanges: [change])

        // 3. Reconstruct to confirm (may rollback if error)
        await loadTasks()
    }
}
```

---

## Security & Privacy

### Data Encryption

#### At Rest

**Local Storage**:
- File: `redo_changes.json` encrypted by iOS (Data Protection)
- Protection Class: `NSFileProtectionComplete` (default for Documents directory)
- Encryption: AES-256 (hardware-accelerated)
- Key Storage: Secure Enclave (iPhone 5s+)

**Keychain**:
- Encryption: AES-256-GCM
- Key Derivation: PBKDF2
- Access: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Backup: Encrypted in iCloud Keychain

**Firebase**:
- Encryption: AES-256 at rest (Google Cloud default)
- Key Management: Google KMS
- Certificate: SOC 2 Type II, ISO 27001

#### In Transit

**Local to Firebase**:
- Protocol: TLS 1.3
- Certificate Pinning: Not implemented (relies on system trust)
- Encryption: AES-256-GCM

**Firebase to iOS**:
- Protocol: HTTPS with TLS 1.3
- Authentication: Firebase Auth tokens (JWT)
- Expiration: 1 hour (auto-refresh)

### Access Control

#### Local Storage Access

```swift
// Only this app can access its Documents directory
// Enforced by iOS sandbox
let fileURL = try fileManager.url(
    for: .documentDirectory,
    in: .userDomainMask,  // User-specific, app-sandboxed
    appropriateFor: nil,
    create: true
)
```

**Protection**:
- Other apps: Cannot access
- User: Can access via Files app (if enabled)
- Backup: Included in iCloud backup (encrypted)

#### Keychain Access

```swift
let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.salient.vision.redo",  // App-specific
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
]
```

**Access Policy**:
- **Device Locked**: No access
- **Device Unlocked**: Full access
- **Other Apps**: No access (different service identifier)
- **Backup**: Not backed up to iCloud (device-only)

#### Firebase Access

**Security Rules**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Nodes collection
    match /nodes/{nodeId} {
      allow read: if request.auth != null
                  && request.auth.uid in resource.data.accessList;

      allow create: if request.auth != null
                    && request.auth.uid in request.resource.data.accessList
                    && request.resource.data.version == 1
                    && request.resource.data.id == nodeId;  // ID = document ID

      allow update, delete: if false;  // Immutable
    }

    // Users collection
    match /users/{userId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

**Access Matrix**:

| User | Read Own Nodes | Read Others' Nodes | Write Nodes | Delete Nodes |
|------|----------------|-------------------|-------------|--------------|
| Authenticated | ✅ | ❌ | ✅ | ❌ |
| Unauthenticated | ❌ | ❌ | ❌ | ❌ |

### Authentication Flow

```
User Opens App
    │
    ▼
Check Keychain for Keys
    │
    ├─ Keys Exist ──────────────────────────────┐
    │                                           ▼
    └─ No Keys ──► Generate Ed25519 Keypair ──► Save to Keychain
                                                  │
                                                  ▼
                                          Check Firebase Auth
                                                  │
                                   ├─ Authenticated ──────────┐
                                   │                          ▼
                                   └─ Not Auth ──► Google OAuth ──► Get Firebase Token
                                                                       │
                                                                       ▼
                                                                   Store in Keychain
                                                                       │
                                                                       ▼
                                                                   Ready to Sync
```

### Data Privacy

**User Data Collection**:
- **Collected**: Task titles, descriptions, completion times
- **NOT Collected**: Location, contacts, photos
- **Analytics**: None (no Firebase Analytics, no third-party SDKs)

**Data Sharing**:
- **Shared**: None (single-user app currently)
- **Future**: Shared task lists (opt-in, via `accessList`)

**Data Retention**:
- **Local**: Indefinite (until user deletes app)
- **Firebase**: Indefinite (until user deletes account)
- **Deletion**: User can export and delete all data

**Privacy Policy Compliance**:
- GDPR: Right to access, right to deletion, data portability
- CCPA: Same as GDPR
- App Store: Privacy nutrition label completed

### Cryptographic Signing

**Ed25519 Signature Scheme**:
```swift
// Sign change with private key
let canonicalJSON = try CanonicalJSON.encode(change)
let signature = try Ed25519Manager.sign(
    string: canonicalJSON,
    privateKeyHex: privateKey
)

// Verify signature with public key
let isValid = try Ed25519Manager.verify(
    signature: signature,
    message: canonicalJSON,
    publicKeyHex: publicKey
)
```

**Signature Coverage**:
- All fields except `signature` itself
- Canonical JSON (RFC 8785) ensures deterministic hashing
- SHA-256 hash is signed, not raw JSON

**Verification**:
- Local: Optional (trust your own signatures)
- Remote: Required (verify before accepting from Firebase)
- Cross-Platform: Critical (prevent tampering during sync)

---

## Appendix

### Error Codes

| Code | Error | Description | Recovery |
|------|-------|-------------|----------|
| `STORAGE_001` | File not found | Change log file doesn't exist | Auto-create empty file |
| `STORAGE_002` | Export failed | JSON encoding failed | Check data integrity |
| `STORAGE_003` | Import failed | JSON decoding failed | Validate input format |
| `STORAGE_004` | Corrupted data | File exists but unreadable | Restore from backup |
| `KEYCHAIN_001` | Save failed | Keychain write error | Check device lock state |
| `KEYCHAIN_002` | Load failed | Keychain read error | Regenerate keys |
| `KEYCHAIN_003` | Invalid data | Data format incorrect | Clear and regenerate |
| `FIREBASE_001` | Auth failed | Firebase authentication error | Re-authenticate |
| `FIREBASE_002` | Sync failed | Network or permissions error | Retry with backoff |
| `FIREBASE_003` | Query failed | Firestore query error | Check index configuration |
| `RECONSTRUCT_001` | Missing task ID | Change entry lacks taskId | Skip change |
| `RECONSTRUCT_002` | Invalid action | Unknown ChangeAction | Skip change |
| `RECONSTRUCT_003` | Validation failed | Change fails v1 validation | Reject change |

### Glossary

- **Change Log Entry**: Immutable event in the event sourcing log
- **Content Addressing**: Using SHA-256 hash of content as identifier
- **DAG**: Directed Acyclic Graph (structure of change dependencies)
- **Event Sourcing**: Storing changes (events) instead of current state
- **Lamport Clock**: Logical clock for causal ordering in distributed systems
- **Local-First**: Architecture where local storage is primary, cloud is secondary
- **State Reconstruction**: Deriving current state by replaying events
- **v1 Protocol**: Version 1 of the change log schema (immutable)

### References

1. **PROTOCOL.md** - Cross-platform v1 protocol specification
2. **PLANNING.md** - Architecture decisions and rationale
3. **CLAUDE.md** - AI agent instructions
4. **RFC 8785** - Canonical JSON specification
5. **Firebase Firestore Documentation** - https://firebase.google.com/docs/firestore
6. **iOS Keychain Services** - https://developer.apple.com/documentation/security/keychain_services

---

**End of DATABASE_SCHEMA.md**
