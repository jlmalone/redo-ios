# Codex Agent Instructions - Redo iOS

**Agent**: GitHub Copilot / OpenAI Codex
**Last Updated**: January 2025

---

## 📚 Required Reading

1. **PROTOCOL.md** (this directory) - Cross-platform v1 protocol
   - ⚠️ **SOURCE OF TRUTH**: `~/WebstormProjects/redo-web-app/PROTOCOL.md` supersedes this copy
2. **AI.md** (this directory) - Universal AI agent instructions
3. **This file** (CODEX.md) - Codex-specific code generation patterns

---

## Codex Strengths for This Project

You excel at:
- **Pattern recognition** from existing code
- **Incremental code completion** following established patterns
- **Test generation** matching existing test style
- **Boilerplate reduction** via smart completion

---

## Quick Reference: Code Patterns

### 1. ChangeLogEntry Creation

**Pattern to follow** (`Sources/RedoCore/Helpers/ChangeLogHelpers.swift`):

```swift
func createChangeLogEntry(
    userId: String,
    keychain: KeychainService,
    storage: ChangeLogStorage,
    action: ChangeAction,
    taskId: String,
    data: [String: Any]
) throws -> ChangeLogEntry {
    // Step 1: Get Lamport clock
    let existingChanges = try? storage.getAllChanges(userId: userId) ?? []
    let maxLamport = existingChanges.map { $0.timestamp.lamport }.max() ?? 0
    let nextLamport = maxLamport + 1

    // Step 2: Get keys
    guard let publicKeyHex = try? keychain.loadPublicKey(),
          let privateKeyHex = try? keychain.loadPrivateKey() else {
        throw KeychainError.keysNotFound
    }

    let cryptoUserId = String(publicKeyHex.prefix(32))

    // Step 3: Get device ID
    let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

    // Step 4: Create timestamp
    let timestamp = ChangeTimestamp(
        lamport: nextLamport,
        wall: ISO8601DateFormatter().string(from: Date())
    )

    // Step 5: Create author
    let author = ChangeAuthor(
        userId: cryptoUserId,
        deviceId: deviceId,
        publicKey: publicKeyHex
    )

    // Step 6: Create entry (temporary ID)
    var entry = ChangeLogEntry(
        version: 1,
        id: "temp",
        parents: existingChanges.map { $0.id },
        timestamp: timestamp,
        author: author,
        action: action,
        taskId: taskId,
        data: data,
        signature: nil
    )

    // Step 7: Calculate content-addressed ID
    entry.id = try ContentAddressing.calculateChangeId(entry: entry)

    // Step 8: Sign
    let signatureHex = try Ed25519Manager.sign(entry: entry, privateKeyHex: privateKeyHex)
    entry.signature = signatureHex

    return entry
}
```

**When generating similar code, always:**
- Increment Lamport clock
- Get existing parents
- Calculate content-addressed ID
- Sign the entry
- Use lowercase hex everywhere

### 2. State Reconstruction Pattern

**Pattern to follow** (`Sources/RedoCore/Services/StateReconstructor.swift`):

```swift
func reconstructTasks(from changes: [ChangeLogEntry]) throws -> [RedoTask] {
    // ALWAYS sort by Lamport clock first
    let sorted = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

    // Validate each change
    for change in sorted {
        guard validator.isValidV1Node(change) else {
            throw ValidationError.invalidNode(id: change.id)
        }
    }

    // Replay actions
    var tasks: [UUID: RedoTask] = [:]

    for change in sorted {
        guard let taskId = UUID(uuidString: change.taskId) else { continue }

        switch change.action {
        case .create:
            tasks[taskId] = createTaskFromChange(change)
        case .update:
            tasks[taskId]?.update(from: change.data)
        case .delete:
            tasks[taskId] = nil
        // ... other actions
        }
    }

    return Array(tasks.values)
}
```

**When reconstructing state:**
- Sort by Lamport (causal order)
- Validate all changes
- Replay sequentially
- Never skip validation

### 3. Matrix Theme SwiftUI Pattern

**Pattern to follow** (`Sources/RedoUI/Theme/MatrixTheme.swift`):

```swift
struct MyView: View {
    var body: some View {
        ZStack {
            // Background ALWAYS first
            Color.matrixBackground.ignoresSafeArea()

            VStack(spacing: .matrixSpacingLarge) {
                // Header with neon text
                Text("TITLE")
                    .font(.matrixTitle1)
                    .foregroundColor(.matrixNeon)
                    .neonGlow()

                // Content with secondary text
                Text("Subtitle")
                    .font(.matrixBody)
                    .foregroundColor(.matrixTextSecondary)

                // Cards with borders
                VStack {
                    // Card content
                }
                .padding()
                .background(Color.matrixBackgroundSecondary)
                .cornerRadius(.matrixCornerRadius)
                .matrixBorder()
            }
            .padding()
        }
    }
}
```

**Color palette** (always use these):
- `.matrixBackground` - #020B09 (dark background)
- `.matrixBackgroundSecondary` - #0A1815 (card background)
- `.matrixNeon` - #00FFB8 (primary accent)
- `.matrixTextPrimary` - #B8FFE6 (primary text)
- `.matrixTextSecondary` - #80BFA3 (secondary text)
- `.matrixSuccess` - #00FF88 (success state)
- `.matrixError` - #FF4444 (error state)
- `.matrixAmber` - #FFC833 (warning state)

**Spacing** (always use these):
- `.matrixSpacingSmall` - 8
- `.matrixSpacingMedium` - 16
- `.matrixSpacingLarge` - 24
- `.matrixCornerRadius` - 12

**Typography** (always use these):
- `.matrixTitle1` - 34pt bold monospace
- `.matrixTitle2` - 28pt bold monospace
- `.matrixHeadline` - 17pt semibold monospace
- `.matrixBody` - 15pt regular monospace
- `.matrixCaption` - 12pt regular monospace

### 4. Test Pattern

**Pattern to follow** (`Tests/RedoCoreTests/`):

```swift
import XCTest
@testable import RedoCore

final class MyFeatureTests: XCTestCase {
    var storage: ChangeLogStorage!
    var validator: ChangeLogValidator!
    var reconstructor: StateReconstructor!

    override func setUp() {
        super.setUp()
        storage = ChangeLogStorage()
        validator = ChangeLogValidator()
        reconstructor = StateReconstructor()
    }

    override func tearDown() {
        // Clean up test files
        try? FileManager.default.removeItem(at: storage.testFileURL)
        super.tearDown()
    }

    func testBasicFunctionality() throws {
        // Arrange
        let input = /* test data */

        // Act
        let result = /* operation under test */

        // Assert
        XCTAssertEqual(result, expectedValue)
    }

    func testErrorHandling() throws {
        // Arrange invalid input
        let invalidInput = /* bad data */

        // Act & Assert
        XCTAssertThrowsError(try someFunction(invalidInput)) { error in
            XCTAssertTrue(error is MyError)
        }
    }
}
```

**Test naming**:
- `test<Feature><Scenario>` - e.g., `testTaskCreationWithValidData`
- `test<Feature>ThrowsError<Condition>` - e.g., `testValidationThrowsErrorForInvalidVersion`

---

## Autocomplete Context Hints

When you see these patterns, complete with:

### Hint 1: ChangeLogEntry Creation

```swift
// User types:
let entry = createChangeLogEntry(

// You complete:
    userId: userId,
    keychain: keychain,
    storage: storage,
    action: .create,  // or .update, .delete, etc.
    taskId: task.guid.uuidString,
    data: [
        "title": task.title,
        "priority": task.priority,
        // ... other fields
    ]
)
```

### Hint 2: State Reconstruction

```swift
// User types:
func reconstructTasks(from changes:

// You complete:
func reconstructTasks(from changes: [ChangeLogEntry]) throws -> [RedoTask] {
    let sorted = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

    for change in sorted {
        guard validator.isValidV1Node(change) else {
            throw ValidationError.invalidNode(id: change.id)
        }
    }

    var tasks: [UUID: RedoTask] = [:]

    for change in sorted {
        guard let taskId = UUID(uuidString: change.taskId) else { continue }

        switch change.action {
        case .create:
            // TODO: Implement
        case .update:
            // TODO: Implement
        }
    }

    return Array(tasks.values)
}
```

### Hint 3: SwiftUI View

```swift
// User types:
struct MyView: View {
    var body:

// You complete:
struct MyView: View {
    var body: some View {
        ZStack {
            Color.matrixBackground.ignoresSafeArea()

            VStack(spacing: .matrixSpacingLarge) {
                // TODO: Add content
            }
            .padding()
        }
    }
}
```

### Hint 4: Test Case

```swift
// User types:
func testTaskCreation

// You complete:
func testTaskCreationWithValidData() throws {
    // Arrange
    let taskId = UUID()
    let data: [String: Any] = [
        "title": "Test Task",
        "priority": 3
    ]

    let entry = try createChangeLogEntry(
        userId: userId,
        keychain: keychain,
        storage: storage,
        action: .create,
        taskId: taskId.uuidString,
        data: data
    )

    // Act
    let tasks = try reconstructor.reconstructTasks(from: [entry])

    // Assert
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks.first?.title, "Test Task")
    XCTAssertEqual(tasks.first?.priority, 3)
}
```

---

## Common Completions You Should Suggest

### 1. Validation Before Storage

```swift
// User types: storage.saveChanges
// You suggest:
guard validator.isValidV1Node(change) else {
    throw ValidationError.invalidNode(id: change.id)
}
try storage.saveChanges(userId: userId, newChanges: [change])
```

### 2. Error Handling

```swift
// User types: do {
// You suggest:
do {
    try someOperation()
} catch let error as ValidationError {
    print("Validation error: \(error)")
    throw error
} catch {
    print("Unexpected error: \(error)")
    throw error
}
```

### 3. Date Formatting

```swift
// User types: ISO8601
// You suggest:
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let dateString = formatter.string(from: Date())
```

### 4. UUID Conversion

```swift
// User types: UUID(uuidString:
// You suggest:
guard let taskId = UUID(uuidString: change.taskId) else {
    throw ValidationError.invalidTaskId
}
```

### 5. Hex Encoding (ALWAYS lowercase)

```swift
// User types: .hexEncodedString
// You suggest:
let hexString = data.map { String(format: "%02x", $0) }.joined()
// NOT: let hexString = data.map { String(format: "%02X", $0) }.joined()  // ❌ WRONG
```

---

## Anti-Patterns to Avoid

### ❌ Don't Suggest These

```swift
// 1. Uppercase hex
let hash = data.hexEncodedString().uppercased()  // ❌ Breaks protocol

// 2. Caching state
@AppStorage("tasks") var cachedTasks: Data  // ❌ Violates event sourcing

// 3. Blocking UI on network
func loadTasks() async {
    tasks = await firebase.getTasks()  // ❌ Blocks UI
}

// 4. Skipping validation
try storage.saveChanges(userId: userId, newChanges: [change])  // ❌ No validation

// 5. Legacy version support
if change.version == 1 || change.version == 0 { /* ... */ }  // ❌ Only v1

// 6. Modifying existing changes
change.data["title"] = "new title"  // ❌ Changes are immutable
```

### ✅ Suggest These Instead

```swift
// 1. Lowercase hex
let hash = data.map { String(format: "%02x", $0) }.joined()

// 2. Always reconstruct
let changes = try storage.getAllChanges(userId: userId)
let tasks = try reconstructor.reconstructTasks(from: changes)

// 3. Background sync
func loadTasks() async throws {
    let changes = try storage.getAllChanges(userId: userId)  // Instant
    tasks = try reconstructor.reconstructTasks(from: changes)
    Task { await syncChanges() }  // Background
}

// 4. Always validate
guard validator.isValidV1Node(change) else {
    throw ValidationError.invalidNode(id: change.id)
}
try storage.saveChanges(userId: userId, newChanges: [change])

// 5. Only v1
guard change.version == 1 else {
    throw ValidationError.unsupportedVersion
}

// 6. Create new change
let newChange = createChangeLogEntry(
    action: .update,
    taskId: taskId,
    data: ["title": "new title"]
)
```

---

## File-Specific Patterns

### When editing `StateReconstructor.swift`:

```swift
// Always start with:
let sorted = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

// Always validate:
for change in sorted {
    guard validator.isValidV1Node(change) else {
        throw ValidationError.invalidNode(id: change.id)
    }
}

// Always replay:
var tasks: [UUID: RedoTask] = [:]
for change in sorted {
    // Handle action
}
```

### When editing `ContentAddressing.swift`:

```swift
// Always lowercase hex:
let hexHash = hash.compactMap { String(format: "%02x", $0) }.joined()

// Always prefix with "sha256:":
return "sha256:\(hexHash)"

// Always use canonical JSON:
let canonicalJSON = try CanonicalJSON.serialize(entry)
```

### When editing SwiftUI views:

```swift
// Always start with ZStack + background:
var body: some View {
    ZStack {
        Color.matrixBackground.ignoresSafeArea()
        // ... content
    }
}

// Always use Matrix theme:
.font(.matrixBody)
.foregroundColor(.matrixTextPrimary)
.padding(.matrixSpacingMedium)
```

---

## Snippet Shortcuts

If user types these comments, expand to full code:

### `// TODO: create change`

```swift
let entry = try createChangeLogEntry(
    userId: userId,
    keychain: keychain,
    storage: storage,
    action: .create,
    taskId: UUID().uuidString,
    data: [
        "title": title,
        "priority": priority,
        "description": description
    ]
)
try storage.saveChanges(userId: userId, newChanges: [entry])
```

### `// TODO: reconstruct tasks`

```swift
let changes = try storage.getAllChanges(userId: userId)
let tasks = try reconstructor.reconstructTasks(from: changes)
```

### `// TODO: validate change`

```swift
guard validator.isValidV1Node(change) else {
    throw ValidationError.invalidNode(id: change.id)
}
```

### `// TODO: matrix view`

```swift
struct MyView: View {
    var body: some View {
        ZStack {
            Color.matrixBackground.ignoresSafeArea()

            VStack(spacing: .matrixSpacingLarge) {
                // Content here
            }
            .padding()
        }
    }
}
```

---

## Testing Shortcuts

### `// TODO: test creation`

```swift
func testTaskCreation() throws {
    // Arrange
    let entry = try createChangeLogEntry(
        userId: userId,
        keychain: keychain,
        storage: storage,
        action: .create,
        taskId: UUID().uuidString,
        data: ["title": "Test", "priority": 3]
    )

    // Act
    let tasks = try reconstructor.reconstructTasks(from: [entry])

    // Assert
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks.first?.title, "Test")
}
```

### `// TODO: test validation`

```swift
func testValidationThrowsErrorForInvalidNode() throws {
    // Arrange
    let invalidChange = ChangeLogEntry(
        version: 2,  // Invalid!
        id: "sha256:abc",
        // ... rest of fields
    )

    // Act & Assert
    XCTAssertThrowsError(try validator.validate(invalidChange)) { error in
        XCTAssertTrue(error is ValidationError)
    }
}
```

---

## Code Review Checklist

Before suggesting code, verify:

- [ ] Hex encoding is lowercase
- [ ] v1 protocol only (no legacy support)
- [ ] Validation before storage
- [ ] State reconstruction (no caching)
- [ ] Matrix theme colors
- [ ] Error handling present
- [ ] No network blocking in UI
- [ ] Accessibility labels (SwiftUI)
- [ ] Tests match existing pattern
- [ ] Comments explain "why" not "what"

---

## Integration with IDE

### VS Code / Cursor Settings

Add to `.vscode/settings.json`:

```json
{
  "editor.suggest.snippetsPreventQuickSuggestions": false,
  "editor.quickSuggestions": {
    "strings": true
  },
  "files.associations": {
    "*.swift": "swift"
  }
}
```

### Xcode Settings

Enable:
- Code completion
- Suggestion priority: "Exact match"
- Import suggestions

---

## Final Notes

**You excel at:**
- Completing patterns from existing code
- Generating boilerplate following established style
- Suggesting variable names matching convention
- Auto-importing required modules

**You should NOT:**
- Suggest architectural changes (defer to human/Claude)
- Generate large refactorings (too risky)
- Change protocol specifications (read-only for you)
- Modify existing algorithms (unless fixing bugs)

**When uncertain:**
- Follow the pattern in the current file
- Check AI.md for general rules
- Look at similar code in project
- Suggest multiple options, let human choose

---

**End of CODEX.md**

See AI.md for universal instructions, PROTOCOL.md for cross-platform spec.
