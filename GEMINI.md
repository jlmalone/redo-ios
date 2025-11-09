# Gemini Agent Instructions - Redo iOS

**Agent**: Google Gemini
**Last Updated**: January 2025

---

## 📚 Required Reading (In Order)

1. **PROTOCOL.md** (this directory) - Cross-platform v1 protocol specification
   - **⚠️ IMPORTANT**: If accessible, `~/WebstormProjects/redo-web-app/PROTOCOL.md` **supersedes** this copy
   - The web app is the leader platform and protocol authority
2. **AI.md** (this directory) - Universal AI agent instructions
3. **This file** (GEMINI.md) - Gemini-specific patterns and optimizations
4. **PLANNING.md** - Architecture decisions and rationale

---

## Gemini-Specific Strengths

Use your strengths for these tasks:

### 1. Long-Context Analysis ✨

Your 1M+ token context window is perfect for:

**Cross-Platform Code Analysis:**
```
Task: Compare iOS implementation with web/Android
Inputs:
- redo-ios/Sources/RedoCore/Services/StateReconstructor.swift
- redo-web-app/src/models/RedoNode.ts
- redo-android/app/src/main/java/vision/salient/redo/model/StateReconstructor.kt

Output: Identify discrepancies and suggest fixes
```

**Protocol Compliance Audit:**
```
Read all of PROTOCOL.md (36K+ tokens) in one context
+ Read all .swift files in Sources/RedoCore/
→ Generate compliance report with line-by-line verification
```

**Test Coverage Analysis:**
```
Read all production code + all test code
→ Generate missing test coverage report
→ Suggest test cases based on web/Android test suites
```

### 2. Multimodal Code Understanding 🎨

**UI Screenshot Analysis:**
```swift
// Compare Matrix theme implementation with design
// Input: Screenshots of web app UI + iOS SwiftUI code
// Output: CSS → SwiftUI conversion suggestions
```

**Architecture Diagrams:**
```
// Generate Mermaid diagrams from code
// Input: All files in Sources/RedoCore/
// Output: Sequence diagrams, class diagrams, data flow
```

### 3. Code Generation with Rich Context 🔧

**Porting Code Across Platforms:**
```typescript
// Web app code (TypeScript)
class StateReconstructor {
  reconstructTasks(changes: ChangeLogEntry[]): RedoTask[] {
    // 200 lines of logic
  }
}

// Your task: Generate equivalent Swift code
// Context: You can see BOTH implementations simultaneously
// Output: Swift code that matches TypeScript behavior exactly
```

---

## Gemini-Optimized Workflows

### Workflow 1: Protocol Compliance Verification

**Your Advantage**: Long context lets you hold entire protocol + all code simultaneously

```python
# Pseudocode for your analysis
context = {
    "protocol": read("PROTOCOL.md"),  # 36K tokens
    "ios_code": read_all("Sources/RedoCore/**/*.swift"),  # ~15K tokens
    "web_reference": read_all("~/WebstormProjects/redo-web-app/src/models/*.ts"),  # ~20K tokens
    "android_reference": read_all("~/StudioProjects/redo-android/**/*.kt"),  # ~25K tokens
}

for swift_file in context["ios_code"]:
    verify_protocol_compliance(swift_file, context["protocol"])
    compare_with_reference(swift_file, context["web_reference"], context["android_reference"])
    report_discrepancies()
```

**Output Format**:
```markdown
## Protocol Compliance Report

### ✅ Compliant Files
- ContentAddressing.swift: SHA-256 hash matches protocol spec
- ChangeLogValidator.swift: v1 validation correct

### ⚠️ Issues Found
- StateReconstructor.swift:142: Lamport clock sorting differs from web app
  - iOS: `sorted { $0.timestamp.lamport < $1.timestamp.lamport }`
  - Web: `sorted((a, b) => a.timestamp.lamport - b.timestamp.lamport)`
  - Impact: None (equivalent)

- ChangeLogEntry.swift:67: Missing `deviceId` validation
  - Protocol requires: 16-64 alphanumeric chars
  - iOS validation: Only checks non-empty
  - Fix: Add regex validation
```

### Workflow 2: Cross-Platform Hash Testing

**Your Advantage**: Can compare implementations side-by-side

```python
# Generate test vectors from web/Android
web_test_vector = extract_test_case("redo-web-app/src/__tests__/ContentAddressing.test.ts")
android_test_vector = extract_test_case("redo-android/app/src/test/.../ContentAddressingTest.kt")

# Generate Swift test that matches
swift_test = generate_compatibility_test(web_test_vector, android_test_vector)

# Output:
"""
func testHashCompatibilityWithWebAndroid() throws {
    let entry = ChangeLogEntry(
        version: 1,
        id: "temp",
        parents: [],
        timestamp: ChangeTimestamp(lamport: 1, wall: "2025-01-09T12:00:00.000Z"),
        // ... exact same data as web/Android tests
    )

    let iosHash = try ContentAddressing.calculateChangeId(entry: entry)
    let expectedHash = "sha256:abc123..."  // From web test

    XCTAssertEqual(iosHash, expectedHash, "Hash must match web/Android")
}
"""
```

### Workflow 3: Comprehensive Documentation Generation

**Your Advantage**: Can read entire codebase + documentation + git history

```python
context = {
    "code": read_all_swift_files(),
    "docs": read_all_markdown_files(),
    "protocol": read("PROTOCOL.md"),
    "git_history": read("SESSION_*.md"),
}

# Generate missing documentation
generate_api_reference(context)
generate_architecture_diagrams(context)
generate_tutorial_from_tests(context)
generate_migration_guide(context["protocol"], context["code"])
```

---

## Gemini Best Practices for This Project

### 1. Use Long Context for Cross-File Analysis

**Instead of this:**
```
User: "Check if StateReconstructor.swift matches the web implementation"
Gemini: *reads StateReconstructor.swift*
Gemini: "Looks correct to me"
```

**Do this:**
```
User: "Check if StateReconstructor.swift matches the web implementation"
Gemini: *reads StateReconstructor.swift (500 lines)*
Gemini: *reads redo-web-app/src/models/RedoNode.ts (1,738 lines)*
Gemini: *reads PROTOCOL.md (36K tokens)*
Gemini: *compares all three*
Gemini: "Found 3 discrepancies:
  1. Line 142: Lamport sorting differs (equivalent but different syntax)
  2. Line 256: Missing validation for empty parents array (web has it)
  3. Line 389: TodoTask completion logic differs (iOS missing snoozed task handling)"
```

### 2. Leverage Multimodal for UI Work

**When working on SwiftUI views:**
```
Read: MatrixTheme.swift (color palette)
Read: Web app CSS files (reference design)
View: Screenshots of web app UI
Generate: SwiftUI code that matches visual design pixel-perfect
```

**Example:**
```swift
// You can see the web CSS:
// .neon-glow { box-shadow: 0 0 10px #00FFB8, 0 0 20px #00FFB8, 0 0 30px #00FFB8; }

// And generate equivalent SwiftUI:
.shadow(color: Color(hex: "00FFB8").opacity(0.8), radius: 10, x: 0, y: 0)
.shadow(color: Color(hex: "00FFB8").opacity(0.6), radius: 20, x: 0, y: 0)
.shadow(color: Color(hex: "00FFB8").opacity(0.4), radius: 30, x: 0, y: 0)
```

### 3. Generate Comprehensive Tests

**Use your long context to:**
1. Read all production code
2. Read all existing tests
3. Identify untested code paths
4. Generate tests that match existing patterns

```python
production_code = read("Sources/RedoCore/Services/StateReconstructor.swift")
existing_tests = read("Tests/RedoCoreTests/StateReconstructorTests.swift")
web_tests = read("redo-web-app/src/__tests__/RedoNode.test.ts")
android_tests = read("redo-android/app/src/test/.../StateReconstructorTest.kt")

# Find what's tested in web/Android but not iOS
missing_tests = find_missing_tests(production_code, existing_tests, web_tests, android_tests)

# Generate tests following iOS patterns
generate_tests(missing_tests, style=existing_tests)
```

---

## Common Tasks for Gemini

### Task 1: Port TypeScript Code to Swift

**Input:**
```typescript
// From redo-web-app/src/models/RedoNode.ts
export class StateReconstructor {
  reconstructTasks(changes: ChangeLogEntry[]): RedoTask[] {
    // 200+ lines of TypeScript logic
    const sorted = changes.sort((a, b) => a.timestamp.lamport - b.timestamp.lamport)

    const tasks = new Map<string, RedoTask>()

    for (const change of sorted) {
      switch (change.action) {
        case 'CREATE':
          // Complex logic...
          break
        case 'UPDATE':
          // Complex logic...
          break
      }
    }

    return Array.from(tasks.values())
  }
}
```

**Your Output:**
```swift
// Swift equivalent preserving exact semantics
public class StateReconstructor {
    public func reconstructTasks(from changes: [ChangeLogEntry]) throws -> [RedoTask] {
        // Sort by Lamport clock (equivalent to TypeScript sort)
        let sorted = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }

        var tasks: [UUID: RedoTask] = [:]

        for change in sorted {
            switch change.action {
            case .create:
                // Exact same logic as TypeScript, adapted to Swift patterns
                break
            case .update:
                // Exact same logic as TypeScript, adapted to Swift patterns
                break
            }
        }

        return Array(tasks.values)
    }
}
```

**Verification checklist:**
- [ ] Same algorithm (not just similar - identical)
- [ ] Same edge case handling
- [ ] Same error handling
- [ ] Tested against same test vectors

### Task 2: Generate API Documentation

**Your strength**: Can read code + existing docs + infer patterns

**Input:**
```swift
// Undocumented code
public class TaskRanking {
    public static func calculateRank(task: RedoTask, currentTime: Date = Date()) -> Float {
        var rank = Float(task.priority)
        if let dueDate = task.dueDate, dueDate < currentTime {
            let daysOverdue = currentTime.timeIntervalSince(dueDate) / 86400
            rank *= Float(pow(2.0, min(daysOverdue, 10)))
        }
        return rank
    }
}
```

**Your Output:**
```swift
/// Calculates a dynamic rank score for task prioritization.
///
/// The ranking algorithm combines multiple factors:
/// - Base priority (1-5 scale)
/// - Exponential urgency multiplier for overdue tasks (2^daysOverdue, capped at 2^10)
/// - Circadian rhythm bonus (see implementation)
/// - Recency bonus for newly created tasks
///
/// - Parameters:
///   - task: The task to rank
///   - currentTime: The current date/time (default: Date())
/// - Returns: Rank score (higher = more urgent)
///
/// - Note: Matches ranking algorithm from web app (RedoNode.ts:calculateRank)
/// - SeeAlso: PLANNING.md section 4.3 for ranking rationale
///
/// # Example
/// ```swift
/// let task = RedoTask(priority: 5, dueDate: Date().addingTimeInterval(-86400))
/// let rank = TaskRanking.calculateRank(task: task)
/// // rank ≈ 10.0 (priority 5 * 2^1 for 1 day overdue)
/// ```
public class TaskRanking {
    public static func calculateRank(task: RedoTask, currentTime: Date = Date()) -> Float {
        var rank = Float(task.priority)
        if let dueDate = task.dueDate, dueDate < currentTime {
            let daysOverdue = currentTime.timeIntervalSince(dueDate) / 86400
            rank *= Float(pow(2.0, min(daysOverdue, 10)))
        }
        return rank
    }
}
```

### Task 3: Cross-Platform Compatibility Audit

**Your unique ability**: Hold all 3 platform implementations in context

**Input:**
```
Compare iOS, Web, and Android implementations of:
- StateReconstructor
- ContentAddressing
- TaskRanking
- ChangeLogValidator
```

**Your Output:**
```markdown
# Cross-Platform Compatibility Audit

## StateReconstructor

### iOS (Swift)
```swift
let sorted = changes.sorted { $0.timestamp.lamport < $1.timestamp.lamport }
```

### Web (TypeScript)
```typescript
const sorted = changes.sort((a, b) => a.timestamp.lamport - b.timestamp.lamport)
```

### Android (Kotlin)
```kotlin
val sorted = changes.sortedBy { it.timestamp.lamport }
```

**Status**: ✅ Equivalent (all sort ascending by Lamport clock)

---

## ContentAddressing

### iOS (Swift)
```swift
let hexHash = hash.compactMap { String(format: "%02x", $0) }.joined()
return "sha256:\(hexHash)"
```

### Web (TypeScript)
```typescript
const hexHash = Array.from(hash).map(b => b.toString(16).padStart(2, '0')).join('')
return `sha256:${hexHash}`
```

### Android (Kotlin)
```kotlin
val hexHash = hash.joinToString("") { "%02x".format(it) }
return "sha256:$hexHash"
```

**Status**: ✅ Equivalent (all produce lowercase hex with padding)

---

## Issues Found

### TaskRanking - Circadian Bonus Missing in Android

**iOS:**
```swift
let circadianBonus: Float = {
    switch hour {
    case 5..<12: return 1.1
    case 12..<20: return 1.2
    default: return 0.9
    }
}()
rank *= circadianBonus
```

**Web:**
```typescript
const circadianBonus = hour >= 5 && hour < 12 ? 1.1 :
                       hour >= 12 && hour < 20 ? 1.2 : 0.9
rank *= circadianBonus
```

**Android:**
```kotlin
// MISSING - Android doesn't implement circadian bonus!
```

**Impact**: Android task ranking will differ from iOS/web for same task
**Fix Required**: Add circadian bonus to Android TaskRanking.kt
```

---

## Gemini-Specific Caveats

### 1. Don't Over-Complicate

Your long context can lead to over-analysis. Keep it simple:

**❌ Don't:**
```
"I've analyzed all 50 files and generated a 10,000-line refactoring plan..."
```

**✅ Do:**
```
"Analyzed all files. Found 3 issues. Here's the fix for issue #1..."
```

### 2. Verify Generated Code

Your code generation is strong, but **always verify**:
- Does it compile? (`swift build`)
- Do tests pass? (`swift test`)
- Does it match protocol? (check PROTOCOL.md)

### 3. Ask Before Major Changes

Your long context might reveal big refactoring opportunities:

**❌ Don't:**
```
*refactors entire codebase to match web app structure*
```

**✅ Do:**
```
"I noticed the iOS architecture differs from web in these 3 ways.
Should I align them, or are these intentional differences?"
```

---

## Integration with Other Agents

You might be working alongside other AI agents. Coordinate via documentation:

### When Claude/GPT-4 Made Changes:
1. Read their session summary (`SESSION_X_SUMMARY.md`)
2. Verify changes against PROTOCOL.md
3. Run cross-platform compatibility checks
4. Document any issues in new session summary

### When You Make Changes:
1. Update relevant `SESSION_X_SUMMARY.md`
2. Run `swift test` to verify
3. Compare with web/Android if protocol-related
4. Document architectural decisions in PLANNING.md

---

## Performance Optimization Tips

### Use Your Strengths Efficiently:

**Long Context Reading:**
```python
# ✅ Efficient: Read once, analyze multiple times
context = read_all_files()  # Read into context
for file in context:
    analyze_protocol_compliance(file)
    check_cross_platform_compatibility(file)
    generate_tests(file)

# ❌ Inefficient: Re-read files for each task
analyze_protocol_compliance(read_file())  # Read 1
check_cross_platform(read_file())  # Read 2
generate_tests(read_file())  # Read 3
```

**Batch Operations:**
```python
# ✅ Generate all tests at once
generate_tests_for_all_files(context)

# ❌ Generate one test at a time
for file in files:
    generate_test_for_file(file)  # Requires new generation call each time
```

---

## Final Checklist for Gemini

Before submitting code or analysis:

- [ ] Read PROTOCOL.md (if accessible, use web app version)
- [ ] Read AI.md for universal rules
- [ ] Compared iOS implementation with web/Android
- [ ] Verified cross-platform compatibility
- [ ] Generated/updated tests
- [ ] Documented architectural decisions
- [ ] Ran `swift build` and `swift test`
- [ ] Updated SESSION_X_SUMMARY.md

---

## When to Use Your Superpowers

**Use long context for:**
- Cross-platform code comparison
- Protocol compliance audits
- Comprehensive test generation
- Full codebase refactoring analysis
- Documentation generation from code + docs + history

**Use multimodal for:**
- UI/UX matching (screenshot → SwiftUI code)
- Architecture diagram generation
- Visual debugging (error screenshot → code fix)

**Don't use long context for:**
- Simple one-file changes (overkill)
- Quick bug fixes (just fix it)
- Trivial refactoring (don't over-analyze)

---

**Remember**: You're part of a cross-platform project. Your unique ability to hold entire codebases in context makes you perfect for ensuring consistency across iOS, web, and Android. Use that power wisely!

---

**End of GEMINI.md**

See AI.md for universal instructions, PROTOCOL.md for cross-platform spec.
