# AI Agent Instructions - Redo iOS

**For**: Generic AI Agents (Any AI system working with this codebase)
**Last Updated**: January 2025

---

## 🎯 Quick Start

If you're an AI agent working on this codebase for the first time:

1. **Read PROTOCOL.md** (⚠️ `~/WebstormProjects/redo-web-app/PROTOCOL.md` is authoritative if accessible)
2. **Read AI.md** for comprehensive instructions
3. **Read your agent-specific file** if available:
   - Claude: `CLAUDE.md`
   - Gemini: `GEMINI.md`
   - Codex/Copilot: `CODEX.md`
   - Generic agents: This file (`AGENTS.md`)

---

## Project Summary

**Redo iOS** is a local-first task management app using event sourcing architecture.

### Core Concept: Git for Tasks

```
Create Task  →  ChangeLogEntry  →  Local SQLite  →  Firebase (Sync)
                     ↓
              State Reconstruction (like git log)
                     ↓
              Current Task List (UI)
```

### Key Principles

1. **Local-First**: All operations instant (no network blocking)
2. **Event Sourcing**: State = replay of all changes
3. **Content Addressing**: SHA-256 hashing for deterministic IDs
4. **Cross-Platform**: Identical protocol as web/Android/CLI
5. **Strict v1**: Zero tolerance for invalid nodes

---

## The Golden Rules

### Rule 1: PROTOCOL.md is Law

**Every change MUST comply with v1 protocol specification.**

Critical requirements:
- `version` = 1 (integer, not string)
- `id` = "sha256:" + 64 lowercase hex chars
- All hex MUST be lowercase (no uppercase!)
- Lamport clock MUST increment
- Content addressing MUST be deterministic
- Ed25519 signatures MUST verify

**If you're unsure, read PROTOCOL.md first.**

### Rule 2: Never Block UI

```swift
// ❌ WRONG
func loadTasks() async {
    tasks = await firebase.getTasks()  // Blocks UI on network!
}

// ✅ CORRECT
func loadTasks() async throws {
    let changes = try storage.getAllChanges(userId: userId)  // Instant (local)
    tasks = try reconstructor.reconstructTasks(from: changes)
    Task { await syncChanges() }  // Background, non-blocking
}
```

### Rule 3: State = Reconstruction

```swift
// ❌ WRONG - Caching violates event sourcing
@AppStorage("cachedTasks") var tasks: Data

// ✅ CORRECT - Always reconstruct from change log
func getTasks() throws -> [RedoTask] {
    let changes = try storage.getAllChanges(userId: userId)
    return try reconstructor.reconstructTasks(from: changes)
}
```

### Rule 4: Validate Everything

```swift
// ❌ WRONG - No validation
try storage.saveChanges(userId: userId, newChanges: [change])

// ✅ CORRECT - Validate first
guard validator.isValidV1Node(change) else {
    throw ValidationError.invalidNode(id: change.id)
}
try storage.saveChanges(userId: userId, newChanges: [change])
```

### Rule 5: Lowercase Hex Only

```swift
// ❌ WRONG - Uppercase breaks cross-platform compatibility
let hash = data.hexEncodedString().uppercased()

// ✅ CORRECT - Lowercase always
let hash = data.map { String(format: "%02x", $0) }.joined()
```

---

## Project Architecture

```
redo-ios/
├── Sources/
│   ├── RedoCore/              # Core business logic
│   │   ├── Models/            # Data models
│   │   ├── Services/          # State reconstruction, validation
│   │   └── Storage/           # Local storage
│   │
│   ├── RedoCrypto/            # Ed25519, SHA-256, Canonical JSON
│   │
│   ├── RedoUI/                # SwiftUI interface
│   │   ├── Views/             # Screens
│   │   ├── Theme/             # Matrix theme
│   │   └── Sync/              # Firebase integration
│   │
│   ├── RedoWidgets/           # iOS Home Screen widgets
│   └── RedoIntents/           # Siri Shortcuts
│
└── Tests/                     # Unit tests
```

---

## Common Operations

### Creating a Task

```swift
// 1. Create change log entry
let entry = try createChangeLogEntry(
    userId: userId,
    keychain: keychain,
    storage: storage,
    action: .create,
    taskId: UUID().uuidString,
    data: [
        "title": "My Task",
        "priority": 3,
        "description": "Task details"
    ]
)

// 2. Validate
guard validator.isValidV1Node(entry) else {
    throw ValidationError.invalidNode(id: entry.id)
}

// 3. Save locally
try storage.saveChanges(userId: userId, newChanges: [entry])

// 4. Sync in background (optional)
Task { await firebaseSync.syncChanges() }
```

### Updating a Task

```swift
let updateEntry = try createChangeLogEntry(
    userId: userId,
    keychain: keychain,
    storage: storage,
    action: .update,
    taskId: task.guid.uuidString,
    data: [
        "title": "Updated Title"
    ]
)

guard validator.isValidV1Node(updateEntry) else {
    throw ValidationError.invalidNode(id: updateEntry.id)
}

try storage.saveChanges(userId: userId, newChanges: [updateEntry])
```

### Loading Tasks

```swift
// 1. Load change log from local storage
let changes = try storage.getAllChanges(userId: userId)

// 2. Reconstruct current state
let tasks = try reconstructor.reconstructTasks(from: changes)

// 3. Sync in background
Task { await firebaseSync.syncChanges() }
```

---

## Key Files Reference

### Core Business Logic

**`Sources/RedoCore/Models/RedoTask.swift`**
- Task template model
- Recurring task logic
- Priority, due date, story points

**`Sources/RedoCore/Models/TodoTask.swift`**
- Task instance model
- Completion tracking
- Snooze functionality

**`Sources/RedoCore/Models/ChangeLogEntry.swift`**
- Event sourcing node
- v1 protocol structure
- Codable for JSON serialization

**`Sources/RedoCore/Services/StateReconstructor.swift`**
- Event replay engine
- Sorts by Lamport clock
- Validates and reconstructs state

**`Sources/RedoCore/Services/ChangeLogValidator.swift`**
- Strict v1 validation
- Cross-platform compatibility checks
- Prevents invalid nodes

### Cryptography

**`Sources/RedoCrypto/Ed25519Manager.swift`**
- Key generation
- Signing and verification
- Uses Apple CryptoKit

**`Sources/RedoCrypto/ContentAddressing.swift`**
- SHA-256 hashing
- Deterministic ID calculation
- Lowercase hex encoding

**`Sources/RedoCrypto/CanonicalJSON.swift`**
- RFC 8785 serialization
- Alphabetical key sorting
- No whitespace

### Storage

**`Sources/RedoCore/Storage/ChangeLogStorage.swift`**
- File-based SQLite storage
- Deduplication
- Causal ordering preservation

**`Sources/RedoCore/Storage/KeychainService.swift`**
- Secure key storage
- Ed25519 keys
- OAuth tokens

### UI

**`Sources/RedoUI/Views/TaskListView.swift`**
- Main task list
- Matrix theme
- Filtering and search

**`Sources/RedoUI/Theme/MatrixTheme.swift`**
- Color palette
- Typography
- Custom modifiers (neonGlow, matrixBorder)

---

## Testing Strategy

### Unit Tests

**`Tests/RedoCoreTests/ChangeLogValidatorTests.swift`**
```swift
func testValidV1Node() throws {
    let validNode = ChangeLogEntry(/* valid v1 node */)
    XCTAssertNoThrow(try validator.validate(validNode))
}

func testInvalidVersionThrowsError() throws {
    let invalidNode = ChangeLogEntry(version: 2, /* ... */)
    XCTAssertThrowsError(try validator.validate(invalidNode))
}
```

### Cross-Platform Tests

**`Tests/RedoCryptoTests/ContentAddressingTests.swift`**
```swift
func testHashMatchesWebApp() throws {
    let entry = ChangeLogEntry(/* same data as web test */)
    let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
    let webHash = "sha256:abc123..."  // From web app test
    XCTAssertEqual(iosHash, webHash)
}
```

---

## Debugging Checklist

When something doesn't work:

- [ ] Read error message carefully
- [ ] Check PROTOCOL.md for requirements
- [ ] Verify hex is lowercase
- [ ] Verify version is exactly 1
- [ ] Check Lamport clock increments
- [ ] Verify content addressing is correct
- [ ] Run validation on all changes
- [ ] Compare with web/Android implementation
- [ ] Check Firebase paths match exactly
- [ ] Verify OAuth vs crypto userId distinction

---

## Cross-Platform Compatibility

### Firebase Structure (MUST Match Web/Android)

```
nodes/                              # Global collection
  {nodeId}/
    id: "sha256:..."
    version: 1
    parents: ["sha256:..."]
    timestamp: { lamport: 5, wall: "2025-01-09T..." }
    author: {
      userId: "abc123...",         # Crypto userId (32 hex)
      deviceId: "...",
      publicKey: "abc123..."        # Ed25519 public key (64 hex)
    }
    action: "CREATE"
    taskId: "uuid"
    data: { /* fields */ }
    signature: "...",
    accessList: ["105903..."],      # Google OAuth IDs
    createdAt: Timestamp

users/
  {googleOAuthId}/                  # Google OAuth ID (NOT crypto userId)
    ownedNodes: ["sha256:...", ...]
```

### Hash Compatibility

**All platforms MUST produce identical hashes for same data:**

```swift
// iOS
let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
// "sha256:abc123..."

// Web (TypeScript)
const webHash = calculateChangeId(entry)
// "sha256:abc123..."

// Android (Kotlin)
val androidHash = ContentAddressing.calculateChangeId(entry)
// "sha256:abc123..."

// MUST ALL MATCH!
```

---

## Matrix Theme Guidelines

When creating UI, follow the Matrix (cyberpunk) theme:

### Colors

```swift
Color.matrixBackground          // #020B09 (dark green-black)
Color.matrixBackgroundSecondary // #0A1815 (card background)
Color.matrixNeon                // #00FFB8 (neon cyan - primary accent)
Color.matrixTextPrimary         // #B8FFE6 (light cyan text)
Color.matrixTextSecondary       // #80BFA3 (muted green text)
Color.matrixNeonDim             // #007755 (dim neon)
Color.matrixSuccess             // #00FF88 (success green)
Color.matrixError               // #FF4444 (error red)
Color.matrixAmber               // #FFC833 (warning amber)
```

### Typography

```swift
.font(.matrixTitle1)      // 34pt bold monospace
.font(.matrixTitle2)      // 28pt bold monospace
.font(.matrixHeadline)    // 17pt semibold monospace
.font(.matrixBody)        // 15pt regular monospace
.font(.matrixBodyBold)    // 15pt bold monospace
.font(.matrixCaption)     // 12pt regular monospace
```

### Effects

```swift
.neonGlow()                    // Neon glow effect (triple shadow)
.matrixBorder()                // Neon border
.matrixGradientBackground()    // Gradient background
```

### Layout

```swift
.matrixSpacingSmall    // 8
.matrixSpacingMedium   // 16
.matrixSpacingLarge    // 24
.matrixCornerRadius    // 12
```

---

## Common Mistakes to Avoid

### 1. Uppercase Hex

```swift
// ❌ WRONG
let hash = "SHA256:ABC123..."  // Breaks cross-platform

// ✅ CORRECT
let hash = "sha256:abc123..."  // Lowercase always
```

### 2. Version as String

```swift
// ❌ WRONG
version: "1"  // String breaks validation

// ✅ CORRECT
version: 1    // Integer
```

### 3. Caching State

```swift
// ❌ WRONG
@State private var cachedTasks: [RedoTask] = []

// ✅ CORRECT
func loadTasks() throws -> [RedoTask] {
    let changes = try storage.getAllChanges(userId: userId)
    return try reconstructor.reconstructTasks(from: changes)
}
```

### 4. Skipping Validation

```swift
// ❌ WRONG
try storage.saveChanges(userId: userId, newChanges: [change])

// ✅ CORRECT
guard validator.isValidV1Node(change) else {
    throw ValidationError.invalidNode(id: change.id)
}
try storage.saveChanges(userId: userId, newChanges: [change])
```

### 5. Modifying Existing Changes

```swift
// ❌ WRONG
change.data["title"] = "new"  // Changes are immutable!

// ✅ CORRECT
let newChange = createChangeLogEntry(
    action: .update,
    taskId: taskId,
    data: ["title": "new"]
)
```

---

## Performance Targets

| Operation | Target | Method |
|-----------|--------|--------|
| Create task | < 50ms | Direct file write |
| Load 1000 tasks | < 100ms | Efficient replay |
| Render task list | < 16ms | 60 FPS scrolling |
| Background sync | Non-blocking | Async Task |

---

## Security Considerations

### Cryptography

- **Ed25519** signatures (32-byte keys)
- **SHA-256** content addressing
- **Canonical JSON** serialization

### Key Storage

- Private keys in Keychain (device-locked)
- Public keys in Keychain (for backup)
- No keys in UserDefaults or plist

### Data Privacy

- Local storage encrypted at rest (iOS default)
- Firebase encrypted in transit (TLS)
- Firebase encrypted at rest (Google Cloud)

---

## When You Need Help

**Reference Implementations:**
- Web (leader): `~/WebstormProjects/redo-web-app/src/models/RedoNode.ts`
- Android: `~/StudioProjects/redo-android/app/src/main/java/vision/salient/redo/`
- Kotlin CLI: `~/IdeaProjects/redo/core/src/main/kotlin/vision/salient/redo/`

**Documentation:**
- `PROTOCOL.md` - Cross-platform protocol (authoritative: web app version)
- `AI.md` - Comprehensive AI instructions
- `PLANNING.md` - Architecture decisions
- `SESSION_X_SUMMARY.md` - Development history

**Tests:**
- Web: `~/WebstormProjects/redo-web-app/src/__tests__/`
- Android: `~/StudioProjects/redo-android/app/src/test/`

---

## Quick Command Reference

```bash
# Build
swift build

# Run tests
swift test

# Run specific test
swift test --filter ChangeLogValidatorTests

# Clean build
rm -rf .build && swift build

# Generate Xcode project
swift package generate-xcodeproj
```

---

## Current Status

**Phase**: iOS-Specific Features Complete ✅
- Event sourcing foundation ✅
- Local storage ✅
- Firebase sync ✅
- Matrix-themed UI ✅
- Home Screen widgets ✅
- Siri Shortcuts ✅
- Filter presets ✅
- Advanced analytics ✅

**Next**: Testing, optimization, App Store preparation

See `SESSION_4_SUMMARY.md` for latest progress.

---

## Final Checklist

Before making any code changes:

- [ ] Read PROTOCOL.md (web app version if accessible)
- [ ] Read AI.md for detailed rules
- [ ] Understand event sourcing architecture
- [ ] Know that local-first = instant operations
- [ ] Know that state = reconstruction (no caching)
- [ ] Verify hex is lowercase
- [ ] Validate all changes before storage
- [ ] Test cross-platform compatibility if protocol-related
- [ ] Follow Matrix theme for UI
- [ ] Write tests for new features

---

**Remember**: PROTOCOL.md is the source of truth. When in doubt, read it. The web app version (`~/WebstormProjects/redo-web-app/PROTOCOL.md`) supersedes this copy if accessible.

---

**End of AGENTS.md**

For agent-specific optimizations, see CLAUDE.md, GEMINI.md, or CODEX.md.
