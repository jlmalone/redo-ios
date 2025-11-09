# AI Agent Instructions - Redo iOS

**Last Updated**: January 2025
**Target Audience**: All AI agents (Claude, GPT-4, Gemini, Codex, etc.)

---

## 🚨 CRITICAL: Read This First

**PROTOCOL.md is the source of truth for cross-platform compatibility.**

However, if accessible, the **original PROTOCOL.md in `~/WebstormProjects/redo-web-app/PROTOCOL.md` supersedes** any local copies. The web app is the leader platform and protocol authority.

### Required Reading Order

1. **PROTOCOL.md** (this directory or web app) - Cross-platform protocol specification
2. **CLAUDE.md** (or your agent-specific file) - Platform-specific context and patterns
3. **PLANNING.md** - Architecture decisions and rationale
4. **SESSION_X_SUMMARY.md** - Recent development progress

---

## Project Overview

**Redo iOS** is a native iOS/macOS task management app implementing the v1 event sourcing protocol shared with:
- **Web App** (leader): `~/WebstormProjects/redo-web-app`
- **Android App**: `~/StudioProjects/redo-android`
- **Kotlin CLI**: `~/IdeaProjects/redo`

### Core Architecture: Event Sourcing + Local-First

```
User Action → ChangeLogEntry → Local Storage → State Reconstruction → UI
                    ↓
              Firebase Sync (Background, Optional)
```

**Think Git for Tasks:**
- `getAllTasks()` = `git log` (instant, reads local)
- `createTask()` = `git commit` (instant, writes local)
- `syncChanges()` = `git fetch/push` (async, background)

---

## Non-Negotiable Rules

### 1. STRICT v1 Protocol Compliance

**ZERO tolerance** for invalid nodes. Cross-platform compatibility depends on this.

**v1 Node Requirements:**
- `version` MUST be exactly `1` (integer)
- `id` MUST be `"sha256:"` + 64 lowercase hex chars
- `parents` MUST be array of valid change IDs
- `timestamp.lamport` MUST be integer > 0
- `timestamp.wall` MUST be valid ISO 8601 string
- `author.userId` MUST be 32 lowercase hex chars (first 32 of public key)
- `author.publicKey` (optional) MUST be 64 lowercase hex chars
- `signature` (optional) MUST be 128 lowercase hex chars
- **NO Base58 encoding** (web app's mistake, caused 125+ invalid nodes)
- **NO uppercase hex** (breaks cross-platform hashing)
- **NO legacy v0 support** (only v1 accepted)

**Validation Location**: `Sources/RedoCore/Services/ChangeLogValidator.swift`

**If you consider relaxing these rules, STOP. Read PLANNING.md section 2.2 and the web app's 50+ hours of debugging pain.**

### 2. Content Addressing (Canonical JSON)

All change IDs are SHA-256 hashes of canonical JSON per RFC 8785:
- Keys sorted alphabetically
- No whitespace
- Consistent encoding
- Deterministic across platforms

**Test cross-platform compatibility:**
```swift
let entry = /* same data as Kotlin/TypeScript */
let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
let kotlinHash = "sha256:abc123..."  // From Kotlin test
XCTAssertEqual(iosHash, kotlinHash)  // MUST match
```

**Implementation**: `Sources/RedoCrypto/ContentAddressing.swift`

### 3. Local-First Paradigm

**All operations MUST be instant** (no network blocking):

```swift
// ✅ CORRECT
func loadTasks() async throws {
    // Step 1: Load from local storage (instant)
    let changes = try storage.getAllChanges(userId: userId)
    tasks = try stateReconstructor.reconstructTasks(from: changes)

    // Step 2: Sync in background (non-blocking)
    Task { await syncChanges() }
}

// ❌ WRONG - Blocks UI on network
func loadTasks() async {
    tasks = await firebaseSync.getTasks()  // NO!
}
```

### 4. State = Replay (Never Cache)

Current state is **always** reconstructed from change log:

```swift
// ✅ CORRECT - Reconstruct every time
func getTasks() throws -> [RedoTask] {
    let changes = try storage.getAllChanges(userId: userId)
    return try stateReconstructor.reconstructTasks(from: changes)
}

// ❌ WRONG - Caching violates event sourcing
@AppStorage("cachedTasks") var tasks: Data  // NO!
```

**Why?** Change log is single source of truth. Caching introduces sync issues.

---

## Development Guidelines

### Before Making Changes

1. **Read PROTOCOL.md** - Understand v1 node structure
2. **Review web/Android implementation** - Avoid solved problems
3. **Check protocol impact** - Will this break cross-platform compatibility?
4. **Write tests first** - TDD approach prevents regressions

### Critical Checks

**Before committing code, verify:**

- [ ] Does this change canonical JSON serialization? → Test cross-platform hashing
- [ ] Does this modify validation rules? → Verify against PROTOCOL.md
- [ ] Does this block UI on network? → Refactor to background
- [ ] Does this cache state? → Use event sourcing instead
- [ ] Does this use uppercase hex? → Convert to lowercase
- [ ] Does this support v0 nodes? → Remove legacy support

### Common Pitfalls

#### ❌ Don't Do This

```swift
// 1. Caching task state
@AppStorage("cachedTasks") var tasks: Data

// 2. Blocking UI on network
func loadTasks() async {
    tasks = await firebase.getTasks()  // Blocks!
}

// 3. Mixing token types
keychain.save(firebaseToken, forKey: "googleAccessToken")  // Wrong!

// 4. Relaxing validation
if version == 1 || version == 2 { /* NO legacy! */ }

// 5. Uppercase hex
let hash = data.hexEncodedString(uppercase: true)  // Breaks protocol!

// 6. Modifying existing changes
func updateChange(_ change: ChangeLogEntry) {
    change.data["title"] = newTitle  // Changes are immutable!
}
```

#### ✅ Do This Instead

```swift
// 1. Always reconstruct state
func loadTasks() async throws {
    let changes = try storage.getAllChanges(userId: userId)
    tasks = try stateReconstructor.reconstructTasks(from: changes)
    Task { await syncChanges() }  // Background
}

// 2. Validate at boundaries
func saveChange(_ change: ChangeLogEntry) throws {
    guard validator.isValidV1Node(change) else {
        throw ValidationError.invalidNode
    }
    try storage.saveChanges(userId: userId, newChanges: [change])
}

// 3. Separate credentials
keychain.save(googleOAuthToken, forKey: "googleOAuthToken")
keychain.save(firebaseCustomToken, forKey: "firebaseCustomToken")

// 4. Only v1 protocol
guard change.version == 1 else {
    throw ValidationError.unsupportedVersion
}

// 5. Lowercase hex always
let hash = data.hexEncodedString().lowercased()

// 6. Create new change instead of modifying
let newChange = createChangeLogEntry(
    action: .update,
    taskId: task.guid.uuidString,
    data: ["title": newTitle]
)
try storage.saveChanges(userId: userId, newChanges: [newChange])
```

---

## Project Structure

```
redo-ios/
├── Sources/
│   ├── RedoCore/              # Business logic (platform-agnostic)
│   │   ├── Models/            # RedoTask, TodoTask, ChangeLogEntry
│   │   ├── Services/          # StateReconstructor, ChangeLogValidator, TaskRanking
│   │   └── Storage/           # ChangeLogStorage, KeychainService
│   │
│   ├── RedoCrypto/            # Cryptography (Ed25519, SHA-256, Canonical JSON)
│   │   ├── Ed25519Manager.swift
│   │   ├── ContentAddressing.swift
│   │   └── CanonicalJSON.swift
│   │
│   ├── RedoUI/                # SwiftUI interface
│   │   ├── Views/             # TaskListView, CreateTaskView, AnalyticsView
│   │   ├── ViewModels/        # AppViewModel (MVVM pattern)
│   │   ├── Components/        # MatrixTaskCard, SearchBar, etc.
│   │   ├── Theme/             # MatrixTheme (colors, typography, modifiers)
│   │   └── Sync/              # FirebaseSyncService
│   │
│   ├── RedoWidgets/           # Home Screen widgets (iOS-exclusive)
│   │   └── Views/             # TaskListWidgetView, QuickActionsWidgetView
│   │
│   └── RedoIntents/           # Siri Shortcuts (iOS-exclusive)
│       ├── AppIntents.swift   # iOS 16+ modern App Intents
│       └── IntentHandlers.swift  # iOS 14-15 legacy intents
│
├── Tests/
│   ├── RedoCoreTests/         # Business logic tests
│   └── RedoCryptoTests/       # Cryptography tests
│
├── PROTOCOL.md                # Cross-platform protocol (COPY from web app)
├── PLANNING.md                # Architecture decisions and rationale
├── CLAUDE.md                  # Claude-specific instructions
├── AI.md                      # This file (all agents)
├── GEMINI.md                  # Gemini-specific instructions
├── CODEX.md                   # Codex-specific instructions
├── AGENTS.md                  # Generic AI agent instructions
└── SESSION_X_SUMMARY.md       # Development session summaries
```

---

## Key Algorithms

### 1. State Reconstruction

**Location**: `Sources/RedoCore/Services/StateReconstructor.swift`

```swift
func reconstructTasks(from changes: [ChangeLogEntry]) throws -> [RedoTask] {
    // Step 1: Sort by Lamport clock (causal ordering)
    let sorted = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

    // Step 2: Validate each change
    for change in sorted {
        guard validator.isValidV1Node(change) else {
            throw ValidationError.invalidNode(id: change.id)
        }
    }

    // Step 3: Replay actions sequentially
    var tasks: [UUID: RedoTask] = [:]
    for change in sorted {
        switch change.action {
        case .create:
            tasks[taskId] = createTask(from: change.data)
        case .update:
            tasks[taskId]?.update(from: change.data)
        case .delete:
            tasks[taskId] = nil
        // ... etc
        }
    }

    return Array(tasks.values)
}
```

### 2. Enhanced Task Ranking

**Location**: `Sources/RedoCore/Services/TaskRanking.swift`

```swift
func calculateRank(task: RedoTask, currentTime: Date = Date()) -> Float {
    var rank = Float(task.priority)  // Base: 1-5

    // Urgency multiplier (exponential based on days overdue)
    if let dueDate = task.dueDate, dueDate < currentTime {
        let daysOverdue = currentTime.timeIntervalSince(dueDate) / 86400
        rank *= Float(pow(2.0, min(daysOverdue, 10)))  // Cap at 2^10 = 1024x
    }

    // Circadian bonus (5am-12pm = +10%, 12pm-8pm = +20%, 8pm-5am = -10%)
    let hour = Calendar.current.component(.hour, from: currentTime)
    let circadianBonus: Float = {
        switch hour {
        case 5..<12: return 1.1   // Morning boost
        case 12..<20: return 1.2  // Afternoon boost
        default: return 0.9       // Evening penalty
        }
    }()
    rank *= circadianBonus

    // Recency bonus (newer tasks slightly higher)
    let daysSinceCreated = currentTime.timeIntervalSince(task.created) / 86400
    let recencyBonus = max(1.0, 1.2 - Float(daysSinceCreated * 0.01))
    rank *= recencyBonus

    return rank
}
```

### 3. Content Addressing (SHA-256)

**Location**: `Sources/RedoCrypto/ContentAddressing.swift`

```swift
func calculateChangeId(entry: ChangeLogEntry) throws -> String {
    // Step 1: Serialize to canonical JSON
    let canonicalJSON = try CanonicalJSON.serialize(entry)

    // Step 2: SHA-256 hash
    let data = Data(canonicalJSON.utf8)
    let hash = SHA256.hash(data: data)

    // Step 3: Hex encode (lowercase!)
    let hexHash = hash.compactMap { String(format: "%02x", $0) }.joined()

    return "sha256:\(hexHash)"
}
```

---

## Cross-Platform Compatibility

### Testing Against Other Platforms

**Hash Consistency Test:**
```swift
func testHashMatchesKotlin() throws {
    let entry = ChangeLogEntry(/* same data as Kotlin test */)
    let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
    let kotlinHash = "sha256:abc123..."  // From Kotlin test
    XCTAssertEqual(iosHash, kotlinHash)
}
```

**Signature Verification Test:**
```swift
func testEd25519CompatibilityWithWeb() throws {
    let message = "test"
    let privateKey = "abc123..."  // Same key as web test
    let signature = try Ed25519Manager.sign(string: message, privateKeyHex: privateKey)

    // Paste signature into web app console:
    // > Ed25519.verify(publicKey, signature, "test")
    // Should return true
}
```

### Firebase Data Structure

**MUST match web/Android exactly:**

```
nodes/                              # Global collection
  {nodeId}/
    id: "sha256:..."
    version: 1
    parents: ["sha256:..."]
    timestamp: { lamport: 5, wall: "2025-01-09T..." }
    author: {
      userId: "abc123...",         # Crypto userId (first 32 of public key)
      deviceId: "...",
      publicKey: "abc123..."        # Full Ed25519 public key (64 hex)
    }
    action: "CREATE"
    taskId: "uuid"
    data: { /* task fields */ }
    signature: "...",
    accessList: ["105903..."],      # Google OAuth IDs
    createdAt: Timestamp

users/
  {googleOAuthId}/                  # Google OAuth subject ID (NOT crypto userId)
    ownedNodes: ["sha256:...", ...]
```

**Critical Distinctions:**
- `author.userId` = First 32 hex chars of Ed25519 public key (crypto identity)
- `users/{googleOAuthId}` = Google OAuth subject ID (Firebase auth identity)
- These are **different** and must not be confused!

---

## Common Tasks

### Adding a New Action Type

1. **Update ChangeAction enum** (`Sources/RedoCore/Models/ChangeLogEntry.swift`):
   ```swift
   public enum ChangeAction: String, Codable {
       case create = "CREATE"
       case update = "UPDATE"
       case snooze = "SNOOZE"  // NEW
   }
   ```

2. **Add handler in StateReconstructor** (`Sources/RedoCore/Services/StateReconstructor.swift`):
   ```swift
   switch change.action {
   case .snooze:
       if let taskId = UUID(uuidString: change.taskId),
          let snoozeUntil = change.data["snoozeUntil"] as? String,
          let date = ISO8601DateFormatter().date(from: snoozeUntil) {
           tasks[taskId]?.snoozedUntil = date
       }
   }
   ```

3. **Update web/Android implementations** to match

4. **Write tests** for new action type

### Adding a New UI View

1. **Follow Matrix theme patterns** (`Sources/RedoUI/Theme/MatrixTheme.swift`):
   ```swift
   struct MyNewView: View {
       var body: some View {
           ZStack {
               Color.matrixBackground.ignoresSafeArea()

               VStack(spacing: .matrixSpacingLarge) {
                   Text("Title")
                       .font(.matrixTitle1)
                       .foregroundColor(.matrixNeon)
                       .neonGlow()
               }
           }
       }
   }
   ```

2. **Use Matrix color palette**:
   - `.matrixBackground` - #020B09 (dark green-black)
   - `.matrixNeon` - #00FFB8 (neon cyan)
   - `.matrixTextPrimary` - #B8FFE6 (light cyan)
   - `.matrixTextSecondary` - #80BFA3 (muted green)

3. **Add accessibility** (VoiceOver support):
   ```swift
   .accessibilityLabel("Task: \(task.title)")
   .accessibilityHint("Double tap to open task details")
   .accessibilityIdentifier("task_card_\(task.guid)")
   ```

### Debugging Sync Issues

1. **Check Firebase path matching**:
   ```swift
   // iOS path: nodes/{nodeId}
   // Web path: nodes/{nodeId}
   // Must match exactly!
   ```

2. **Verify OAuth vs Crypto userId**:
   ```swift
   let oauthId = keychain.loadGoogleOAuthId()  // For Firebase paths
   let cryptoUserId = keychain.loadUserId()    // For node signing
   // These are DIFFERENT!
   ```

3. **Enable Firebase debug logging**:
   ```swift
   FirebaseConfiguration.shared.setLoggerLevel(.debug)
   ```

4. **Check change log validation**:
   ```swift
   let changes = try storage.getAllChanges(userId: userId)
   for change in changes {
       guard validator.isValidV1Node(change) else {
           print("Invalid node: \(change.id)")
       }
   }
   ```

---

## Performance Targets

| Metric | Target | Method |
|--------|--------|--------|
| Task list render | < 16ms | 60 FPS smooth scrolling |
| State reconstruction (1000 tasks) | < 100ms | Efficient replay algorithm |
| Local operations (create/update) | < 50ms | Direct file I/O |
| Firebase sync (background) | < 500ms | Non-blocking async |
| Change log file size (1000 tasks) | ~1MB | ~1KB per task |
| Memory usage (typical) | < 10MB | Efficient data structures |

---

## Security & Privacy

### Cryptography

- **Ed25519** for signatures (CryptoKit hardware-accelerated)
- **SHA-256** for content addressing
- **Canonical JSON** for deterministic serialization

### Key Storage

- **Private keys** in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **Public keys** in Keychain (for backup)
- **NO keys** in UserDefaults/plist files

### Data Privacy

- Change log encrypted at rest (iOS default)
- Firebase data encrypted in transit (TLS)
- Firebase data encrypted at rest (Google Cloud default)
- Optional: End-to-end encryption (future feature)

---

## When You're Stuck

**Reference implementations:**
1. **Web app** (leader): `~/WebstormProjects/redo-web-app/src/models/RedoNode.ts` (1,738 lines)
2. **Android**: `~/StudioProjects/redo-android/app/src/main/java/vision/salient/redo/`
3. **Kotlin CLI**: `~/IdeaProjects/redo/core/src/main/kotlin/vision/salient/redo/model/`

**Documentation:**
- **PROTOCOL.md** (web app): Cross-platform v1 specification
- **ARCHITECTURE.md** (web app): Design rationale and decisions
- **PLANNING.md** (iOS): Architecture decisions specific to iOS
- **SESSION_X_SUMMARY.md**: Recent development progress

**Debug checklist:**
- [ ] Read PROTOCOL.md section on the relevant feature
- [ ] Compare iOS implementation to web/Android
- [ ] Check if change breaks cross-platform compatibility
- [ ] Verify tests pass (`swift test`)
- [ ] Test against web/Android if protocol-related

---

## Current Development Status

**Foundation Phase** ✅ Complete
- Core models (RedoTask, TodoTask, ChangeLogEntry)
- Cryptography (Ed25519, SHA-256, canonical JSON)
- State reconstruction engine
- Local storage (file-based change log)
- Firebase sync service
- SwiftUI UI (Matrix theme)
- Basic test coverage

**iOS-Specific Features** ✅ Complete
- Home Screen widgets (task list + stats)
- Siri Shortcuts integration (create/complete/view tasks)
- Saved filter presets (quick-apply combinations)
- Advanced analytics (trends, predictions, insights)

**Next Focus Areas:**
- Comprehensive test coverage
- Performance optimization
- UI/UX polish
- App Store preparation
- Cross-platform sync verification

See `SESSION_4_SUMMARY.md` for latest development progress.

---

## Final Reminders

1. **PROTOCOL.md is law** - Cross-platform compatibility depends on strict adherence
2. **Web app PROTOCOL.md supersedes** any local copies if accessible
3. **Local-first always** - Never block UI on network operations
4. **Event sourcing always** - Never cache state, always reconstruct
5. **Test cross-platform** - Hash compatibility is non-negotiable
6. **v1 only** - Zero tolerance for invalid/legacy nodes

**When in doubt, ask:** "Would this break sync with web/Android?" If yes, don't do it.

---

**End of AI.md**

Read CLAUDE.md / GEMINI.md / CODEX.md / AGENTS.md for agent-specific instructions.
