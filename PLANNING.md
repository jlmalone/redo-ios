# Redo iOS - Comprehensive Planning Document

**Created**: 2025-11-09
**Status**: Planning Phase
**Target Launch**: Q1 2026

---

## Executive Summary

**Redo iOS** will be a native iOS task management application implementing the proven v1 event sourcing protocol used by the web (leader) and Android platforms. This document outlines architecture decisions, lessons learned from existing platforms, and a phased implementation strategy.

---

## 1. Vision & Goals

### Primary Objectives
1. **Full Feature Parity** with web app (the leader platform)
2. **Cross-Platform Sync** with web, Android, and Kotlin CLI
3. **Native iOS Experience** with SwiftUI and iOS design patterns
4. **Offline-First Architecture** following Git-like local-first principles
5. **Security & Privacy** with end-to-end cryptography

### Success Criteria
- Perfect sync with web and Android (zero data loss)
- Sub-100ms UI response time for all operations
- Works flawlessly offline (airplane mode)
- App Store approval on first submission
- 5-star UX matching or exceeding web app

---

## 2. Lessons Learned from Web App (Leader Platform)

### 2.1 Architecture Wins

**Event Sourcing Excellence**:
- ✅ Immutable change log provides complete audit trail
- ✅ State reconstruction eliminates sync conflicts
- ✅ Content-addressed nodes prevent tampering
- ✅ Lamport clocks ensure causal ordering

**Local-First Paradigm**:
- ✅ All operations instant (localStorage never blocks)
- ✅ Background sync doesn't delay UI
- ✅ Offline mode works perfectly
- ✅ Git-like mental model (`git log`, `git commit`, `git fetch`)

**Universal Backend Support**:
- ✅ Same data format works with localStorage, Firebase, Git, blockchain
- ✅ No vendor lock-in
- ✅ Easy to add new backends

**iOS Implementation**: Use same principles with CoreData/File storage as primary, Firebase as optional backend

### 2.2 Critical Protocols

**STRICT v1 Validation** (from PROTOCOL.md):
- ❌ Web had 125 Base58-encoded nodes (non-compliant) causing CLI sync failures
- ✅ Solution: Zero-tolerance enforcement, immediate rejection of invalid nodes
- **iOS Must**: Implement `isValidV1Node()` identical to web app's latest version
- **iOS Must**: Reject and delete invalid nodes immediately (no legacy support)

**Hex Encoding Only**:
- ❌ Web allowed Base58/Base64 in early builds
- ✅ v1 protocol requires lowercase hexadecimal for all crypto fields
- **iOS Must**: All Ed25519 keys, signatures, SHA-256 hashes in lowercase hex

**Content Addressing**:
- ✅ SHA-256 hash of canonical JSON (RFC 8785 sorted keys)
- ✅ Deterministic IDs enable cross-platform verification
- **iOS Must**: Canonical JSON implementation matching web/Android exactly

### 2.3 Token Management

**Two-Token System** (from AUTHENTICATION_ARCHITECTURE.md):
- **Google OAuth Access Token**: For Google APIs (Calendar, Tasks)
- **Firebase Custom Token**: For Firebase authentication
- ❌ Build 106 bug: App.tsx overwrote `googleAccessToken` with Firebase token (50 min debugging)
- **iOS Lesson**: Never mix OAuth and Firebase tokens, use separate Keychain entries

**iOS Implementation**:
```swift
// Separate Keychain entries
KeychainService.save(token: googleAccessToken, key: "google_oauth_token")
KeychainService.save(token: firebaseToken, key: "firebase_custom_token")
```

### 2.4 Version Management

**Build Number Enforcement**:
- ❌ Web had multiple re-deployment wastes when version not incremented
- ✅ Solution: Two version numbers must be updated before ANY code changes
  - `src/version.json` (build number visible in footer)
  - `package.json` (semantic version)
- **iOS Must**: Automate version bumping in Xcode build phases

### 2.5 Sync Performance

**Current Web App Bottleneck**:
- ⚠️ Sequential Firestore reads causing latency
- 📋 Planned: Batched operations for 50-90% latency reduction
- **iOS Advantage**: Implement batched sync from day one

### 2.6 Documentation Excellence

**Web App Documentation** (48,000+ lines across 33 files):
- ✅ PROTOCOL.md - Cross-platform specification
- ✅ ARCHITECTURE.md - Design principles and anti-patterns
- ✅ AUTHENTICATION_ARCHITECTURE.md - Token management (created after painful bug)
- **iOS Must**: Maintain comprehensive documentation from day one

---

## 3. Lessons Learned from Android

### 3.1 Architecture Wins

**Room Database as Primary Storage**:
- ✅ Instant local operations (never blocks on network)
- ✅ Full offline functionality
- ✅ Optional Firebase sync (can be enabled/disabled)
- **iOS Equivalent**: CoreData with CloudKit or File-based storage

**MVVM with Jetpack Compose**:
- ✅ Clean separation: UI ↔ ViewModel ↔ Repository
- ✅ Reactive state updates via StateFlow
- **iOS Equivalent**: SwiftUI with @StateObject/@ObservableObject

**Comprehensive Testing**:
- ✅ 65 passing unit tests
- ✅ Test suite ported from web app (ensures protocol parity)
- ✅ Fast tests (<100ms each)
- **iOS Must**: XCTest suite with same coverage

### 3.2 Critical Fixes (Nov 2025)

**Cross-Platform Sync Issue**:
- ❌ Android used Firebase UID for storage path
- ❌ Web used Google OAuth subject ID
- ❌ Different paths = no sync between platforms
- ✅ Solution: Extract OAuth ID from JWT, persist to SharedPreferences
- **iOS Must**: Use Google OAuth ID for Firebase paths (not Firebase UID)

**Architecture Evolution**:
```
❌ ORIGINAL: users/{oauthId}/changes/{nodeId}  (per-user subcollection)
❌ INTERMEDIATE: users/{cryptoUserId}/ownedNodes[]  (crypto-based ownership)
✅ CURRENT: nodes/{nodeId} + users/{googleOAuthId}/ownedNodes[]  (OAuth-based)
```
- **iOS Must**: Use CURRENT architecture from day one

**Crypto ID vs OAuth ID Separation**:
- **Crypto userId**: First 32 chars of Ed25519 public key (for node signing/authorship)
- **Google OAuth ID**: Subject ID from JWT (for Firebase storage paths)
- These are SEPARATE and serve different purposes
- **iOS Must**: Document this distinction clearly

### 3.3 Visual Polish Gap

**Android vs Web Appearance**:
- ⚠️ Android's neon green duller than web's vibrant neon
- ⚠️ Missing glow effects that web has
- ⚠️ Typography doesn't match web's modern font
- **iOS Opportunity**: Match web's visual polish from day one

**iOS Advantage**: SwiftUI with advanced visual effects (SF Symbols, blur effects, gradients)

### 3.4 Validation Strictness

**Ported Web Test Suite**:
- ✅ 1045-line test suite ported to Android
- ✅ Strengthened `RedoNode.validate()` to match web exactly
- ✅ Validation at ALL boundaries (creation, upload, download, display)
- **iOS Must**: Port same test suite for protocol compliance

---

## 4. iOS Architecture Design

### 4.1 Technology Stack

**Core Technologies**:
- **Language**: Swift 5.9+ (iOS 17+)
- **UI Framework**: SwiftUI with Composable Architecture
- **Data Layer**: CoreData with CloudKit OR File-based JSON storage
- **Networking**: Firebase iOS SDK + URLSession
- **Cryptography**: CryptoKit (Ed25519, SHA-256)
- **Testing**: XCTest + UI Testing

**Key Frameworks**:
```swift
// Package.swift dependencies
.package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0"),
.package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
```

### 4.2 Architecture Pattern

**Composable Architecture (TCA)**:
```
┌─────────────────────────────────────────┐
│           SwiftUI Views                 │
│  (TaskListView, CalendarView, etc.)    │
└──────────────┬──────────────────────────┘
               │ ViewStore
┌──────────────▼──────────────────────────┐
│          Store<State, Action>           │
│  - Centralized state management         │
│  - Unidirectional data flow             │
└──────────┬─────────────┬────────────────┘
           │             │
┌──────────▼────────┐   ▼─────────────────┐
│  CoreData/Files   │   │  Firebase SDK   │
│  (PRIMARY)        │   │  (SYNC)         │
│  - Instant ops    │   │  - Background   │
│  - Always works   │   │  - Optional     │
└───────────────────┘   └──────────────────┘
```

**Why TCA?**:
- Proven SwiftUI architecture
- Excellent testing support
- Unidirectional data flow (matches event sourcing)
- Dependency injection built-in
- Side effect management (perfect for Firebase sync)

### 4.3 Module Structure

```
RedoApp/
├── App/
│   ├── RedoApp.swift                    # App entry point
│   ├── AppDelegate.swift                # Firebase initialization
│   └── SceneDelegate.swift              # Scene lifecycle
│
├── Core/                                # Shared business logic
│   ├── Models/
│   │   ├── RedoTask.swift               # Task template model
│   │   ├── TodoTask.swift               # Task instance model
│   │   ├── ChangeLogEntry.swift         # Event sourcing node
│   │   └── ProtocolTypes.swift          # Timestamps, author, etc.
│   │
│   ├── Services/
│   │   ├── StateReconstructor.swift     # Event replay engine
│   │   ├── ChangeLogValidator.swift     # v1 protocol validation
│   │   ├── TaskRanking.swift            # Enhanced ranking algorithm
│   │   └── CanonicalJSON.swift          # RFC 8785 JSON serializer
│   │
│   ├── Cryptography/
│   │   ├── Ed25519Manager.swift         # Key generation, signing
│   │   ├── ContentAddressing.swift      # SHA-256 hashing
│   │   └── KeychainService.swift        # Secure key storage
│   │
│   └── Storage/
│       ├── ChangeLogStorage.swift       # Local change log persistence
│       ├── CoreDataStack.swift          # CoreData setup (optional)
│       └── FileStorage.swift            # File-based storage (alternative)
│
├── Features/                            # Feature modules
│   ├── TaskList/
│   │   ├── TaskListFeature.swift        # TCA reducer
│   │   ├── TaskListView.swift           # SwiftUI view
│   │   └── TaskListViewModel.swift      # View model (if not using TCA)
│   │
│   ├── TaskDetail/
│   │   ├── TaskDetailFeature.swift
│   │   └── TaskDetailView.swift
│   │
│   ├── Calendar/
│   │   ├── CalendarFeature.swift
│   │   └── CalendarView.swift
│   │
│   ├── Analytics/
│   │   ├── AnalyticsFeature.swift
│   │   └── AnalyticsView.swift
│   │
│   └── Settings/
│       ├── SettingsFeature.swift
│       └── SettingsView.swift
│
├── Sync/                                # Firebase sync layer
│   ├── FirebaseSyncService.swift        # Main sync coordinator
│   ├── FirebaseChangeLogBackend.swift   # Firestore integration
│   └── SyncStatus.swift                 # Sync state tracking
│
├── UI/                                  # Reusable UI components
│   ├── Components/
│   │   ├── MatrixTaskCard.swift         # Task card with Matrix theme
│   │   ├── NeonButton.swift             # Neon-styled button
│   │   └── GlowModifier.swift           # Neon glow effect
│   │
│   ├── Theme/
│   │   ├── MatrixTheme.swift            # Color palette, fonts
│   │   └── Typography.swift             # Text styles
│   │
│   └── Navigation/
│       └── AppNavigation.swift          # Tab bar, routing
│
└── Tests/                               # Test suites
    ├── CoreTests/
    │   ├── ChangeLogValidationTests.swift
    │   ├── StateReconstructorTests.swift
    │   └── Ed25519Tests.swift
    │
    ├── SyncTests/
    │   └── CrossPlatformSyncTests.swift
    │
    └── UITests/
        └── TaskFlowUITests.swift
```

---

## 5. Core Data Models

### 5.1 RedoTask (Swift)

```swift
import Foundation

struct RedoTask: Identifiable, Codable, Equatable {
    let guid: UUID
    let userId: String              // First 32 chars of public key
    var title: String
    var description: String
    var privacy: Bool               // true = private, false = public
    var storyPoints: Float
    var priority: Int               // 1-5 (mapped to Low/Medium/High in UI)
    var frequencyDays: Int          // 0 = one-time, 7 = weekly, etc.
    let created: Date
    var archived: Bool
    var lastUpdated: Date?
    var todoTasks: [TodoTask]

    // Computed properties
    var isRecurring: Bool {
        frequencyDays > 0
    }

    var currentPendingTask: TodoTask? {
        todoTasks.first { $0.completed == nil }
    }

    // Business logic
    func currentRank(at date: Date = Date()) -> Double {
        guard let todo = currentPendingTask else { return 0 }

        let urgency = calculateUrgency(for: todo, at: date)
        let complexity = sqrt(storyPoints)
        let priorityWeight = Double(priority)
        let circadianBonus = isInMorningHours(date) ? 1.15 : 1.0

        return priorityWeight * urgency * complexity * circadianBonus
    }

    private func calculateUrgency(for todo: TodoTask, at date: Date) -> Double {
        let daysSinceCreation = date.timeIntervalSince(todo.created) / 86400
        let k = log(9.0) / 30.0  // 10% → 90% urgency over 30 days
        return 1.0 / (1.0 + exp(-k * (daysSinceCreation - 30.0)))
    }

    private func isInMorningHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 6 && hour < 11
    }
}
```

### 5.2 TodoTask (Swift)

```swift
struct TodoTask: Identifiable, Codable, Equatable {
    let guid: UUID
    let redoParentGuid: UUID
    let created: Date
    var notes: String
    var deadline: Date
    var completed: Date?

    var isPending: Bool {
        completed == nil
    }

    var isOverdue: Bool {
        guard isPending else { return false }
        return deadline < Date()
    }
}
```

### 5.3 ChangeLogEntry (Swift)

```swift
struct ChangeLogEntry: Identifiable, Codable, Equatable {
    let id: String                  // "sha256:<64 hex chars>"
    let version: Int                // MUST be 1
    let parents: [String]           // Parent change IDs
    let timestamp: LogicalTimestamp
    let author: AuthorInfo
    let action: ChangeAction
    let taskId: String?
    let data: ChangeData
    let signature: String?          // Ed25519 signature (128 hex chars)

    enum ChangeAction: String, Codable {
        case create = "CREATE"
        case update = "UPDATE"
        case createTodo = "CREATE_TODO"
        case completeTodo = "COMPLETE_TODO"
        case snooze = "SNOOZE"
        case archive = "ARCHIVE"
        case unarchive = "UNARCHIVE"
        case delete = "DELETE"
    }
}

struct LogicalTimestamp: Codable, Equatable {
    let lamport: Int
    let wall: String                // ISO 8601
}

struct AuthorInfo: Codable, Equatable {
    let userId: String              // First 32 chars of public key
    let deviceId: String
    let name: String?
    let publicKey: String?          // Ed25519 public key (64 hex chars)
}

struct ChangeData: Codable, Equatable {
    let fields: [String: AnyCodable]  // Flexible payload
}
```

---

## 6. Cryptography Implementation

### 6.1 Ed25519Manager (CryptoKit)

```swift
import CryptoKit
import Foundation

class Ed25519Manager {
    // Generate new Ed25519 keypair
    static func generateKey() -> (publicKey: String, privateKey: String, userId: String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let privateKeyData = privateKey.rawRepresentation

        // CRITICAL: Lowercase hexadecimal encoding (v1 protocol requirement)
        let publicKeyHex = publicKeyData.hexEncodedString(uppercase: false)
        let privateKeyHex = privateKeyData.hexEncodedString(uppercase: false)

        // User ID = first 32 chars of public key
        let userId = String(publicKeyHex.prefix(32))

        return (publicKeyHex, privateKeyHex, userId)
    }

    // Sign data with private key
    static func sign(data: Data, privateKeyHex: String) throws -> String {
        guard let privateKeyData = Data(hexEncoded: privateKeyHex) else {
            throw CryptoError.invalidPrivateKey
        }

        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let signature = try privateKey.signature(for: data)

        // CRITICAL: Lowercase hex encoding
        return signature.hexEncodedString(uppercase: false)
    }

    // Verify signature
    static func verify(data: Data, signature: String, publicKeyHex: String) throws -> Bool {
        guard let publicKeyData = Data(hexEncoded: publicKeyHex),
              let signatureData = Data(hexEncoded: signature) else {
            return false
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        return publicKey.isValidSignature(signatureData, for: data)
    }
}
```

### 6.2 ContentAddressing (SHA-256)

```swift
import CryptoKit

class ContentAddressing {
    static func calculateChangeId(entry: ChangeLogEntry) throws -> String {
        // 1. Serialize to canonical JSON (sorted keys, no whitespace)
        let canonicalJson = try CanonicalJSON.stringify(entry)

        // 2. SHA-256 hash
        let data = canonicalJson.data(using: .utf8)!
        let hash = SHA256.hash(data: data)

        // 3. Lowercase hex encoding
        let hashHex = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "sha256:\(hashHex)"
    }
}
```

### 6.3 CanonicalJSON (RFC 8785)

```swift
class CanonicalJSON {
    static func stringify<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(value)

        // Ensure no whitespace
        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let canonicalData = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            return String(data: canonicalData, encoding: .utf8)!
        }

        return String(data: data, encoding: .utf8)!
    }
}
```

---

## 7. State Reconstruction Engine

### 7.1 StateReconstructor (Swift)

```swift
class StateReconstructor {
    func reconstructTasks(from changes: [ChangeLogEntry]) throws -> [RedoTask] {
        var tasks: [String: RedoTask] = [:]

        // 1. Sort by Lamport clock (causal ordering)
        let sortedChanges = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

        // 2. Validate all changes (strict v1 enforcement)
        let validChanges = sortedChanges.filter { change in
            if !isValidV1Node(change) {
                print("⚠️ Rejecting invalid change: \(change.id)")
                return false
            }
            return true
        }

        // 3. Replay each change
        for change in validChanges {
            try applyChange(change, to: &tasks)
        }

        return Array(tasks.values)
    }

    private func applyChange(_ change: ChangeLogEntry, to tasks: inout [String: RedoTask]) throws {
        switch change.action {
        case .create:
            try handleCreate(change, tasks: &tasks)
        case .update:
            try handleUpdate(change, tasks: &tasks)
        case .completeTodo:
            try handleCompleteTodo(change, tasks: &tasks)
        case .snooze:
            try handleSnooze(change, tasks: &tasks)
        case .archive:
            try handleArchive(change, tasks: &tasks)
        case .unarchive:
            try handleUnarchive(change, tasks: &tasks)
        case .delete:
            try handleDelete(change, tasks: &tasks)
        case .createTodo:
            try handleCreateTodo(change, tasks: &tasks)
        }
    }

    private func handleCreate(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId else { return }

        let task = RedoTask(
            guid: UUID(uuidString: taskId)!,
            userId: change.author.userId,
            title: change.data.fields["title"]?.stringValue ?? "",
            description: change.data.fields["description"]?.stringValue ?? "",
            privacy: change.data.fields["privacy"]?.boolValue ?? false,
            storyPoints: Float(change.data.fields["storyPoints"]?.doubleValue ?? 1.0),
            priority: change.data.fields["priority"]?.intValue ?? 1,
            frequencyDays: change.data.fields["frequencyDays"]?.intValue ?? 7,
            created: ISO8601DateFormatter().date(from: change.timestamp.wall)!,
            archived: false,
            lastUpdated: nil,
            todoTasks: []
        )

        tasks[taskId] = task
    }

    private func handleCompleteTodo(_ change: ChangeLogEntry, tasks: inout [String: RedoTask]) throws {
        guard let taskId = change.taskId,
              var task = tasks[taskId],
              let todoTaskId = change.data.fields["todoTaskId"]?.stringValue,
              let completedStr = change.data.fields["completed"]?.stringValue else {
            return
        }

        let completed = ISO8601DateFormatter().date(from: completedStr)!

        // Mark todo as completed
        if let todoIndex = task.todoTasks.firstIndex(where: { $0.guid.uuidString == todoTaskId }) {
            task.todoTasks[todoIndex].completed = completed

            // Append notes
            if let notes = change.data.fields["notes"]?.stringValue, !notes.isEmpty {
                task.todoTasks[todoIndex].notes += "\n\(notes)"
            }

            // Auto-create next todo for recurring tasks
            if !task.archived && task.frequencyDays > 0 {
                let nextDeadline = Calendar.current.date(
                    byAdding: .day,
                    value: task.frequencyDays,
                    to: completed
                )!

                let nextTodo = TodoTask(
                    guid: UUID(),
                    redoParentGuid: task.guid,
                    created: completed,
                    notes: "",
                    deadline: nextDeadline,
                    completed: nil
                )

                task.todoTasks.append(nextTodo)
            }
        }

        tasks[taskId] = task
    }

    private func isValidV1Node(_ change: ChangeLogEntry) -> Bool {
        // Strict v1 protocol validation
        return change.version == 1 &&
               change.id.hasPrefix("sha256:") &&
               change.id.count == 71 &&  // "sha256:" + 64 hex chars
               change.timestamp.lamport > 0 &&
               !change.timestamp.wall.isEmpty &&
               !change.author.userId.isEmpty &&
               change.parents.allSatisfy { $0.hasPrefix("sha256:") }
    }
}
```

---

## 8. Firebase Sync Implementation

### 8.1 FirebaseSyncService (Swift)

```swift
import FirebaseFirestore

class FirebaseSyncService {
    private let db = Firestore.firestore()
    private let userId: String
    private let deviceId: String

    init(userId: String, deviceId: String) {
        self.userId = userId
        self.deviceId = deviceId
    }

    func syncChanges(localChanges: [ChangeLogEntry]) async throws -> SyncResponse {
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

    private func pushChanges(_ changes: [ChangeLogEntry]) async throws {
        let batch = db.batch()

        for change in changes {
            // CRITICAL: Use global nodes collection (not per-user subcollection)
            let nodeRef = db.collection("nodes").document(change.id)

            let data: [String: Any] = [
                "id": change.id,
                "version": change.version,
                "parents": change.parents,
                "timestamp": [
                    "lamport": change.timestamp.lamport,
                    "wall": change.timestamp.wall
                ],
                "author": [
                    "userId": change.author.userId,
                    "deviceId": change.author.deviceId,
                    "name": change.author.name ?? "",
                    "publicKey": change.author.publicKey ?? ""
                ],
                "action": change.action.rawValue,
                "taskId": change.taskId ?? "",
                "data": change.data.fields,
                "signature": change.signature ?? "",
                "accessList": [userId],  // Access control
                "createdAt": FieldValue.serverTimestamp()
            ]

            batch.setData(data, forDocument: nodeRef)
        }

        // Also update user's ownedNodes array
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "ownedNodes": FieldValue.arrayUnion(changes.map { $0.id })
        ], forDocument: userRef)

        try await batch.commit()
    }

    private func pullChanges() async throws -> [ChangeLogEntry] {
        // Query nodes collection using user's ownedNodes array
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let ownedNodes = userDoc.data()?["ownedNodes"] as? [String] else {
            return []
        }

        var changes: [ChangeLogEntry] = []

        // Batch fetch nodes (Firebase limit: 10 per query, so need multiple batches)
        for batch in ownedNodes.chunked(into: 10) {
            let snapshot = try await db.collection("nodes")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()

            for document in snapshot.documents {
                if let change = try? parseChangeLogEntry(from: document.data()) {
                    changes.append(change)
                }
            }
        }

        return changes
    }

    private func parseChangeLogEntry(from data: [String: Any]) throws -> ChangeLogEntry {
        // Parse Firestore document to ChangeLogEntry
        // ... implementation details
    }
}
```

---

## 9. Visual Design - Matrix Theme

### 9.1 Color Palette (SwiftUI)

```swift
import SwiftUI

extension Color {
    // Matrix color palette (matching web app's vibrant colors)
    static let matrixBackground = Color(hex: "020B09")      // Near-black
    static let matrixNeon = Color(hex: "00FFB8")            // Bright cyan-green
    static let matrixNeonDim = Color(hex: "00FFB8").opacity(0.6)
    static let matrixAmber = Color(hex: "FFC833")           // Accent
    static let matrixTextPrimary = Color(hex: "B8FFE6")     // Light cyan-green
    static let matrixTextSecondary = Color(hex: "80BFA3")   // Dimmed text
    static let matrixError = Color(hex: "FF4444")           // Error red

    // Neon glow effect (iOS advantage over Android)
    var neonGlow: some View {
        self
            .shadow(color: self.opacity(0.7), radius: 10, x: 0, y: 0)
            .shadow(color: self.opacity(0.5), radius: 20, x: 0, y: 0)
            .shadow(color: self.opacity(0.3), radius: 30, x: 0, y: 0)
    }
}
```

### 9.2 Typography

```swift
extension Font {
    static let matrixTitle = Font.custom("SFMono-Bold", size: 24)
    static let matrixHeadline = Font.custom("SFMono-Semibold", size: 18)
    static let matrixBody = Font.custom("SFMono-Regular", size: 16)
    static let matrixCaption = Font.custom("SFMono-Regular", size: 14)
}
```

### 9.3 MatrixTaskCard Component

```swift
struct MatrixTaskCard: View {
    let task: RedoTask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title with neon glow
            Text(task.title)
                .font(.matrixHeadline)
                .foregroundColor(.matrixNeon)
                .neonGlow

            // Description
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextSecondary)
            }

            // Metadata row
            HStack {
                // Priority indicator
                PriorityBadge(priority: task.priority)

                // Story points
                Text("\(Int(task.storyPoints)) pts")
                    .font(.matrixCaption)
                    .foregroundColor(.matrixTextSecondary)

                Spacer()

                // Current todo deadline
                if let todo = task.currentPendingTask {
                    DeadlineBadge(date: todo.deadline, isOverdue: todo.isOverdue)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.matrixBackground, Color(hex: "0A1815")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.matrixNeon.opacity(0.3), lineWidth: 1)
        )
    }
}
```

---

## 10. Cross-Platform Sync Testing

### 10.1 Critical Test Cases

**Test 1: SHA-256 Consistency**:
```swift
func testSHA256Consistency() throws {
    // Create identical ChangeLogEntry on iOS, Kotlin, TypeScript
    let entry = ChangeLogEntry(/* ... */)

    let iosHash = try ContentAddressing.calculateChangeId(entry)

    // Expected hash from Kotlin/TypeScript implementations
    let expectedHash = "sha256:abc123..."  // Pre-computed

    XCTAssertEqual(iosHash, expectedHash, "SHA-256 hash must match across platforms")
}
```

**Test 2: Ed25519 Signature Interoperability**:
```swift
func testEd25519CrossPlatform() throws {
    // Sign with iOS, verify with Kotlin public key
    let data = "test message".data(using: .utf8)!
    let signature = try Ed25519Manager.sign(data: data, privateKeyHex: testPrivateKey)

    // Verify using Kotlin-generated public key
    let isValid = try Ed25519Manager.verify(
        data: data,
        signature: signature,
        publicKeyHex: kotlinPublicKey
    )

    XCTAssertTrue(isValid, "Ed25519 signatures must be cross-platform compatible")
}
```

**Test 3: State Reconstruction Parity**:
```swift
func testStateReconstructionParity() throws {
    // Use same change log as Kotlin/TypeScript tests
    let changes = loadTestChangeLog()  // From shared test vectors

    let tasks = try StateReconstructor().reconstructTasks(from: changes)

    // Expected state from Kotlin/TypeScript
    let expectedTasks = loadExpectedTaskState()

    XCTAssertEqual(tasks, expectedTasks, "State reconstruction must match across platforms")
}
```

---

## 11. Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- ✅ Set up Xcode project with SwiftUI + TCA
- ✅ Implement core models (RedoTask, TodoTask, ChangeLogEntry)
- ✅ Implement cryptography (Ed25519Manager, ContentAddressing)
- ✅ Implement canonical JSON serialization
- ✅ Write unit tests for cryptography (cross-platform verification)
- **Deliverable**: Core models library with 100% test coverage

### Phase 2: State Management (Weeks 3-4)
- ✅ Implement StateReconstructor
- ✅ Implement ChangeLogValidator (strict v1 enforcement)
- ✅ Implement Lamport clock management
- ✅ Write unit tests for state reconstruction
- **Deliverable**: Event sourcing engine with validated protocol compliance

### Phase 3: Storage Layer (Weeks 4-5)
- ✅ Implement local change log storage (File-based or CoreData)
- ✅ Implement Keychain service for private keys
- ✅ Implement export/import for backup
- **Deliverable**: Offline-first local storage

### Phase 4: Firebase Sync (Weeks 5-6)
- ✅ Integrate Firebase iOS SDK
- ✅ Implement FirebaseSyncService
- ✅ Implement Google OAuth authentication
- ✅ Test sync with web app and Android
- **Deliverable**: Cross-platform cloud sync

### Phase 5: UI Foundation (Weeks 7-8)
- ✅ Implement Matrix theme (colors, typography, components)
- ✅ Build TaskListView with filtering/sorting
- ✅ Build TaskDetailView
- ✅ Build CreateTaskView
- **Deliverable**: Core UI with task management

### Phase 6: Advanced Features (Weeks 9-10)
- ✅ Implement CalendarView
- ✅ Implement AnalyticsView
- ✅ Implement enhanced task ranking algorithm
- ✅ Implement search and filtering
- **Deliverable**: Feature parity with web app

### Phase 7: Polish & Testing (Weeks 11-12)
- ✅ UI/UX refinement (animations, transitions)
- ✅ Comprehensive testing (unit, integration, UI)
- ✅ Performance optimization
- ✅ Accessibility (VoiceOver, Dynamic Type)
- **Deliverable**: App Store-ready app

### Phase 8: Launch (Week 13)
- ✅ App Store submission
- ✅ Beta testing via TestFlight
- ✅ Documentation (README, CLAUDE.md, etc.)
- **Deliverable**: Public release on App Store

---

## 12. Success Metrics

### Technical Metrics
- ✅ 100% v1 protocol compliance (zero invalid nodes)
- ✅ <100ms UI response time for all local operations
- ✅ Perfect sync with web and Android (zero data loss)
- ✅ Works offline (airplane mode) with full functionality
- ✅ 90%+ code coverage on core business logic

### User Experience Metrics
- ✅ 5-star average rating on App Store
- ✅ <5% crash rate
- ✅ Positive user feedback on visual design
- ✅ Comparable or better UX than web app

### Development Metrics
- ✅ Complete documentation (README, CLAUDE.md, ARCHITECTURE.md)
- ✅ All major features completed within 13 weeks
- ✅ App Store approval on first submission

---

## 13. Risk Mitigation

### Technical Risks

**Risk 1: Cross-Platform Sync Failures**
- **Mitigation**: Implement comprehensive test suite from day one
- **Mitigation**: Use exact same Firebase structure as web/Android
- **Mitigation**: Weekly sync testing with web and Android

**Risk 2: Cryptography Implementation Errors**
- **Mitigation**: Port test vectors from Kotlin/TypeScript
- **Mitigation**: Use battle-tested CryptoKit (not custom crypto)
- **Mitigation**: Cross-platform signature verification tests

**Risk 3: State Reconstruction Bugs**
- **Mitigation**: Port StateReconstructor test suite from Android
- **Mitigation**: Use deterministic test fixtures
- **Mitigation**: Validate against web app's 1045-line test suite

### Schedule Risks

**Risk 1: Underestimated Complexity**
- **Mitigation**: Build MVP first (Phase 1-4), then enhance
- **Mitigation**: Weekly progress reviews
- **Mitigation**: Maintain todo list with realistic estimates

**Risk 2: Dependency Issues**
- **Mitigation**: Lock Firebase SDK version early
- **Mitigation**: Test CryptoKit on target iOS version
- **Mitigation**: Have fallback plans (File storage instead of CoreData)

---

## 14. Documentation Requirements

Following web app's excellent documentation model:

### Core Documents
1. **README.md** - Quick start, features, screenshots
2. **CLAUDE.md** - AI agent instructions, project context
3. **ARCHITECTURE.md** - Design principles, architecture decisions
4. **PROTOCOL.md** - v1 protocol specification (link to web app's)
5. **AUTHENTICATION_ARCHITECTURE.md** - Token management, OAuth flow
6. **ROADMAP.md** - Feature planning, future enhancements

### Development Documents
7. **SETUP_GUIDE.md** - Detailed setup instructions
8. **TESTING.md** - Testing strategy, test coverage
9. **CROSS_PLATFORM_SYNC.md** - Sync implementation details
10. **SESSION_SUMMARY.md** - Development log

### Reference Documents
11. **API_REFERENCE.md** - Public API documentation
12. **TROUBLESHOOTING.md** - Common issues and solutions

---

## 15. Next Steps

### Immediate Actions (This Week)
1. ✅ Review and approve this planning document
2. ⏳ Set up Xcode project structure
3. ⏳ Implement core data models
4. ⏳ Set up Firebase iOS SDK

### Week 1-2 Goals
- Complete Phase 1 (Foundation)
- Establish cross-platform test vectors
- Begin Phase 2 (State Management)

### Decision Points
- **Architecture**: TCA vs MVVM? (Recommend TCA for testability)
- **Storage**: CoreData vs File-based? (Recommend File-based for simplicity)
- **Code Sharing**: Pure Swift vs Kotlin Multiplatform? (Recommend pure Swift initially)

---

## Conclusion

**Redo iOS** has a clear path to success by learning from the web app (leader) and Android implementations. The strict v1 protocol, local-first architecture, and comprehensive testing strategy provide a solid foundation. With SwiftUI's native capabilities, we can match or exceed the web app's visual polish while maintaining perfect cross-platform sync.

**Estimated Timeline**: 13 weeks to App Store launch
**Risk Level**: Medium (mitigated by strong protocols and testing)
**Success Probability**: High (proven architecture, clear documentation)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-09
**Status**: Awaiting approval to proceed with implementation
