# Cross-Platform Sync Testing Proposal - iOS Perspective

**Project:** REDO Task Management
**Platform:** iOS (with cross-platform validation)
**Date:** 2025-11-16
**Protocol Version:** v1
**Author:** Claude (iOS Agent)

---

## Executive Summary

This document outlines a comprehensive testing strategy for validating cross-platform sync between iOS and other REDO platforms (Web, Android, Kotlin CLI). The strategy focuses on protocol compliance, conflict resolution, and data integrity across the decentralized peer-to-peer architecture with Firebase as the shared replication target.

**Key Principles:**
- All platforms must produce byte-for-byte identical hashes for identical nodes
- Firebase is a replication target, not the source of truth
- Local storage is the source of truth for each device
- Sync must be non-blocking and resilient to network failures
- Conflicts are inevitable and must be handled gracefully

---

## iOS-Specific Context

### Current Implementation Status
- ✅ Core models (RedoTask, ChangeLogEntry)
- ✅ Cryptography (Ed25519, SHA-256, canonical JSON)
- ✅ State reconstruction (event replay)
- ✅ Local storage (file-based change log)
- ✅ Firebase sync service (basic)
- ⏳ Conflict resolution (partially implemented)
- ⏳ Offline mode (needs testing)

### Testing Environment
- **Simulator:** iOS 17.0+ (iPhone 14 Pro)
- **Device:** Physical iPhone for network tests
- **Firebase:** Staging project (`redo-staging` per ecosystem)
- **Storage:** Sandbox Documents directory
- **Network:** Network Link Conditioner for offline tests

---

## Test Data Fixtures

### Fixture 1: Basic Task
```json
{
  "version": 1,
  "id": "sha256:a1b2c3d4e5f6...",
  "parents": [],
  "timestamp": {
    "lamport": 1,
    "wall": "2025-11-16T10:00:00.000Z"
  },
  "author": {
    "userId": "abc123def456...",
    "deviceId": "ios-iphone-001",
    "publicKey": "abc123def456..."
  },
  "action": "CREATE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "fields": {
      "title": "Buy groceries",
      "priority": 3,
      "timeEstimate": 30
    }
  },
  "signature": "abc123...",
  "accessList": ["105903772564891234567"],
  "createdAt": "2025-11-16T10:00:00.000Z"
}
```

### Fixture 2: Edge Case Task (Special Characters)
```json
{
  "data": {
    "fields": {
      "title": "Test émojis 🚀 & symbols: @#$%^&*()",
      "description": "Multi-line\nwith\ttabs\nand \"quotes\"",
      "priority": 1,
      "timeEstimate": 120
    }
  }
}
```

### Fixture 3: Maximum Length Fields
```json
{
  "data": {
    "fields": {
      "title": "A".repeat(200),
      "description": "B".repeat(5000),
      "priority": 5,
      "timeEstimate": 9999,
      "tags": ["tag1", "tag2", "tag3", ...]  // 50 tags
    }
  }
}
```

### Fixture 4: Complex DAG (Multiple Parents)
```json
{
  "version": 1,
  "id": "sha256:merge001...",
  "parents": [
    "sha256:parent001...",
    "sha256:parent002..."
  ],
  "action": "MERGE",
  "taskId": "550e8400-e29b-41d4-a716-446655440001"
}
```

---

## Test Scenarios

### Scenario 1: Basic Create → Read (Web → iOS)

**Platforms:** Web → iOS
**Objective:** Verify iOS can read and reconstruct tasks created on Web

**Initial State:**
- iOS: Empty change log
- Web: Empty change log
- Firebase: Empty `nodes/` collection

**Actions:**
1. Web: Create task "Buy groceries" (priority 3, estimate 30 min)
2. Web: Push to Firebase (verify node uploaded)
3. iOS: Call `syncChanges()` in background
4. iOS: Verify task appears in `getAllTasks()`

**Expected Outcome:**
- iOS reconstructs task with identical fields
- Task appears in TaskListView immediately after sync
- No validation errors in iOS logs

**Protocol Checks:**
- [ ] Node ID is `sha256:` + 64 lowercase hex chars
- [ ] Timestamp.wall has exactly 3 decimal places + 'Z'
- [ ] Author.userId is 32 lowercase hex chars
- [ ] Signature is 128 lowercase hex chars
- [ ] SHA-256 hash matches Web's calculated hash

**Pass Criteria:**
- iOS `getAllTasks()` returns 1 task
- `task.title == "Buy groceries"`
- `task.priority == 3`
- `task.timeEstimate == 30`
- No errors in iOS console

**Firebase Verification:**
```bash
# Query Firebase
firebase firestore:get nodes/sha256:a1b2c3d4...

# Verify structure matches Fixture 1
```

---

### Scenario 2: Create → Update → Complete (iOS → Android → Web)

**Platforms:** iOS → Android → Web
**Objective:** Verify multi-hop sync preserves causal ordering

**Initial State:**
- All platforms synced with 0 tasks
- Firebase: Empty

**Actions:**
1. iOS: Create task "Write tests" (lamport=1)
2. iOS: Push to Firebase
3. Android: Pull from Firebase, verify task appears
4. Android: Update task title to "Write comprehensive tests" (lamport=2, parent=iOS node)
5. Android: Push to Firebase
6. Web: Pull from Firebase, verify update
7. Web: Complete task (lamport=3, parent=Android node)
8. Web: Push to Firebase
9. iOS: Pull from Firebase

**Expected Outcome:**
- iOS sees completed task with updated title
- Change log has 3 entries (CREATE → UPDATE → COMPLETE)
- Parents chain correctly (CREATE ← UPDATE ← COMPLETE)
- Lamport clocks increase monotonically (1 → 2 → 3)

**Protocol Checks:**
- [ ] Each node references correct parent
- [ ] Lamport clocks are monotonic
- [ ] SHA-256 hashes are deterministic (iOS recalculates and matches)
- [ ] State reconstruction produces completed task

**Pass Criteria:**
- iOS `task.title == "Write comprehensive tests"`
- iOS `task.completedAt != nil`
- iOS `changeLog.count == 3`
- iOS `changeLog[1].parents[0] == changeLog[0].id`

**iOS-Specific Validation:**
```swift
// StateReconstructor should produce correct final state
let changes = try storage.getAllChanges(userId: userId)
XCTAssertEqual(changes.count, 3)
let tasks = try stateReconstructor.reconstructTasks(from: changes)
XCTAssertEqual(tasks.count, 1)
XCTAssertNotNil(tasks[0].completedAt)
```

---

### Scenario 3: Offline Conflict → Resolution (iOS vs Android)

**Platforms:** iOS (offline) vs Android (offline) → Online merge
**Objective:** Test conflict detection and MERGE node creation

**Initial State:**
- Both platforms have synced task "Plan meeting" (lamport=10)
- Both go offline
- Firebase: Last known state (lamport=10)

**Actions:**
1. iOS (offline): Complete task (lamport=11, wall=2025-11-16T10:00:00.000Z)
2. Android (offline): Update task priority to 1 (lamport=11, wall=2025-11-16T10:00:01.000Z)
3. iOS goes online, pushes to Firebase
4. Android goes online, pulls from Firebase
5. Android detects conflict (same parent, different actions)
6. Android creates MERGE node (lamport=12, parents=[iOS complete, Android update])
7. Android pushes MERGE to Firebase
8. iOS pulls MERGE from Firebase

**Expected Outcome:**
- Both platforms end with MERGE node
- Task is completed (iOS wins) with priority 1 (Android wins)
- No data loss
- Change log shows divergent history then convergence

**Protocol Checks:**
- [ ] Conflict detected (same lamport, different wall times)
- [ ] MERGE node has 2 parents
- [ ] MERGE action is "MERGE"
- [ ] MERGE data combines both changes
- [ ] Final state is deterministic (both platforms agree)

**Pass Criteria:**
- iOS `task.completedAt != nil` (iOS change preserved)
- iOS `task.priority == 1` (Android change preserved)
- iOS `changeLog` shows MERGE node
- iOS StateReconstructor produces identical state as Android

**iOS Implementation Notes:**
```swift
// FirebaseSyncService should detect conflict
// Logic: If pulling node with same lamport but different ID, create MERGE
if localNode.timestamp.lamport == remoteNode.timestamp.lamport &&
   localNode.id != remoteNode.id {
    // Conflict detected
    let mergeNode = createMergeNode(
        parents: [localNode.id, remoteNode.id],
        combinedData: mergeData(localNode, remoteNode)
    )
    try storage.saveChanges(userId: userId, newChanges: [mergeNode])
}
```

---

### Scenario 4: Rapid Sequential Edits (Multi-Platform)

**Platforms:** Web → iOS → Android → CLI (rapid succession)
**Objective:** Test Lamport clock synchronization under high frequency

**Initial State:**
- All platforms synced
- Firebase: Empty

**Actions:**
1. Web: CREATE task (lamport=1, wait 100ms)
2. iOS: Pull, UPDATE task (lamport=2, wait 100ms)
3. Android: Pull, ADD_TODO task (lamport=3, wait 100ms)
4. CLI: Pull, COMPLETE_TODO task (lamport=4, wait 100ms)
5. Web: Pull, COMPLETE task (lamport=5)
6. All platforms sync

**Expected Outcome:**
- All platforms converge to same final state
- Change log has 5 entries in causal order
- No missing parents
- No duplicate nodes

**Protocol Checks:**
- [ ] Lamport clocks increment correctly (1→2→3→4→5)
- [ ] Each node has exactly 1 parent (linear history)
- [ ] Wall times are monotonically increasing
- [ ] No race conditions (all platforms see same order)

**Pass Criteria:**
- All platforms: `changeLog.count == 5`
- All platforms: `task.completedAt != nil`
- All platforms: `task.todos[0].completedAt != nil`
- iOS: No "missing parent" validation errors

**iOS Performance Check:**
```swift
// State reconstruction should complete in < 100ms for 5 nodes
let start = Date()
let tasks = try stateReconstructor.reconstructTasks(from: changes)
let duration = Date().timeIntervalSince(start)
XCTAssertLessThan(duration, 0.1)  // 100ms
```

---

### Scenario 5: Large Batch Sync (Stress Test)

**Platforms:** Web → iOS
**Objective:** Test iOS performance with large change logs

**Initial State:**
- Web: 500 tasks created (500 CREATE nodes)
- iOS: Empty

**Actions:**
1. Web: Create 500 tasks (various priorities, estimates)
2. Web: Complete 250 tasks (250 COMPLETE nodes)
3. Web: Push all to Firebase (750 nodes total)
4. iOS: Call `syncChanges()`
5. iOS: Measure sync time, memory usage, UI responsiveness

**Expected Outcome:**
- iOS downloads all 750 nodes
- iOS reconstructs 500 tasks (250 active, 250 completed)
- UI remains responsive during sync
- Memory usage < 50MB

**Protocol Checks:**
- [ ] All 750 nodes validate successfully
- [ ] No duplicate nodes in Firebase
- [ ] Batch fetching works (Firebase 'in' query limited to 10)
- [ ] No timeout errors

**Pass Criteria:**
- iOS `changeLog.count == 750`
- iOS `getAllTasks().count == 500`
- Sync completes in < 10 seconds
- UI frame rate > 30 FPS during sync
- No memory warnings

**iOS Implementation:**
```swift
// FirebaseSyncService should batch fetch
// Firestore 'in' query limited to 10 IDs
let nodeIds = ownedNodes  // 750 IDs
let batches = nodeIds.chunked(into: 10)  // 75 batches
for batch in batches {
    let nodes = try await fetchNodes(ids: batch)
    try storage.saveChanges(userId: userId, newChanges: nodes)
}
```

---

### Scenario 6: Edge Case Data (Unicode, Escaping)

**Platforms:** iOS → Web → Android
**Objective:** Verify canonical JSON handles special characters correctly

**Initial State:**
- All platforms empty

**Actions:**
1. iOS: Create task with title "Test émojis 🚀 & symbols: @#$%^&*()"
2. iOS: Add description with "Multi-line\nwith\ttabs\nand \"quotes\""
3. iOS: Push to Firebase
4. Web: Pull from Firebase
5. Android: Pull from Firebase

**Expected Outcome:**
- All platforms display identical text
- SHA-256 hashes match across platforms
- No encoding errors (UTF-8 preserved)
- JSON escaping correct (\n, \t, \")

**Protocol Checks:**
- [ ] Unicode characters preserved (émojis, UTF-8)
- [ ] JSON escaping correct (quotes, newlines, tabs)
- [ ] SHA-256 hash identical (iOS, Web, Android)
- [ ] No Base64 encoding (all hex)

**Pass Criteria:**
- Web `task.title` contains 🚀 emoji
- Android `task.description` contains literal \n (not newline)
- iOS SHA-256 matches Web SHA-256
- Firebase stores UTF-8 correctly

**Hash Verification:**
```swift
// iOS calculates hash
let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
// Expected: "sha256:abc123..." (from Web)

// Verify in Web console:
// > console.log(ChangeLogService.calculateChangeId(node))
// > "sha256:abc123..."

XCTAssertEqual(iosHash, expectedWebHash)
```

---

### Scenario 7: Parent Chain Validation (DAG Integrity)

**Platforms:** iOS → Android (with intentional corruption)
**Objective:** Test iOS validation rejects invalid parent chains

**Initial State:**
- iOS: Task with 3-node history (CREATE → UPDATE → COMPLETE)
- Android: Empty

**Actions:**
1. iOS: Push to Firebase
2. Android: Pull from Firebase
3. Android: Manually edit Firebase node (break parent chain)
4. Android: Set node.parents = ["sha256:nonexistent..."]
5. iOS: Pull from Firebase (should detect invalid parent)

**Expected Outcome:**
- iOS ChangeLogValidator rejects node with missing parent
- iOS logs error "Invalid parent reference"
- iOS does NOT save corrupted node to local storage
- iOS continues with valid nodes only

**Protocol Checks:**
- [ ] ChangeLogValidator checks parent existence
- [ ] Invalid nodes are rejected
- [ ] Valid nodes are preserved
- [ ] UI shows error notification (optional)

**Pass Criteria:**
- iOS `changeLog.count == 3` (original valid nodes only)
- iOS logs contain "ValidationError: missing parent"
- iOS `getAllTasks()` still returns task (from valid local cache)
- No crash or data corruption

**iOS Validation Logic:**
```swift
// ChangeLogValidator.swift
func validateParentChain(entry: ChangeLogEntry, existingEntries: [ChangeLogEntry]) throws {
    for parentId in entry.parents {
        guard existingEntries.contains(where: { $0.id == parentId }) else {
            throw ValidationError.missingParent(parentId)
        }
    }
}
```

---

### Scenario 8: Concurrent Creates (Same Timestamp)

**Platforms:** iOS + Android (simultaneous)
**Objective:** Test wall time tie-breaking for lamport=1

**Initial State:**
- Both platforms empty
- Both offline (no sync)

**Actions:**
1. iOS: Create task "Task A" (lamport=1, wall=2025-11-16T10:00:00.000Z)
2. Android: Create task "Task B" (lamport=1, wall=2025-11-16T10:00:00.000Z)
3. Both go online simultaneously
4. Both push to Firebase
5. Both pull from Firebase

**Expected Outcome:**
- Both platforms see 2 tasks (Task A, Task B)
- Both nodes coexist (different IDs, same lamport)
- Ordering is deterministic (sort by SHA-256 hash)
- No conflict (different task IDs)

**Protocol Checks:**
- [ ] Both nodes have lamport=1 (valid)
- [ ] Both nodes have different IDs (different signatures)
- [ ] State reconstruction produces 2 tasks
- [ ] Ordering is consistent (iOS and Android agree)

**Pass Criteria:**
- iOS `getAllTasks().count == 2`
- Android `getAllTasks().count == 2`
- Ordering: If iOS SHA < Android SHA, then iOS task first
- Both platforms display identical order

**iOS Sorting Logic:**
```swift
// StateReconstructor.swift
func reconstructTasks(from changes: [ChangeLogEntry]) -> [TodoTask] {
    let sorted = changes.sorted { lhs, rhs in
        if lhs.timestamp.lamport != rhs.timestamp.lamport {
            return lhs.timestamp.lamport < rhs.timestamp.lamport
        }
        // Tie-break by SHA-256 hash (deterministic)
        return lhs.id < rhs.id
    }
    // Replay in sorted order
}
```

---

### Scenario 9: Network Interruption Recovery

**Platforms:** iOS (unstable network)
**Objective:** Test resilience to network failures during sync

**Initial State:**
- Firebase: 100 tasks
- iOS: Empty
- Network: Use Network Link Conditioner (50% packet loss)

**Actions:**
1. iOS: Call `syncChanges()`
2. Network drops during fetch (after 50 nodes downloaded)
3. iOS: Retry logic activates
4. Network recovers
5. iOS: Resumes fetch from last successful batch

**Expected Outcome:**
- iOS eventually downloads all 100 tasks
- No duplicate nodes in local storage
- No corrupted nodes
- Sync completes successfully after retries

**Protocol Checks:**
- [ ] Retry logic exponential backoff (2s, 4s, 8s, 16s)
- [ ] Idempotent sync (re-fetching same nodes is safe)
- [ ] Local storage deduplication works
- [ ] UI shows "Syncing..." indicator

**Pass Criteria:**
- iOS `changeLog.count == 100` (eventually)
- iOS logs show retry attempts (< 5 retries)
- No crash or timeout errors
- Sync completes in < 60 seconds (including retries)

**iOS Retry Logic:**
```swift
// FirebaseSyncService.swift
func syncChanges() async throws {
    var attempt = 0
    let maxAttempts = 5
    var backoff = 2.0  // seconds

    while attempt < maxAttempts {
        do {
            try await performSync()
            return  // Success
        } catch {
            attempt += 1
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff *= 2  // Exponential backoff
            } else {
                throw error  // Final attempt failed
            }
        }
    }
}
```

---

### Scenario 10: Full Round-Trip (iOS → Web → Android → CLI → iOS)

**Platforms:** All platforms in sequence
**Objective:** Comprehensive end-to-end validation

**Initial State:**
- All platforms empty, synced
- Firebase: Empty

**Actions:**
1. **iOS**: Create task "Round-trip test" with 3 TODOs (lamport=1)
2. **iOS**: Push to Firebase
3. **Web**: Pull from Firebase, verify task appears
4. **Web**: Complete first TODO (lamport=2)
5. **Web**: Push to Firebase
6. **Android**: Pull from Firebase, verify TODO completed
7. **Android**: Add new TODO "Final step" (lamport=3)
8. **Android**: Push to Firebase
9. **CLI**: Pull from Firebase, verify 4 TODOs (3 original + 1 new)
10. **CLI**: Complete task (lamport=4)
11. **CLI**: Push to Firebase
12. **iOS**: Pull from Firebase, verify task completed with all TODOs

**Expected Outcome:**
- iOS sees completed task with 4 TODOs (1 completed, 3 active)
- Change log has 4 entries (CREATE → COMPLETE_TODO → ADD_TODO → COMPLETE)
- All platforms converge to identical state
- All SHA-256 hashes match

**Protocol Checks:**
- [ ] Each platform validates all nodes
- [ ] No encoding mismatches (hex, UTF-8)
- [ ] Lamport clocks increment correctly
- [ ] Parent chains are valid
- [ ] State reconstruction is deterministic

**Pass Criteria:**
- iOS `task.completedAt != nil`
- iOS `task.todos.count == 4`
- iOS `task.todos[0].completedAt != nil` (first TODO completed)
- iOS `changeLog.count == 4`
- All platforms: Final state SHA-256 matches

**Full Validation Checklist:**
```swift
// iOS comprehensive validation
let changes = try storage.getAllChanges(userId: userId)

// 1. Count
XCTAssertEqual(changes.count, 4)

// 2. Ordering
XCTAssertEqual(changes[0].action, .create)
XCTAssertEqual(changes[1].action, .completeTodo)
XCTAssertEqual(changes[2].action, .addTodo)
XCTAssertEqual(changes[3].action, .complete)

// 3. Parent chain
XCTAssertEqual(changes[1].parents, [changes[0].id])
XCTAssertEqual(changes[2].parents, [changes[1].id])
XCTAssertEqual(changes[3].parents, [changes[2].id])

// 4. State reconstruction
let tasks = try stateReconstructor.reconstructTasks(from: changes)
XCTAssertEqual(tasks.count, 1)
XCTAssertNotNil(tasks[0].completedAt)
XCTAssertEqual(tasks[0].todos.count, 4)

// 5. Hash verification (compare with Web)
let iosHash = try ContentAddressing.calculateChangeId(entry: changes[0])
let expectedWebHash = "sha256:..."  // From Web console
XCTAssertEqual(iosHash, expectedWebHash)
```

---

## Verification Checklist

### Pre-Sync Validation (Before pushing to Firebase)

**iOS Local Storage:**
- [ ] Change log file exists (`~/Library/Application Support/com.redo.app/changes_{userId}.json`)
- [ ] All entries validate against v1 protocol
- [ ] No duplicate IDs in local storage
- [ ] Parent references are valid (all parents exist locally)

**iOS Cryptography:**
- [ ] Private key exists in Keychain (`com.redo.app.privateKey`)
- [ ] Public key exists in Keychain (`com.redo.app.publicKey`)
- [ ] Signatures verify correctly (Ed25519)
- [ ] SHA-256 hashes are lowercase hex (not uppercase, not Base58)

### Post-Sync Validation (After pushing to Firebase)

**Firebase Structure:**
- [ ] Node exists in `nodes/{nodeId}` collection
- [ ] Node has required fields: id, version, parents, timestamp, author, action, signature
- [ ] Node has `accessList` array (contains Google OAuth ID)
- [ ] Node has `createdAt` timestamp

**Firebase Encoding:**
- [ ] All hex fields are lowercase (id, userId, publicKey, signature)
- [ ] Timestamp.wall has exactly 3 decimals + 'Z' (e.g., "2025-11-16T10:00:00.000Z")
- [ ] No Base64 encoding anywhere
- [ ] UTF-8 characters preserved (émojis, accents)

**Firebase Security:**
- [ ] User can read their own nodes (accessList check passes)
- [ ] User cannot read other users' nodes (security rules enforce)
- [ ] User can write to `users/{oauthId}/ownedNodes` (own ID only)
- [ ] User cannot modify other users' ownedNodes arrays

### Cross-Platform Validation

**Hash Consistency:**
- [ ] iOS SHA-256 matches Web SHA-256 (for identical node)
- [ ] iOS SHA-256 matches Android SHA-256
- [ ] iOS SHA-256 matches CLI SHA-256
- [ ] Hash calculation is deterministic (same input → same output)

**State Consistency:**
- [ ] iOS reconstructed state matches Web state
- [ ] iOS reconstructed state matches Android state
- [ ] iOS reconstructed state matches CLI state
- [ ] All platforms show same task count, same titles, same completion status

**Timestamp Consistency:**
- [ ] Lamport clocks are monotonically increasing
- [ ] Wall times are reasonable (not year 1970 or 3000)
- [ ] Wall times have exactly 3 decimal places
- [ ] Timezone is always UTC (Z suffix)

---

## Expected Firebase Node Examples

### Example 1: CREATE Action (from iOS)
```json
{
  "version": 1,
  "id": "sha256:7f9a3c5b2d8e1a6f4b3c9d7e2a5f8b1c4d9e6a3f7b2c5d8e1a4f9b3c6d7e2a5f",
  "parents": [],
  "timestamp": {
    "lamport": 1,
    "wall": "2025-11-16T10:00:00.000Z"
  },
  "author": {
    "userId": "abc123def456789abc123def456789ab",
    "deviceId": "ios-iphone-14-pro",
    "publicKey": "abc123def456789abc123def456789abc123def456789abc123def456789abcd"
  },
  "action": "CREATE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "fields": {
      "title": "Buy groceries",
      "priority": 3,
      "timeEstimate": 30,
      "createdAt": "2025-11-16T10:00:00.000Z"
    }
  },
  "signature": "a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2",
  "accessList": ["105903772564891234567"],
  "createdAt": {
    "_seconds": 1731751200,
    "_nanoseconds": 0
  }
}
```

**iOS Code to Create:**
```swift
let task = RedoTask(
    id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
    title: "Buy groceries",
    priority: 3,
    timeEstimate: 30
)

let entry = try ChangeLogEntry.create(
    task: task,
    author: author,
    timestamp: LogicalTimestamp(lamport: 1, wall: Date.fromISO8601("2025-11-16T10:00:00.000Z")),
    privateKey: privateKey
)

try storage.saveChanges(userId: author.userId, newChanges: [entry])
```

---

### Example 2: UPDATE Action (from iOS)
```json
{
  "version": 1,
  "id": "sha256:8a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b",
  "parents": ["sha256:7f9a3c5b2d8e1a6f4b3c9d7e2a5f8b1c4d9e6a3f7b2c5d8e1a4f9b3c6d7e2a5f"],
  "timestamp": {
    "lamport": 2,
    "wall": "2025-11-16T10:05:00.000Z"
  },
  "author": {
    "userId": "abc123def456789abc123def456789ab",
    "deviceId": "ios-iphone-14-pro",
    "publicKey": "abc123def456789abc123def456789abc123def456789abc123def456789abcd"
  },
  "action": "UPDATE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "fields": {
      "priority": 5
    }
  },
  "signature": "b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3",
  "accessList": ["105903772564891234567"],
  "createdAt": {
    "_seconds": 1731751500,
    "_nanoseconds": 0
  }
}
```

**iOS Code to Create:**
```swift
let updateEntry = try ChangeLogEntry.update(
    taskId: task.id,
    updates: ["priority": 5],
    author: author,
    timestamp: LogicalTimestamp(lamport: 2, wall: Date()),
    parents: [previousEntry.id],
    privateKey: privateKey
)

try storage.saveChanges(userId: author.userId, newChanges: [updateEntry])
```

---

### Example 3: MERGE Action (from iOS)
```json
{
  "version": 1,
  "id": "sha256:9b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c",
  "parents": [
    "sha256:ios_complete_node...",
    "sha256:android_update_node..."
  ],
  "timestamp": {
    "lamport": 12,
    "wall": "2025-11-16T10:10:00.000Z"
  },
  "author": {
    "userId": "abc123def456789abc123def456789ab",
    "deviceId": "ios-iphone-14-pro",
    "publicKey": "abc123def456789abc123def456789abc123def456789abc123def456789abcd"
  },
  "action": "MERGE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "fields": {
      "completedAt": "2025-11-16T10:00:00.000Z",
      "priority": 1
    },
    "conflictResolution": {
      "strategy": "union",
      "preservedFields": ["completedAt", "priority"],
      "source": "automatic"
    }
  },
  "signature": "c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4e5f6789a1b2c3d4",
  "accessList": ["105903772564891234567"],
  "createdAt": {
    "_seconds": 1731751800,
    "_nanoseconds": 0
  }
}
```

**iOS Code to Create:**
```swift
// Detect conflict
if localNode.timestamp.lamport == remoteNode.timestamp.lamport &&
   localNode.id != remoteNode.id {

    // Merge data (union strategy)
    let mergedData: [String: Any] = [
        "completedAt": localNode.data.fields["completedAt"],  // iOS wins
        "priority": remoteNode.data.fields["priority"]        // Android wins
    ]

    let mergeEntry = try ChangeLogEntry.merge(
        taskId: taskId,
        parents: [localNode.id, remoteNode.id],
        mergedData: mergedData,
        author: author,
        timestamp: LogicalTimestamp(lamport: 12, wall: Date()),
        privateKey: privateKey
    )

    try storage.saveChanges(userId: author.userId, newChanges: [mergeEntry])
}
```

---

## Test Execution Plan

### Phase 1: Foundation (Week 1)
- [ ] Set up Firebase staging project
- [ ] Configure iOS test environment (simulator + device)
- [ ] Create test fixtures (30+ tasks with various field combinations)
- [ ] Implement basic sync tests (Scenarios 1-2)

### Phase 2: Cross-Platform (Week 2)
- [ ] Coordinate with Web/Android teams for simultaneous testing
- [ ] Execute Scenarios 3-5 (multi-platform sync)
- [ ] Verify hash consistency across platforms
- [ ] Document any encoding mismatches

### Phase 3: Edge Cases (Week 3)
- [ ] Execute Scenarios 6-8 (edge cases, stress tests)
- [ ] Test with 1000+ tasks (performance validation)
- [ ] Test with special characters, Unicode, long fields
- [ ] Test DAG integrity and parent chain validation

### Phase 4: Resilience (Week 4)
- [ ] Execute Scenario 9 (network interruption)
- [ ] Test offline mode (airplane mode on device)
- [ ] Test recovery from corrupted local storage
- [ ] Test Firebase security rules (access control)

### Phase 5: Full Round-Trip (Week 5)
- [ ] Execute Scenario 10 (all platforms in sequence)
- [ ] Document any platform-specific quirks
- [ ] Create final cross-platform compatibility report
- [ ] Submit findings to ecosystem consolidation agent

---

## Success Metrics

### Protocol Compliance
- **Target:** 100% of nodes pass v1 validation
- **Measurement:** ChangeLogValidator.isValidV1Node() = true for all nodes
- **Threshold:** Zero tolerance for invalid nodes

### Hash Consistency
- **Target:** 100% hash match across platforms
- **Measurement:** iOS SHA-256 == Web SHA-256 == Android SHA-256
- **Threshold:** Any mismatch is a critical bug

### Sync Reliability
- **Target:** 99.9% sync success rate
- **Measurement:** Successful syncs / Total sync attempts
- **Threshold:** < 0.1% failure rate (only network errors acceptable)

### State Consistency
- **Target:** 100% state agreement across platforms
- **Measurement:** iOS reconstructed state == Web state
- **Threshold:** Zero tolerance for state divergence

### Performance
- **Target:** Sync < 2 seconds for 100 tasks
- **Measurement:** Time from syncChanges() call to completion
- **Threshold:** < 10 seconds for 1000 tasks

---

## iOS-Specific Implementation Notes

### Current Gaps to Address

1. **Conflict Resolution Logic:**
   - Implement MERGE node creation in FirebaseSyncService
   - Add conflict detection (same lamport, different IDs)
   - Implement merge strategy (union of non-conflicting fields)

2. **Batch Fetching:**
   - Firebase 'in' query limited to 10 IDs
   - Need to chunk ownedNodes array into batches of 10
   - Implement retry logic for each batch

3. **Offline Mode:**
   - Queue changes when offline
   - Auto-sync when network returns
   - Show offline indicator in UI

4. **Validation at Boundaries:**
   - Validate before saving to local storage
   - Validate before pushing to Firebase
   - Validate after pulling from Firebase
   - Reject invalid nodes immediately

### Test Infrastructure Needed

1. **Mock Firebase:**
   - Create in-memory Firebase mock for unit tests
   - Avoid hitting real Firebase in CI/CD

2. **Network Simulation:**
   - Use Network Link Conditioner on device
   - Simulate packet loss, latency, disconnection

3. **Test Fixtures:**
   - Generate 1000+ test tasks with realistic data
   - Include edge cases (special chars, max lengths, etc.)

4. **Assertion Helpers:**
   - `assertHashMatch(iOS, Web)` - Compare SHA-256 hashes
   - `assertStateMatch(iOS, Android)` - Compare reconstructed state
   - `assertValidV1Node(entry)` - Validate protocol compliance

### Code Locations

**Tests to Create:**
- `Tests/RedoCoreTests/CrossPlatformSyncTests.swift` - Scenarios 1-10
- `Tests/RedoCoreTests/HashConsistencyTests.swift` - Cross-platform hash verification
- `Tests/RedoCoreTests/ConflictResolutionTests.swift` - MERGE node logic
- `Tests/RedoUITests/OfflineModeTests.swift` - Offline/online transitions

**Code to Modify:**
- `Sources/RedoUI/Sync/FirebaseSyncService.swift` - Add conflict detection, batch fetching
- `Sources/RedoCore/Services/ChangeLogValidator.swift` - Add parent chain validation
- `Sources/RedoCore/Storage/ChangeLogStorage.swift` - Add deduplication logic

---

## Collaboration with Other Platforms

### Data to Share with Web/Android/CLI Teams

1. **iOS SHA-256 Hashes:**
   - Share test fixture hashes for cross-platform verification
   - Format: `{ nodeId: "sha256:...", platform: "ios", timestamp: "..." }`

2. **iOS Canonical JSON Output:**
   - Share raw canonical JSON for same test fixtures
   - Verify byte-for-byte matching

3. **iOS Conflict Resolution Strategy:**
   - Document merge logic (union vs. last-write-wins)
   - Share test cases for conflict scenarios

4. **iOS Performance Benchmarks:**
   - Share sync times, memory usage, reconstruction times
   - Compare with other platforms

### Data Needed from Other Platforms

1. **Web Test Fixtures:**
   - Same tasks created on Web, with SHA-256 hashes
   - Used for hash consistency tests

2. **Android Conflict Examples:**
   - MERGE nodes created by Android
   - Used to verify iOS can parse Android's MERGE logic

3. **CLI Canonical JSON:**
   - Raw JSON output from Kotlin CLI
   - Used for byte-for-byte comparison

4. **Firebase Security Rules:**
   - Share staging project rules
   - Verify iOS respects access control

---

## Risk Assessment

### High Risk

1. **Hash Mismatch:**
   - **Risk:** iOS SHA-256 ≠ Web SHA-256 due to canonical JSON differences
   - **Mitigation:** Test against known good hashes from Web, port exact canonical JSON logic
   - **Detection:** Automated hash comparison in CI/CD

2. **Conflict Data Loss:**
   - **Risk:** MERGE node loses data from one platform
   - **Mitigation:** Union strategy preserves all non-conflicting fields
   - **Detection:** Manual inspection of MERGE nodes, automated field count checks

3. **Firebase Security Bypass:**
   - **Risk:** User reads other users' nodes (accessList not enforced)
   - **Mitigation:** Test security rules thoroughly, use Firebase emulator
   - **Detection:** Attempt to read unauthorized nodes in tests

### Medium Risk

1. **Performance Degradation:**
   - **Risk:** Sync takes > 10 seconds for 1000 tasks
   - **Mitigation:** Batch fetching, optimize state reconstruction
   - **Detection:** Performance benchmarks in CI/CD

2. **Offline Queue Overflow:**
   - **Risk:** 1000s of changes queued while offline, memory exhausted
   - **Mitigation:** Limit queue size, paginate sync
   - **Detection:** Memory profiling with Instruments

3. **Unicode Corruption:**
   - **Risk:** Émojis/UTF-8 corrupted during JSON serialization
   - **Mitigation:** Test with comprehensive Unicode test fixtures
   - **Detection:** Byte-for-byte comparison of UTF-8 strings

### Low Risk

1. **Timestamp Format Drift:**
   - **Risk:** iOS generates 4 decimals instead of 3
   - **Mitigation:** Strict ISO 8601 formatter with 3 decimals
   - **Detection:** Regex validation in tests

2. **Lamport Clock Skew:**
   - **Risk:** Lamport clock goes backwards (impossible if implemented correctly)
   - **Mitigation:** Monotonic increment logic, never decrement
   - **Detection:** Assertion in StateReconstructor

---

## Glossary (iOS Context)

- **Change Log:** Array of ChangeLogEntry structs stored in `changes_{userId}.json`
- **State Reconstruction:** Process of replaying change log to produce current task state (StateReconstructor.swift)
- **Canonical JSON:** RFC 8785 compliant JSON serialization (CanonicalJSON.swift)
- **Content Addressing:** SHA-256 hash of canonical JSON (ContentAddressing.swift)
- **Lamport Clock:** Logical timestamp for causal ordering (LogicalTimestamp struct)
- **MERGE Node:** ChangeLogEntry with action=.merge and 2+ parents
- **Firebase Staging:** Test Firebase project (`redo-staging`)
- **Google OAuth ID:** Subject ID from Google Sign-In (e.g., "105903772564891234567")
- **Crypto User ID:** First 32 hex chars of Ed25519 public key
- **Access List:** Array of Google OAuth IDs with read access to a node
- **ownedNodes:** Array of node IDs in `users/{oauthId}/ownedNodes`

---

## Next Steps

### Immediate (This Week)
1. Create `CrossPlatformSyncTests.swift` with Scenario 1-2
2. Set up Firebase staging project for iOS
3. Generate test fixtures (30 tasks)
4. Execute first sync test (Web → iOS)

### Short-Term (Next 2 Weeks)
1. Coordinate with Web/Android teams for simultaneous testing
2. Execute Scenarios 3-5
3. Document any hash mismatches
4. Implement conflict resolution in FirebaseSyncService

### Long-Term (Month 2)
1. Execute all 10 scenarios
2. Create comprehensive test report
3. Submit to ecosystem consolidation agent
4. Plan v2 protocol enhancements (if needed)

---

## Appendix A: Test Data Generator (Swift)

```swift
import Foundation

struct TestDataGenerator {
    static func generateTasks(count: Int) -> [RedoTask] {
        var tasks: [RedoTask] = []
        let priorities = [1, 2, 3, 4, 5]
        let estimates = [15, 30, 60, 120, 240]
        let titles = [
            "Buy groceries",
            "Write tests",
            "Review PR",
            "Deploy to prod",
            "Fix bug #123",
            "Update docs",
            "Refactor code",
            "Add feature",
            "Optimize performance",
            "Security audit"
        ]

        for i in 0..<count {
            let task = RedoTask(
                id: UUID(),
                title: "\(titles[i % titles.count]) (\(i))",
                priority: priorities[i % priorities.count],
                timeEstimate: estimates[i % estimates.count],
                tags: ["test", "auto-generated"],
                createdAt: Date()
            )
            tasks.append(task)
        }

        return tasks
    }

    static func generateEdgeCases() -> [RedoTask] {
        return [
            // Unicode
            RedoTask(
                id: UUID(),
                title: "Test émojis 🚀🎉 and symbols ✓✗",
                priority: 3
            ),
            // Very long title
            RedoTask(
                id: UUID(),
                title: String(repeating: "A", count: 200),
                priority: 1
            ),
            // Special characters
            RedoTask(
                id: UUID(),
                title: "Test \"quotes\" and 'apostrophes' and @#$%^&*()",
                priority: 5
            ),
            // Multiline description
            RedoTask(
                id: UUID(),
                title: "Multiline",
                priority: 2,
                timeEstimate: 60
            )
        ]
    }
}
```

---

## Appendix B: Hash Verification Script (Swift)

```swift
import Foundation
import RedoCrypto

struct HashVerification {
    /// Verify iOS hash matches expected hash from another platform
    static func verifyHash(
        entry: ChangeLogEntry,
        expectedHash: String,
        platform: String
    ) throws {
        let iosHash = try ContentAddressing.calculateChangeId(entry: entry)

        guard iosHash == expectedHash else {
            print("❌ Hash mismatch!")
            print("iOS:      \(iosHash)")
            print("\(platform):  \(expectedHash)")

            // Debug: Print canonical JSON
            let canonicalJSON = try CanonicalJSON.stringify(entry)
            print("\nCanonical JSON (iOS):")
            print(canonicalJSON)

            throw HashMismatchError(
                iosHash: iosHash,
                expectedHash: expectedHash,
                platform: platform
            )
        }

        print("✅ Hash match: \(platform)")
    }

    struct HashMismatchError: Error {
        let iosHash: String
        let expectedHash: String
        let platform: String
    }
}
```

---

## Appendix C: Firebase Verification Script (Swift)

```swift
import Foundation
import FirebaseFirestore

struct FirebaseVerification {
    let db = Firestore.firestore()

    /// Verify node exists in Firebase with correct structure
    func verifyNode(id: String) async throws {
        let doc = try await db.collection("nodes").document(id).getDocument()

        guard doc.exists else {
            throw VerificationError.nodeNotFound(id)
        }

        let data = doc.data()!

        // Check required fields
        guard data["version"] as? Int == 1 else {
            throw VerificationError.invalidVersion
        }

        guard let nodeId = data["id"] as? String,
              nodeId.hasPrefix("sha256:"),
              nodeId.count == 71 else {  // "sha256:" + 64 hex
            throw VerificationError.invalidId
        }

        guard let timestamp = data["timestamp"] as? [String: Any],
              let lamport = timestamp["lamport"] as? Int,
              let wall = timestamp["wall"] as? String,
              lamport > 0,
              wall.hasSuffix("Z") else {
            throw VerificationError.invalidTimestamp
        }

        print("✅ Node \(id) verified in Firebase")
    }

    enum VerificationError: Error {
        case nodeNotFound(String)
        case invalidVersion
        case invalidId
        case invalidTimestamp
    }
}
```

---

## Document Metadata

**Version:** 1.0
**Last Updated:** 2025-11-16
**Author:** Claude (iOS Agent)
**Review Status:** Draft (awaiting consolidation)
**Next Review:** After Phase 1 testing (Week 1)

---

**END OF CROSS-PLATFORM TESTING PROPOSAL - iOS**
