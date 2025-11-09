# Claude Agent Instructions - Redo iOS

**Agent**: Anthropic Claude (Sonnet, Opus, Haiku)
**Created**: 2025-11-09
**Last Updated**: January 2025
**Status**: iOS-Specific Features Complete ✅

---

## 📚 Required Reading (In Order)

1. **PROTOCOL.md** (this directory) - Cross-platform v1 protocol specification
   - ⚠️ **SOURCE OF TRUTH**: If accessible, `~/WebstormProjects/redo-web-app/PROTOCOL.md` supersedes this copy
   - The web app is the leader platform and protocol authority
2. **AI.md** (this directory) - Universal AI agent instructions (shared across all AI agents)
3. **This file** (CLAUDE.md) - Claude-specific workflows and patterns
4. **PLANNING.md** - Architecture decisions and rationale
5. **SESSION_X_SUMMARY.md** - Recent development progress

---

## Project Overview

**Redo iOS** is a native iOS task management application implementing the proven v1 event sourcing protocol shared with:
- **Web App** (leader platform): TypeScript/React at `~/WebstormProjects/redo-web-app`
- **Android App**: Kotlin/Jetpack Compose at `~/StudioProjects/redo-android`
- **Kotlin CLI**: Core models at `~/IdeaProjects/redo`

### Core Architecture

```
Event Sourcing + Local-First + Cross-Platform Sync
   ↓
Immutable Change Log (Git-like) → State Reconstruction → Real-time UI
   ↓
Local Storage (Primary) ↔ Firebase (Optional Sync)
```

---

## Critical Protocols

### 1. STRICT v1 VALIDATION

**ZERO tolerance for invalid nodes**. This is non-negotiable for cross-platform compatibility.

**Requirements**:
- `version` MUST be exactly 1
- `id` MUST be "sha256:" + 64 lowercase hex chars
- `parents` MUST be array of valid change IDs
- `timestamp.lamport` MUST be > 0
- `timestamp.wall` MUST be valid ISO 8601
- `author.userId` MUST be 32 lowercase hex chars
- `author.publicKey` (if present) MUST be 64 lowercase hex chars
- `signature` (if present) MUST be 128 lowercase hex chars
- **NO Base58 encoding** (web app's early mistake)
- **NO uppercase hex** (breaks cross-platform hashing)

**Validation Location**: `RedoCore/Services/ChangeLogValidator.swift`

**AI Agent Instruction**: If you ever consider relaxing these rules, STOP and review PLANNING.md section 2.2. The web app spent 50+ hours debugging issues from lax validation.

### 2. CONTENT ADDRESSING

All change IDs are SHA-256 hashes of canonical JSON:
- Keys sorted alphabetically
- No whitespace
- RFC 8785 compliant
- Deterministic across platforms

**Implementation**: `RedoCrypto/ContentAddressing.swift`

**AI Agent Instruction**: Any changes to models MUST preserve canonical JSON compatibility. Test against web/Android hash outputs.

### 3. LOCAL-FIRST PARADIGM

**All operations MUST be instant** (like Git):
- `getAllTasks()` = `git log` (reads local, instant)
- `createTask()` = `git commit` (writes local, instant)
- `syncChanges()` = `git fetch/push` (background, async)

**AI Agent Instruction**: Never block UI on network operations. If you add Firebase calls in the UI layer, you're doing it wrong.

### 4. STATE = REPLAY

Current state is NEVER cached, always reconstructed from change log:
- Load all changes from storage
- Sort by Lamport clock (causal ordering)
- Validate each change (strict v1)
- Replay actions sequentially
- Return reconstructed tasks

**Implementation**: `RedoCore/Services/StateReconstructor.swift`

**AI Agent Instruction**: If you find yourself caching task state in UserDefaults/CoreData, you've misunderstood the architecture. The change log is the single source of truth.

---

## Project Structure

```
redo-ios/
├── Sources/
│   ├── RedoCore/           # Business logic (platform-agnostic)
│   │   ├── Models/         # RedoTask, TodoTask, ChangeLogEntry
│   │   ├── Services/       # StateReconstructor, ChangeLogValidator
│   │   └── Storage/        # ChangeLogStorage, KeychainService
│   │
│   ├── RedoCrypto/         # Cryptography (Ed25519, SHA-256, CanonicalJSON)
│   │   ├── Ed25519Manager.swift
│   │   ├── ContentAddressing.swift
│   │   └── CanonicalJSON.swift
│   │
│   └── RedoUI/             # SwiftUI interface
│       ├── Views/          # TaskListView, CreateTaskView
│       ├── ViewModels/     # AppViewModel
│       ├── Components/     # MatrixTaskCard, etc.
│       ├── Theme/          # MatrixTheme
│       └── Sync/           # FirebaseSyncService
│
├── Tests/
│   ├── RedoCoreTests/      # Business logic tests
│   └── RedoCryptoTests/    # Cryptography tests
│
└── Docs/
    ├── PLANNING.md         # Comprehensive architecture document
    ├── SETUP.md            # Setup instructions
    └── CLAUDE.md           # This file
```

---

## Current Status

### ✅ Completed (Foundation Phase)

1. **Core Models** - RedoTask, TodoTask, ChangeLogEntry with full business logic
2. **Cryptography** - Ed25519 signing, SHA-256 hashing, canonical JSON
3. **State Reconstruction** - Event replay engine with validation
4. **Local Storage** - File-based change log storage + Keychain for keys
5. **Firebase Sync** - Cloud sync service (matches web/Android architecture)
6. **SwiftUI UI** - Matrix-themed TaskListView, CreateTaskView, task cards
7. **View Models** - AppViewModel with MVVM pattern
8. **Test Foundation** - Unit tests for validation and cryptography

### 🚧 Next Steps (Week 2)

1. **Testing**:
   - StateReconstructor tests (port from Android's 18 tests)
   - Storage tests (file operations, deduplication)
   - Cross-platform hash verification
   - UI tests (SwiftUI previews → UI automation)

2. **Additional Views**:
   - TaskDetailView (full task info, history, TODOs)
   - SettingsView (export/import, sync toggle, identity info)
   - HistoryView (DAG visualization like web app)

3. **Firebase Integration**:
   - Google OAuth authentication
   - Real-time sync listener
   - Offline/online status indicator

4. **Polish**:
   - Animations and transitions
   - Haptic feedback
   - Accessibility (VoiceOver, Dynamic Type)
   - Error handling UI

### 📋 Future Enhancements (Week 3+)

1. **Feature Parity**:
   - Calendar view (matching web/Android)
   - Analytics dashboard
   - Advanced filtering and search
   - Task snoozing

2. **iOS-Specific**:
   - Widget (home screen task summary)
   - Live Activities (task completion tracking)
   - Shortcuts integration
   - ShareSheet for task export

3. **Performance**:
   - Change log pagination (for 1000s of tasks)
   - Background sync optimization
   - Memory profiling

---

## Lessons from Web & Android

### Web App Lessons (Applied)

1. **Build Version Enforcement** ✅
   - iOS: Use Xcode build phases to auto-increment CFBundleVersion
   - Prevents re-deployment waste

2. **Token Separation** ✅
   - Google OAuth token (for Google APIs) separate from Firebase token
   - Store in separate Keychain entries (not same key)
   - Web had 50-min bug from mixing these

3. **Hex Encoding Only** ✅
   - All crypto fields lowercase hex (not Base58/Base64)
   - Web had 125 Base58 nodes causing CLI sync failures

4. **Batched Firestore Operations** ✅
   - Implemented from day one (web is planning this)
   - Fetch in chunks of 10 (Firebase 'in' query limit)

### Android Lessons (Applied)

1. **OAuth ID for Storage** ✅
   - Use Google OAuth subject ID for Firebase paths
   - Crypto userId for node signing
   - Android spent Nov 2025 fixing this mismatch

2. **Visual Polish** ✅
   - iOS gets neon glow from day one (Android missing this)
   - Used .shadow() modifiers with multiple layers
   - SF Symbols for consistent iconography

3. **Comprehensive Tests** ✅
   - Ported validation test patterns from Android's 65 tests
   - Cross-platform compatibility tests included

---

## Development Guidelines

### For AI Agents

**Before Making Changes**:
1. Read PLANNING.md (48KB architecture doc)
2. Review relevant web/Android implementation
3. Check if change affects protocol compatibility
4. Write tests FIRST (TDD approach)

**Critical Checks**:
- Does this change modify canonical JSON serialization? → Test cross-platform hashing
- Does this change validation rules? → Verify against PROTOCOL.md
- Does this block UI on network? → Refactor to background
- Does this cache state? → Use event sourcing instead

**When Stuck**:
- Reference web app: `~/WebstormProjects/redo-web-app/src/models/RedoNode.ts` (1,738 lines)
- Reference Android: `~/StudioProjects/redo-android/app/src/main/java/vision/salient/redo/`
- Reference protocol: `~/WebstormProjects/redo-web-app/PROTOCOL.md`

### For Human Developers

**Setup** (see SETUP.md for details):
```bash
cd ~/ios_code/redo-ios
swift build        # Build all modules
swift test         # Run tests
```

**Common Tasks**:
- Add new action type: Update ChangeAction enum, add handler in StateReconstructor
- Add new UI: Follow MatrixTheme.swift patterns, use .matrixGradientBackground(), .neonGlow()
- Debug sync: Check ChangeLogStorage → Firebase paths match web/Android exactly
- Add tests: See Tests/ for examples, port patterns from Android test suite

**Testing Against Web/Android**:
1. Generate keypair in iOS
2. Copy public key to web app localStorage
3. Create task in iOS
4. Verify it appears in web app after sync
5. Create task in web app
6. Verify it appears in iOS after sync

---

## Firebase Architecture

**CRITICAL**: Must match web/Android exactly

### Collections

```
nodes/                          # Global collection (CURRENT)
  {nodeId}/
    id: "sha256:..."
    version: 1
    parents: ["sha256:..."]
    timestamp: { lamport: 5, wall: "2025-11-09T..." }
    author: {
      userId: "abc123...",     # Crypto userId (first 32 of public key)
      deviceId: "...",
      publicKey: "abc123..."   # Full Ed25519 public key (64 hex)
    }
    action: "CREATE"
    taskId: "uuid"
    data: { fields: {...} }
    signature: "..."
    accessList: ["105903..."]  # Google OAuth IDs
    createdAt: Timestamp

users/
  {googleOAuthId}/              # Google OAuth subject ID (NOT crypto userId)
    ownedNodes: ["sha256:...", ...]  # Array of node IDs
```

**Evolution**:
- ❌ PURGED: `users/{oauthId}/changes/{nodeId}` (old web architecture)
- ❌ ABANDONED: `users/{cryptoUserId}/ownedNodes[]` (intermediate Android)
- ✅ CURRENT: `nodes/{nodeId}` + `users/{googleOAuthId}/ownedNodes[]`

**Rationale**: Global nodes collection enables future shared tasks feature. Access control via `accessList` array.

---

## Testing Strategy

### Unit Tests (Current)
- ✅ Ed25519 key generation, signing, verification
- ✅ Change log validation (v1 protocol)
- ⏳ State reconstruction (TODO: port Android's 18 tests)
- ⏳ Storage operations (TODO: file I/O, deduplication)

### Integration Tests (Planned)
- Cross-platform hash consistency (iOS ↔ Kotlin ↔ TypeScript)
- Firebase sync round-trip (iOS → Firebase → iOS)
- Multi-device sync (iOS → Firebase → Android/Web)

### UI Tests (Planned)
- Task creation flow
- Task completion flow
- Filter/search functionality
- Offline mode resilience

### Cross-Platform Tests (Critical)

**Test Vectors** (from web app):
```swift
// Same ChangeLogEntry should produce same hash
let entry = ChangeLogEntry(/* ... */)
let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
let expectedHash = "sha256:abc123..."  // From web/Android
XCTAssertEqual(iosHash, expectedHash)
```

**Ed25519 Compatibility**:
```swift
// Sign in iOS, verify in web/Android
let message = "test"
let signature = try Ed25519Manager.sign(string: message, privateKeyHex: privateKey)
// Paste signature into web app console:
// > Ed25519.verify(publicKey, signature, message)
// Should return true
```

---

## Performance Targets

### Latency
- Task list render: < 16ms (60 FPS)
- State reconstruction: < 100ms (1000 tasks)
- Local operations: < 50ms (create/update/complete)
- Sync: < 500ms (background, non-blocking)

### Memory
- Change log: ~1KB per task (1000 tasks = ~1MB)
- Reconstructed state: ~500B per task (1000 tasks = ~500KB)
- Total memory: < 10MB for typical usage

### Storage
- Change log file: ~1MB per 1000 tasks
- iOS limit: Unlimited (stored in Documents directory)
- Cleanup strategy: Archive old changes after 1 year

---

## Security & Privacy

### Cryptography
- Ed25519 for signatures (32-byte keys)
- SHA-256 for content addressing
- All crypto via Apple CryptoKit (hardware-accelerated)

### Key Storage
- Private keys in Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
- Public keys in Keychain (for backup)
- No keys in UserDefaults/plist files

### Data Privacy
- Change log stored locally (encrypted at rest by iOS)
- Firebase data encrypted in transit (TLS)
- Firebase data encrypted at rest (Google Cloud default)
- Optional: End-to-end encryption (future feature)

### Access Control
- Firebase security rules enforce access via `accessList` array
- Only authenticated users can read/write their nodes
- Multi-user collaboration (future) via shared `accessList`

---

## Common Pitfalls (For AI Agents)

### ❌ Don't Do This

1. **Caching Task State**
   ```swift
   // ❌ WRONG
   @AppStorage("cachedTasks") var tasks: Data
   ```
   Change log is the source of truth. Always reconstruct.

2. **Blocking UI on Network**
   ```swift
   // ❌ WRONG
   func loadTasks() async {
       tasks = await firebaseSync.getTasks()  // Blocks UI!
   }
   ```
   Read from local storage first. Sync in background.

3. **Mixing Token Types**
   ```swift
   // ❌ WRONG
   keychain.save(firebaseToken, forKey: "googleAccessToken")
   ```
   Google OAuth token ≠ Firebase custom token. Separate keys.

4. **Relaxing Validation**
   ```swift
   // ❌ WRONG
   if version == 1 || version == 2 { ... }  // NO legacy support!
   ```
   Only v1 protocol accepted. Period.

5. **Uppercase Hex**
   ```swift
   // ❌ WRONG
   let hash = data.hexEncodedString(uppercase: true)
   ```
   v1 protocol requires lowercase. No exceptions.

### ✅ Do This Instead

1. **Always Reconstruct State**
   ```swift
   func loadTasks() async throws {
       let changes = try storage.getAllChanges(userId: userId)
       tasks = try stateReconstructor.reconstructTasks(from: changes)
       Task { await syncChanges() }  // Background
   }
   ```

2. **Validate at Boundaries**
   ```swift
   func saveChange(_ change: ChangeLogEntry) throws {
       guard validator.isValidV1Node(change) else {
           throw ValidationError.invalidNode
       }
       try storage.saveChanges(userId: userId, newChanges: [change])
   }
   ```

3. **Test Cross-Platform**
   ```swift
   func testHashCompatibility() throws {
       let entry = /* ... */
       let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
       let kotlinHash = "sha256:..."  // From Kotlin test
       XCTAssertEqual(iosHash, kotlinHash)
   }
   ```

---

## File Reference

**Core Business Logic**:
- `Sources/RedoCore/Models/RedoTask.swift` - Task template model
- `Sources/RedoCore/Models/TodoTask.swift` - Task instance model
- `Sources/RedoCore/Models/ChangeLogEntry.swift` - Event sourcing node
- `Sources/RedoCore/Services/StateReconstructor.swift` - Event replay engine
- `Sources/RedoCore/Services/ChangeLogValidator.swift` - v1 protocol validation

**Cryptography**:
- `Sources/RedoCrypto/Ed25519Manager.swift` - Signing and verification
- `Sources/RedoCrypto/ContentAddressing.swift` - SHA-256 hashing
- `Sources/RedoCrypto/CanonicalJSON.swift` - RFC 8785 serialization

**Storage**:
- `Sources/RedoCore/Storage/ChangeLogStorage.swift` - File-based persistence
- `Sources/RedoCore/Storage/KeychainService.swift` - Secure key storage

**UI**:
- `Sources/RedoUI/Views/TaskListView.swift` - Main task list
- `Sources/RedoUI/Views/CreateTaskView.swift` - Task creation
- `Sources/RedoUI/Components/MatrixTaskCard.swift` - Task card component
- `Sources/RedoUI/Theme/MatrixTheme.swift` - Color palette, typography, modifiers
- `Sources/RedoUI/ViewModels/AppViewModel.swift` - Main view model

**Sync**:
- `Sources/RedoUI/Sync/FirebaseSyncService.swift` - Firebase integration

**Tests**:
- `Tests/RedoCoreTests/ChangeLogValidatorTests.swift` - Validation tests
- `Tests/RedoCryptoTests/Ed25519Tests.swift` - Cryptography tests

**Documentation**:
- `PLANNING.md` - Comprehensive architecture (48KB)
- `README.md` - Quick start and overview
- `CLAUDE.md` - This file (AI agent context)
- `SETUP.md` - Setup instructions

---

## External References

**Cross-Platform Protocol**:
- Web: `~/WebstormProjects/redo-web-app/PROTOCOL.md` (1,603 lines)
- Web: `~/WebstormProjects/redo-web-app/ARCHITECTURE.md` (1,363 lines)

**Reference Implementations**:
- Web (leader): `~/WebstormProjects/redo-web-app/src/models/RedoNode.ts`
- Android: `~/StudioProjects/redo-android/app/src/main/java/vision/salient/redo/model/ChangeLog.kt`
- Kotlin CLI: `~/IdeaProjects/redo/core/src/main/kotlin/vision/salient/redo/model/ChangeLog.kt`

**Test Suites**:
- Web: `~/WebstormProjects/redo-web-app/src/__tests__/`
- Android: `~/StudioProjects/redo-android/app/src/test/java/vision/salient/redo/`

---

## Version History

- **v0.1.0** (2025-11-09): Foundation complete
  - Core models, cryptography, state reconstruction
  - Local storage, Firebase sync skeleton
  - SwiftUI UI with Matrix theme
  - Test foundation

- **v0.2.0** (Planned): Feature parity
  - All CRUD operations
  - Firebase OAuth integration
  - Task detail view, settings, history
  - Complete test coverage

- **v1.0.0** (Planned): App Store launch
  - Cross-platform sync verified
  - Performance optimized
  - Accessibility complete
  - Production Firebase project

---

## Questions? Issues?

**For AI Agents**: If uncertain, check:
1. PLANNING.md sections 2-7 (architecture decisions)
2. Web app's ARCHITECTURE.md (design rationale)
3. Android's CROSS_PLATFORM_SYNC_FIXED.md (sync lessons)

**For Developers**: See SETUP.md for getting started.

**End of CLAUDE.md**
