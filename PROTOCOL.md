# REDO v1 Event Model Sourcing Protocol Specification

**Version**: 1.7
**Status**: Stable
**Last Updated**: October 27, 2025

**Copyright © 2025 Salient Vision Technologies, LLC. All rights reserved.**

This document is the **single source of truth** for the REDO distributed event model sourcing protocol. All implementations (TypeScript web app, Kotlin CLI, Android, iOS, Mac, Windows, and Linux Kotlin Multiplatform Desktop) MUST conform to this specification.

---

> **⚠️ BREAKING CHANGE (v1.7)**
> CREATE_TODO now REQUIRES a stable `todoTaskId` field in the payload.
> This fixes a critical determinism flaw where todos were assigned random GUIDs during state reconstruction.
> **ACTION REQUIRED**: All v1.6 and earlier data must be wiped. See Version History for details.

---

## Protocol Philosophy

REDO is a **verifiable, local-first event sourcing protocol** for personal and collaborative task management.
It treats every change as an immutable, signed, and hash-addressed node in a directed acyclic graph (DAG).
The system favors **determinism, explicitness, and recoverability** over convenience.

Key design tenets:
- **Local state is always the source of truth** - devices are autonomous
- **Violations never corrupt valid ancestors** - "Broken Branch" safety model
- **All actions are explicit** - nothing happens implicitly during reconstruction
- **Identical input produces identical output** - cross-platform determinism
- **Recoverability over convenience** - preserve history for resurrection and audit

This section frames the intent behind the strict enforcement rules that follow.

---

## ⚠️ CRITICAL: PROTOCOL v1.5 - STRICT ENFORCEMENT

**NO BACKWARDS COMPATIBILITY. NO LENIENCY. NO EXCEPTIONS.**

As of v1.5 (October 26, 2025), this protocol is **STRICTLY ENFORCED** during active development:

- ❌ **No migration support** for pre-v1.5 data patterns
- ❌ **No graceful degradation** for protocol violations
- ❌ **No "draft mode"** or partial compliance states
- ✅ **Violations prune the broken branch** - invalid node and descendants REJECTED
- ✅ **Ancestor history preserved** - valid parents remain intact
- ✅ **Development policy**: Fix the code, not the protocol

**Enforcement Rules (v1.5) - The "Broken Branch" Model:**

When a protocol violation is detected, the **invalid node and all its descendants are REJECTED** during state reconstruction. The task's valid ancestor history remains intact. State reverts to the longest surviving valid branch.

**Specific Violations:**
1. **Duplicate CREATE** for same taskId → Original CREATE kept; duplicate and all its descendants REJECTED
2. **COMPLETE_TODO** referencing invalid or genesis-created todo → Node and descendants REJECTED
3. **UPDATE** containing forbidden state management fields (todoTasks, archived, deleted, etc.) → Node and descendants REJECTED
4. **DELETE** without deletedChain → Node and descendants REJECTED
5. **Any protocol violation** → Node and descendants REJECTED; ancestor history preserved
6. **Legacy format nodes** → REJECTED (no 32-char GUIDs; strict UUID v4 only)

**Critical Principle**: An invalid node **CANNOT** corrupt its valid parents or ancestors. Only the broken branch (the invalid node + its children) is pruned. The trunk and other branches remain healthy.

**Why this matters:**
- You are in **active development** - strict enforcement prevents bad patterns from spreading
- Once data scales, migration becomes exponentially harder
- Better to crash early than silently corrupt distributed state
- Protocol compliance is non-negotiable for distributed consensus

**When backwards compatibility MIGHT be added:**
- After v1.5 stabilizes and ships to production users
- Only if absolutely necessary for user data preservation
- Will require explicit migration tooling and documented upgrade path
- NOT during active development phase

**Current policy:** All implementations MUST strictly validate v1.5 compliance. Any violation is a **BUG** that must be fixed in code.

---

## Table of Contents

1. [Overview](#overview)
2. [Core Principles](#core-principles)
   - [Understanding Lamport Clocks and Concurrent Events](#understanding-lamport-clocks-and-concurrent-events)
3. [Protocol Structure](#protocol-structure)
4. [Change Actions](#change-actions)
5. [Validation Rules](#validation-rules)
6. [State Reconstruction](#state-reconstruction)
7. [Distributed TodoTask Consensus (Blockchain Model)](#distributed-todotask-consensus-blockchain-model)
8. [Task Ranking Algorithm](#task-ranking-algorithm)
   - [Mathematical Foundation](#mathematical-foundation)
   - [Derivative Properties](#derivative-properties-critical-design-constraint)
   - [Design Rationale](#design-rationale)
   - [Implementation](#implementation)
9. [Firebase Storage Architecture](#firebase-storage-architecture)
10. [Git-Like Local-First Paradigm](#git-like-local-first-paradigm)
11. [Implementation Requirements](#implementation-requirements)
12. [Normative JSON Schema](#normative-json-schema)
13. [Canonicalization and Hashing](#canonicalization-and-hashing)
    - [13.1 Canonical Hashing Test Vector](#131-canonical-hashing-test-vector)
    - [13.2 Merge Policy Test Scenario](#132-merge-policy-test-scenario)
    - [13.3 Reference Library Recommendations](#133-reference-library-recommendations)
14. [Example Flows](#example-flows)
15. [Security Considerations](#security-considerations)
16. [Version History](#version-history)
17. [Contact & Contributions](#contact--contributions)

---

## Overview

The REDO v1 protocol is a **Git-like distributed event model sourcing system** for task management. It provides:

- **Content-Addressed Storage**: Nodes identified by SHA-256 hash of their canonical JSON body
- **Causal Ordering**: Lamport logical clocks ensure deterministic event ordering
- **DAG Structure**: Parent references form a directed acyclic graph (DAG)
- **Cryptographic Identity**: Ed25519 signatures for authorship verification
- **Conflict-Free Sync**: Deterministic conflict resolution across devices via explicit MERGE actions

**Key Concept**: Current state = replay of all valid nodes in causal order.

The protocol emphasizes **immutability**, **explicit actions**, and **cross-platform consistency**. It supports offline edits with eventual consistency, making it suitable for personal and enterprise task management.

---

## Terminology Quick Reference

Understanding the distinction between different types of node rejection and deletion is critical for protocol implementation:

| Term | Meaning | Caused By | Persisted? | Restorable? |
|------|---------|-----------|------------|-------------|
| **Broken Branch** | Invalid node + descendants rejected during reconstruction | Protocol violation (bad schema, missing fields, etc.) | ❌ No (pruned from state) | ✅ Yes (if violation fixed in ancestor) |
| **Deleted Chain** | Task intentionally marked for deletion via DELETE tombstone | User action (DELETE) | ✅ Yes (in deletedChain payload) | ✅ Yes (if surviving descendant exists) |
| **Corrupted Task** | Task removed from active state due to violation | Any enforcement rule violation | ❌ No (removed from taskMap) | ❌ No (fix requires new valid branch) |
| **Invalidated Node** | Node that fails protocol validation | Schema mismatch, forbidden fields, etc. | ❌ No (rejected during replay) | ✅ Yes (if fixed at source) |
| **Tombstone** | Terminal DELETE node marking end of branch | Explicit DELETE action | ✅ Yes (full node preserved) | ⚠️ Conditional (if branch has living descendants) |

**Key Principles:**
- **Broken branches are pruned; ancestors survive** - Protocol violations never corrupt valid history
- **Deleted chains are preserved; resurrection is possible** - DELETE is intentional pruning, not data loss
- **"If One Lives, All Ancestors Live"** - Surviving descendants keep entire ancestral chain alive

---

## ⚠️ CRITICAL: Encoding Requirements

**ALL IMPLEMENTATIONS MUST USE LOWERCASE HEXADECIMAL ENCODING**

The v1 protocol requires **strict hexadecimal encoding** for cryptographic fields. Any deviation will cause cross-platform sync failures.

| Field | Encoding | Length | Example |
|-------|----------|--------|---------|
| `author.publicKey` | **lowercase hex** | **64 chars** | `9bf1a6192e3c4d5f...` |
| `author.userId` | **lowercase hex** | **32 chars** | `9bf1a6192e3c4d5f...` (first 32 of publicKey) |
| `signature` | **lowercase hex** | **128 chars** | `a1b2c3d4e5f6...` |
| `id` | **lowercase hex with prefix** | **71 chars** | `sha256:` + 64 hex chars |

**What NOT to use:**
- ❌ Base58 encoding (e.g., `9BW1aSPk6aFw...`)
- ❌ Base64 encoding (e.g., `bUIxYVNQazZhRnc=`)
- ❌ Uppercase hex (e.g., `9BF1A6192E3C...`)

**Why this matters:**
- Ensures byte-for-byte identical serialization across TypeScript, Kotlin, Swift, etc.
- Enables SHA-256 hash verification across platforms
- Allows signature verification without encoding conversion
- Prevents "invalid v1 node" rejections during sync

**Implementation checklist:**
- ✅ Use `bytesToHex()` / `Buffer.toString('hex')` / `toHexString()` for encoding
- ✅ Use `hexToBytes()` / `Buffer.from(hex, 'hex')` / `hexStringToBytes()` for decoding
- ✅ Verify output is lowercase (no uppercase A-F)
- ✅ Test cross-platform compatibility with shared test vectors

---

## Core Principles

### 1. Immutability
Once created, a **RedoNode** NEVER changes. Corrections are made by appending new nodes.

### 2. Content Addressing
Every node's ID is the SHA-256 hash of its canonical JSON body (excluding `id` and `signature`). This ensures:
- Identical content always has the same ID
- Content integrity verified by recomputing the hash
- Automatic deduplication across devices

### 3. Causal Ordering
Lamport clocks ensure that if event A caused event B, then `lamport(A) < lamport(B)`.

**Lamport Clock Computation (Normative)**:
```
For CREATE action (no parents):
  node.timestamp.lamport = 1

For all other actions (with parents):
  maxParentLamport = max(parent.timestamp.lamport for parent in node.parents)
  node.timestamp.lamport = maxParentLamport + 1
```

Wall-clock time serves as a tiebreaker and MUST be UTC (ISO 8601 with 'Z' suffix).

### Understanding Lamport Clocks and Concurrent Events

**Lamport clocks provide partial ordering, not total ordering.** This distinction is fundamental to understanding how distributed sync works in REDO.

#### What Lamport Clocks Tell Us

Lamport clocks capture **causal relationships** between events:

- **Causal Order**: If event A caused event B → `lamport(A) < lamport(B)`
- **Concurrent Events**: If `lamport(A) == lamport(B)` from different devices → A and B are **concurrent** (neither caused the other)

**Key Insight**: Same lamport values from different devices is a **feature**, not a bug - it indicates concurrent changes that happened independently.

#### Example: Divergent Branches

Consider two devices working offline simultaneously:

**Device A creates:**
```
CREATE task "Shopping" → lamport=1, parents=[]
UPDATE priority=5     → lamport=2, parents=[CREATE]
UPDATE title="Groceries" → lamport=3, parents=[UPDATE]
```

**Device B creates (at the same time):**
```
CREATE task "Errands"  → lamport=1, parents=[]
UPDATE priority=3      → lamport=2, parents=[CREATE]
UPDATE description="..." → lamport=3, parents=[UPDATE]
```

**Both devices have nodes with lamport=3** - this correctly indicates they were created concurrently without knowledge of each other.

#### Achieving Total Ordering

While Lamport clocks provide partial ordering, REDO achieves **deterministic total ordering** using a 3-level sort:

1. **Primary**: `timestamp.lamport` (ascending) - causal order
2. **Tiebreaker 1**: `timestamp.wall` (ascending) - wall clock time
3. **Tiebreaker 2**: `id` (lexicographic) - node content hash

This ensures **every device reconstructs identical state** from the same set of nodes, regardless of the order in which nodes were received.

**Example**:
```
Node A: lamport=3, wall="10:00:00.000Z", id="sha256:aaa..."
Node B: lamport=3, wall="10:00:00.000Z", id="sha256:bbb..."
Node C: lamport=3, wall="10:05:00.000Z", id="sha256:ccc..."

Deterministic order: A < B < C
(same lamport, so use wall; same wall for A & B, so use id)
```

#### Merging Divergent Branches

When devices sync after working offline, they create a **MERGE node** that explicitly captures the concurrent history:

```json
{
  "id": "sha256:merge123...",
  "parents": [
    "sha256:deviceA_head...",
    "sha256:deviceB_head..."
  ],
  "lamport": 4,  // max(3, 3) + 1
  "action": "MERGE",
  "data": {
    "payload": {
      "base": "sha256:common_ancestor...",
      "policy": { "defaultStrategy": "lww" }
    }
  }
}
```

The MERGE node:
- **Captures concurrency**: Both parent branches explicitly listed
- **Resolves conflicts**: Using policy (Last-Write-Wins, manual resolution, etc.)
- **Advances time**: `lamport = max(parent_lamports) + 1`
- **Creates single head**: Subsequent changes reference this merge

#### State Reconstruction

When replaying the DAG to rebuild current state:

1. **Sort all nodes** using 3-level ordering (lamport, wall, id)
2. **Apply changes** in deterministic order
3. **Last write wins** for conflicting field updates (using total ordering)

**Example**:
```
Device A: UPDATE priority=5, lamport=3, wall="10:00:00"
Device B: UPDATE priority=3, lamport=3, wall="10:05:00"

Result after replay: priority=3
(Device B wins because later wall time)
```

#### Why This Design Works

✅ **Detects concurrency**: Same lamport = concurrent changes
✅ **Deterministic ordering**: Wall + ID ensures everyone sees same state
✅ **Explicit merge tracking**: MERGE nodes document branch merges
✅ **No coordination needed**: Devices work offline and merge later
✅ **Cross-platform consistency**: TypeScript, Kotlin, Swift all reconstruct identical state

This is the same architecture used by Git (Merkle DAG + causal ordering), proven to work for millions of distributed collaborators.

### 4. Zero Legacy Support
v1 protocol only. Invalid nodes are **immediately rejected and deleted**. No backward compatibility.

### 5. Explicit Actions
Every state change must be recorded as an explicit action. No implicit side effects during reconstruction. For recurring tasks, completing a todo and scheduling the next are **separate actions**.

---

## Protocol Structure

### RedoNode (v1)

A **RedoNode** is the immutable unit of change in the REDO DAG. It is serialized as JSON and stored/transmitted in this format.

#### Wire Format (JSON Structure):

```json
{
  "id": "sha256:<hexstring>",
  "version": 1,
  "parents": ["sha256:<hexstring>", ...],
  "timestamp": {
    "lamport": 1,
    "wall": "2025-10-09T12:00:00.000Z"
  },
  "author": {
    "userId": "a1b2c3d4...",
    "deviceId": "device_xyz",
    "publicKey": "ed25519_public_key_hex",
    "name": "Optional Name",
    "email": "optional@email.com",
    "deviceName": "Optional Device Name"
  },
  "action": "CREATE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": { ... }
  },
  "signature": "ed25519_signature_hex"
}
```

#### Field Descriptions:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Content-addressed ID (envelope; excluded from hash). Format: `sha256:<64 lowercase hex chars>` |
| `version` | integer | Yes | Protocol version. MUST be exactly `1` |
| `parents` | array of strings | Yes | Parent node IDs. **MUST be empty `[]` for CREATE action**. MUST have ≥1 for all other actions. Each element: `sha256:<lowercase hex>` |
| `timestamp.lamport` | integer | Yes | Lamport logical clock. **MUST be exactly `1` for CREATE**. For others: `max(parent lamports) + 1`. |
| `timestamp.wall` | string | Yes | Wall-clock time in **UTC (ISO 8601 with 'Z' suffix)**: `YYYY-MM-DDTHH:mm:ss.sssZ` |
| `author.userId` | string | Yes | First 32 chars of Ed25519 public key (**lowercase hex**) |
| `author.deviceId` | string | Yes | Unique device identifier |
| `author.publicKey` | string | Yes | Full Ed25519 public key (**lowercase hex**, 64 chars) |
| `author.name` | string | No | Human-readable author name |
| `author.email` | string | No | Author email address |
| `author.deviceName` | string | No | Human-readable device name |
| `action` | string | Yes | One of the ChangeAction enums (see below) |
| `taskId` | string | Yes | UUID v4 of the target task (lowercase with hyphens) |
| `data.payload` | object | Yes | Action-specific payload (strictly typed per action). **Max 1MB serialized size**. |
| `signature` | string | No | Ed25519 signature over canonical body (**lowercase hex**, 128 chars). **REQUIRED for synced nodes**. |

#### Reserved Field Names

The following field names are **RESERVED** by the protocol and **MUST NOT** be used in `data.payload` or any extension objects:

**Node-Level Reserved Fields:**
- `id`, `version`, `parents`, `timestamp`, `author`, `action`, `taskId`, `data`, `signature`

**Timestamp-Level Reserved Fields:**
- `lamport`, `wall`

**Author-Level Reserved Fields:**
- `userId`, `deviceId`, `publicKey`, `name`, `email`, `deviceName`

**Payload-Level Reserved Fields (Do NOT include in custom payloads):**
- `guid` - Reserved for task-level identifier (assigned by CREATE, immutable)
- `todoTasks` - Reserved for internal state reconstruction (not user-provided)
- `created` - Reserved for timestamp tracking (not user-provided)
- `archived` - Reserved for state management (use ARCHIVE/UNARCHIVE actions)
- `deleted` - Reserved for state management (use DELETE action)

**Why this matters:**
- Prevents collisions with future protocol enhancements
- Ensures cross-platform interoperability
- Protects against accidental state corruption
- Enables safe extension via namespaced fields (e.g., `extensions.myapp.customField`)

**Safe Extension Pattern:**
```json
{
  "action": "UPDATE",
  "data": {
    "payload": {
      "title": "Updated title",
      "extensions": {
        "myapp": {
          "customField": "value"
        }
      }
    }
  }
}
```

#### ChangeAction Enum:

```typescript
type ChangeAction =
  | 'CREATE'
  | 'UPDATE'
  | 'DELETE'
  | 'COMPLETE_TODO'
  | 'CREATE_TODO'
  | 'SNOOZE'
  | 'ARCHIVE'
  | 'UNARCHIVE'
  | 'MERGE';
```

---

## Change Actions

Each action has a **strictly defined payload** under `data.payload`. Payloads are action-specific JSON objects with required/optional fields enforced by the normative JSON Schema.

### CREATE

**Purpose**: Create a new task (genesis block - metadata only).

**Genesis Block Pattern**: CREATE serves as the **genesis block** for a task's history - it defines the task's metadata but does NOT create an actionable todo. A task becomes actionable only when followed by a CREATE_TODO node.

**Payload**:
```json
{
  "title": "Buy milk",
  "description": "Whole milk",
  "privacy": true,
  "storyPoints": 1,
  "priority": 3,
  "frequencyDays": 7
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `title` | string | Yes | minLength: 1 |
| `description` | string | No | |
| `privacy` | boolean | No | |
| `storyPoints` | integer | No | ≥ 0 |
| `priority` | integer | No | 1-5 scale: **5=Highest (Urgent), 1=Lowest (Backlog)** |
| `frequencyDays` | integer | No | ≥ 1 |

**Parents**: **MUST be empty array `[]`** (root node).

**Lamport**: MUST be exactly `1`.

**Uniqueness**: Each `taskId` MUST have exactly ONE CREATE node. Multiple CREATEs for the same `taskId` are invalid.

**Duplicate CREATE Handling (v1.5)**:
When a `taskId` has multiple CREATE nodes (protocol violation), implementations MUST:
1. **Identify the "original" CREATE** using this deterministic tiebreaker:
   - Primary: Earliest `timestamp.wall` (ISO 8601 string comparison)
   - Tiebreaker (if wall times identical): Lexicographic ordering of `id` (sha256 hash)
   - Note: If nodes are cryptographically identical (same signature), they represent the same event and should be deduplicated before processing
2. **Keep the original CREATE** - process it normally
3. **Reject duplicate CREATE nodes** - do not process them
4. **Reject all descendants** - any node that has a duplicate CREATE in its parent chain MUST be rejected (via parent reference analysis)

This ensures deterministic, consistent state reconstruction across all clients regardless of node arrival order.

**Important**: CREATE alone does NOT make a task actionable. Implementations SHOULD immediately follow CREATE with CREATE_TODO to create the first actionable todo. Tasks with CREATE but no CREATE_TODO are considered "draft" tasks and SHOULD NOT appear in active task lists (though UIs MAY display them with special "draft" status).

**CRITICAL CLIENT PRACTICE (v1.3)**: Clients SHOULD create both CREATE and CREATE_TODO as a **single transaction**. Do NOT create UPDATE nodes between CREATE and CREATE_TODO - UPDATE is for editing metadata, NOT for initializing todos.

**Correct Pattern**:
```
CREATE (metadata) → CREATE_TODO (first instance) → [user edits metadata later] → UPDATE
```

**Incorrect Legacy Pattern** (v1.1 - DO NOT USE):
```
CREATE (metadata) → UPDATE (sets deadline) ❌ WRONG - use CREATE_TODO instead!
```

**Recommended UI Flow**:
```typescript
// User clicks "Create Task" - UI creates BOTH nodes as a transaction
await createNode('CREATE', taskId, { title, priority, frequencyDays, ... }, []);
await createNode('CREATE_TODO', taskId, { deadline: ..., notes: '' }, [createNodeId]);
// UPDATE is ONLY used later when user edits metadata (title, priority, etc.)
```

---

### UPDATE

**Purpose**: Modify task metadata only.

**CRITICAL (v1.5)**: The UPDATE action is strictly for editing the task's core properties (like title or priority). It is **forbidden** to use UPDATE for state management.

**Allowed Fields** (Metadata ONLY):
- `title` - Task name
- `description` - Task details
- `priority` - Task importance (1-5 scale: **5=Highest/Urgent, 1=Lowest/Backlog**)
- `storyPoints` - Task complexity/effort (1-5 recommended)
- `frequencyDays` - Recurrence interval for recurring tasks
- `privacy` - Task visibility

**Forbidden Operations**:
- ❌ Managing todo instances (use CREATE_TODO, COMPLETE_TODO)
- ❌ Managing archive status (use ARCHIVE, UNARCHIVE)
- ❌ Managing deletion status (use DELETE)

**Any UPDATE node containing fields related to these forbidden operations (todoTasks, archived, deleted, etc.) will cause that node and all its descendants to be REJECTED during reconstruction.**

**Payload**:
```json
{
  "title": "Buy skim milk",
  "description": "Low fat, organic",
  "priority": 2,
  "storyPoints": 1,
  "frequencyDays": 14,
  "privacy": false
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `title` | string | No | minLength: 1 |
| `description` | string | No | |
| `priority` | integer | No | |
| `storyPoints` | integer | No | ≥ 0 |
| `frequencyDays` | integer | No | ≥ 1 |
| `privacy` | boolean | No | |

**Note**: At least one field MUST be provided.

**PROTOCOL VIOLATION (v1.5)**: Including forbidden state management fields (`archived`, `deleted`, `todoTasks`, etc.) in an UPDATE payload is a protocol violation. **This node and all its descendants will be REJECTED** during reconstruction. The task's state will revert to the last valid ancestor. Use dedicated actions (ARCHIVE, DELETE, CREATE_TODO) for state management instead.

**Parents**: MUST reference the most recent node for this task.

**When to Use**:
- User edits task title or description
- User changes task priority or complexity
- User adjusts recurrence frequency
- User toggles privacy settings

**When NOT to Use**:
- ❌ After CREATE to set first deadline → Use CREATE_TODO
- ❌ To schedule next todo → Use CREATE_TODO
- ❌ To modify todo deadlines → Use SNOOZE or CREATE_TODO

**State Propagation** (CRITICAL):
UPDATE changes to metadata **immediately affect** all downstream operations:

- **frequencyDays**: Next CREATE_TODO MUST calculate deadline using the CURRENT frequencyDays (after all UPDATEs)
- **priority**: Ranking algorithm MUST use CURRENT priority (after all UPDATEs)
- **storyPoints**: Ranking algorithm MUST use CURRENT storyPoints (after all UPDATEs)

**Example Flow**:
```
CREATE (frequencyDays: 7, priority: 1, storyPoints: 1)
CREATE_TODO (deadline: today + 7 days)
COMPLETE_TODO
UPDATE (frequencyDays: 3, priority: 5, storyPoints: 3)
COMPLETE_TODO
CREATE_TODO (deadline: today + 3 days) ← Uses NEW frequencyDays=3
[Ranking] ← Uses NEW priority=5, storyPoints=3
```

**Implementation Requirement**: All operations MUST reconstruct current state by replaying ALL nodes (CREATE + all UPDATEs) before calculating next deadline or ranking score.

---

### COMPLETE_TODO

**Purpose**: Mark a specific TodoTask as completed.

**CRITICAL (v1.4)**: Uses **stable GUID** to identify todo, NOT array index. This prevents race conditions in distributed scenarios where concurrent operations could reorder the todoTasks array.

**Payload**:
```json
{
  "todoTaskId": "3b6f8b9d-c5e4-4a2f-9d7b-1f3a5c8e2b4d",
  "completed": "2025-10-09T14:30:00.000Z",
  "notes": "Bought whole milk"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `todoTaskId` | string | Yes | UUID v4 format - stable GUID of the TodoTask to complete |
| `completed` | string | Yes | ISO 8601 timestamp |
| `notes` | string | No | |

**Important**: Does NOT create the next todo; use separate `CREATE_TODO`.

**Parents**: MUST reference the most recent node for this task.

**CRITICAL VALIDATION RULES (v1.4)**:
1. The todo identified by `todoTaskId` MUST exist in the current reconstructed state
2. The todo MUST have been created by a CREATE_TODO node, NOT by a CREATE node
3. If `todoTaskId` references a non-existent todo → **Chain INVALIDATED**
4. If `todoTaskId` references a CREATE-created todo → **Chain INVALIDATED**

**Race Condition Prevention**: Using stable GUIDs instead of array indices prevents this scenario:
- Device 1: Completes todo at index 0 (GUID: A)
- Device 2: Concurrently deletes todo at index 0, shifting todo B to index 0
- **With indices**: Device 1's completion incorrectly applies to todo B ❌
- **With GUIDs**: Device 1's completion correctly applies to todo A ✅

**Rationale**: The genesis block pattern separates task metadata (CREATE) from actionable instances (CREATE_TODO). Completions reference instances by stable GUID, never by array position or genesis blocks.

---

### CREATE_TODO

**Purpose**: Create a new actionable TodoTask instance.

**When to Use**:
- **Immediately after CREATE** - to make the task actionable for the first time
- After COMPLETE_TODO - to schedule the next occurrence
- After UNARCHIVE - to resume a previously archived task

**Payload**:
```json
{
  "todoTaskId": "550e8400-e29b-41d4-a716-446655440000",
  "deadline": "2025-10-16T14:30:00.000Z",
  "notes": "Next purchase"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `todoTaskId` | string | **Yes** | **UUID v4 format** - the stable, unique identifier for this todo instance. MUST be generated once at node creation time and included in the payload to ensure deterministic state reconstruction. |
| `deadline` | string | Yes | ISO 8601 timestamp |
| `notes` | string | No | |

**⚠️ CRITICAL (v1.7)**: The `todoTaskId` field is REQUIRED. Implementations MUST generate a UUID v4 at CREATE_TODO node creation and include it in the payload. This ensures the todo instance has a stable GUID across all state reconstructions, preventing COMPLETE_TODO and SNOOZE reference failures.

**Parents**: MUST reference the most recent node for this task.

**Critical Design Pattern**: CREATE_TODO creates an "actionable instance" of a todo, separate from the task's genesis block (CREATE). Every COMPLETE_TODO MUST reference a CREATE_TODO node (never a CREATE node directly).

**Example Chain**:
```
CREATE (genesis) → CREATE_TODO (first instance) → COMPLETE_TODO → CREATE_TODO (second instance) → ...
```

---

### SNOOZE

**Purpose**: Extend a TodoTask deadline.

**Payload**:
```json
{
  "todoTaskId": "3b6f8b9d-...",
  "daysToExtend": 3,
  "notes": "Delayed due to travel"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `todoTaskId` | string | Yes | GUID of TodoTask |
| `daysToExtend` | integer | No | ≥ 1 (mutually exclusive with newDeadline) |
| `newDeadline` | string | No | ISO 8601 (mutually exclusive with daysToExtend) |
| `notes` | string | No | |

**Note**: MUST provide either `daysToExtend` OR `newDeadline`.

**Parents**: MUST reference the most recent node for this task.

---

### ARCHIVE

**Purpose**: Archive a task (stops recurring cycle).

**Payload**: Empty object `{}`

**Effect**: Sets `task.archived = true`.

**Parents**: MUST reference the most recent node for this task.

---

### UNARCHIVE

**Purpose**: Restore task from archive.

**Payload**: Empty object `{}`

**Effect**: Sets `task.archived = false`. Typically followed by `CREATE_TODO`.

**Parents**: MUST reference the most recent node for this task.

---

### DELETE

**Purpose**: Mark a branch as deleted (tombstone) while supporting branch resurrection in distributed sync.

**Payload**:
```json
{
  "deletedChain": [
    "sha256:root...",
    "sha256:node1...",
    "sha256:node2...",
    "sha256:node3..."
  ]
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `deletedChain` | array of strings | Yes | Complete ancestry chain from root to deleted head. Each element: `sha256:<lowercase hex>`. MUST include all nodes from CREATE (root) to the parent of this DELETE node. |

**Parents**: MUST reference the most recent node for this task (the head being deleted).

**Core Deletion Principle: Surviving Descendants Keep Ancestors Alive**

A DELETE node acts as a **tombstone for a specific branch of history**. However, this deletion is overruled if any surviving node (one not marked for deletion) descends from that branch's history.

**In effect**: Any living branch "keeps alive" its entire ancestral chain, all the way back to the root CREATE node. A DELETE tombstone only succeeds in pruning a branch that is a true dead end with no living descendants.

This preserves the integrity of divergent histories, which is identical to Git's branch deletion behavior.

**Key Difference from Protocol Violations:**
- **DELETE**: An **intentional pruning** of a valid branch of history. Can be overruled by surviving descendants.
- **Protocol Violation**: An **unintentional break** in the branch. The broken node and its descendants are rejected; ancestors remain safe.

**Transmission and Pruning Rules**:

A node in `deletedChain` is **pruned from transmission/storage** if and only if:
1. It appears in at least one DELETE tombstone's `deletedChain`, AND
2. No surviving nodes (nodes NOT in any `deletedChain`) reference it as an ancestor
3. It has no children outside the `deletedChain` (no divergent branches)

**Git-Like Semantics**:
- **Compact storage**: Machines can prune nodes when no surviving branches exist
- **Branch resurrection**: If divergent branches exist elsewhere, deleted nodes are automatically re-downloaded
- **Distributed conflict resolution**: Multiple DELETE tombstones can coexist, each marking a different branch deletion

**Example - Branch Resurrection:**
```
Initial state:
- Root (CREATE)
- Node1 (UPDATE, parent=Root)
- Node2 (UPDATE, parent=Node1)
- Node3 (COMPLETE_TODO, parent=Node2)

Machine A deletes:
- DELETE1: deletedChain=[Root, Node1, Node2, Node3]
- Machine A prunes all nodes, keeps only DELETE1 tombstone

Machine B (offline) creates divergent branch:
- Node4 (UPDATE, parent=Node2)  ← Branches from Node2!
- Node5 (CREATE_TODO, parent=Node4)

After sync:
Machine A sees Node4, Node5 (not in deletedChain)
→ Machine A re-downloads: Root, Node1, Node2, Node4, Node5
→ Node3 stays pruned (dead end, no children outside deletedChain)
→ Task resurrects with surviving branch: Root→Node1→Node2→Node4→Node5

Transmission result:
✅ Root - needed for Node4 ancestry (even though in deletedChain)
✅ Node1 - needed for Node4 ancestry (even though in deletedChain)
✅ Node2 - needed for Node4 ancestry (even though in deletedChain)
❌ Node3 - dead end, no surviving descendants (PRUNED)
✅ DELETE1 - tombstone metadata always transmitted
✅ Node4 - surviving branch
✅ Node5 - surviving branch
```

**Multiple DELETE Nodes**:

Multiple DELETE tombstones for the same task are valid and represent independent branch deletions:

```
Machine A: DELETE_A with deletedChain=[Root, Node1, Node2, Node3]
Machine B: DELETE_B with deletedChain=[Root, Node1, Node2, Node4]

Result after sync:
- Both DELETE nodes transmitted
- Union of deletedChains: [Root, Node1, Node2, Node3, Node4]
- If Node5 exists with parent=Node2, then Root, Node1, Node2 resurrect
- Node3 and Node4 stay pruned (both dead ends)
```

**State Reconstruction**:

During state reconstruction:
1. Collect all DELETE tombstones for the task
2. Build union of all `deletedChain` arrays across all DELETE nodes
3. Identify surviving nodes (nodes NOT in the union)
4. Apply ancestry-based pruning (keep nodes needed for surviving branches)
5. Replay remaining nodes in causal order
6. If ANY non-deleted branch exists, task appears in final state
7. If ALL branches are deleted (no surviving nodes), task is removed from state

**Branch Resurrection Workflow**:

When a machine discovers nodes outside its known `deletedChain`:
1. Machine A has: DELETE tombstone only (pruned all nodes for storage efficiency)
2. Machine B has: Node4, Node5 (divergent branch created while offline)
3. Sync occurs: Machine A sees Node4 (not in its deletedChain)
4. Machine A recognizes Node4's parent is Node2 (which IS in deletedChain)
5. Machine A re-downloads: Root, Node1, Node2 (ancestors of Node4) + Node4, Node5
6. Task resurrects on Machine A with full branch continuity maintained
7. DELETE tombstone remains in history as record of the deleted branch

**This is identical to git branch semantics:**
- Deleting a branch locally doesn't prevent it from being restored when it exists on a remote
- `git branch -d feature` deletes the branch pointer but commits can still be referenced
- If another remote has the branch, `git fetch` brings it back
- History is preserved through ancestry chains, not just head references

**DELETE Semantics: Branch-Based, Not Global (CRITICAL - v1.7)**

**IMPORTANT**: DELETE is a **branch operation**, not a global kill switch for a taskId.

DELETE only affects nodes that have it in their **parent chain** (descendants), NOT concurrent branches.

**Example - Concurrent DELETE and UNARCHIVE:**
```
ARCHIVE (L=3)
  ├─> DELETE (L=4)        [Branch A - orphaned]
  └─> UNARCHIVE (L=4)     [Branch B - active]
        └─> CREATE_TODO (L=5)  [Valid - follows Branch B]
```

In this scenario:
- DELETE and UNARCHIVE are **concurrent** (both reference ARCHIVE at L=3)
- CREATE_TODO at L=5 follows the UNARCHIVE branch
- CREATE_TODO is **VALID** because DELETE is not in its parent chain
- The task remains active (UNARCHIVE branch "wins" the conflict)

**Implementation Rule**:
When processing nodes, track which DELETE nodes exist in the **ancestor chain** for each node. Only reject nodes that have DELETE in their ancestry, not nodes on parallel branches.

**Invalid vs Valid**:
- ❌ INVALID: `CREATE (L=1) → DELETE (L=2) → CREATE_TODO (L=3, parent=[DELETE])`
- ✅ VALID: `CREATE (L=1) → UPDATE (L=2) → CREATE_TODO (L=3, parent=[UPDATE])`
                         `└─> DELETE (L=2, parent=[CREATE])`

In the valid case, both UPDATE and DELETE reference CREATE (concurrent), and CREATE_TODO follows UPDATE (not DELETE).

**UNDELETE is NOT Supported (v1.7)**:

The protocol does NOT define an UNDELETE or RESTORE action. Once a DELETE tombstone is created:
- Nodes **descended from DELETE** are rejected during reconstruction
- DELETE is **terminal** for its branch only
- Concurrent branches remain valid and unaffected

**However**: Deleted tasks can be "resurrected" if:
- A divergent branch exists that branched off BEFORE the DELETE
- The "If One Lives, All Ancestors Live" rule keeps the ancestry chain intact
- This is **not undeletion** - it's branch preservation based on surviving history

**To recreate a deleted task**: Users must create a NEW task (new taskId, fresh CREATE node). The old task's history remains in the graveyard but is not restored.

---

### MERGE

**Purpose**: Resolve divergent histories for the same `taskId`.

MERGE supports **two lanes**:

1. **Simple Merge** (default, invisible to basic users): Deterministic LWW/union via policy
2. **Detailed Merge** (for power/enterprise users): Per-field resolutions with overrides

#### Simple Merge Payload:

```json
{
  "base": "sha256:9999...",
  "policy": {
    "defaultStrategy": "lww",
    "lwwTiebreakers": ["lamport", "wall", "author"],
    "arrayStrategy": "union"
  }
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `base` | string | Yes | Ancestor node ID (sha256:hex) |
| `policy.defaultStrategy` | string | No | Enum: ours, theirs, union, lww, manual, max, min. Default: lww |
| `policy.lwwTiebreakers` | array of strings | No | Array of enums: lamport, wall, author. Default: ["lamport","wall","author"] |
| `policy.arrayStrategy` | string | No | Enum: union, lww. Default: union |

#### Detailed Merge Payload:

```json
{
  "base": "sha256:9999...",
  "policy": { ... },
  "resolutions": {
    "task": [
      {
        "path": "title",
        "strategy": "lww",
        "notes": "Optional explanation"
      },
      {
        "path": "priority",
        "strategy": "ours",
        "chosenParent": "sha256:aaaa...",
        "notes": "Kept priority from device A"
      }
    ],
    "todos": [
      {
        "todoTaskId": "3b6f...",
        "fields": [
          {
            "path": "deadline",
            "strategy": "theirs",
            "chosenParent": "sha256:bbbb..."
          },
          {
            "path": "notes",
            "strategy": "manual",
            "value": "Merged note text"
          }
        ]
      }
    ]
  }
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `base` | string | Yes | Ancestor node ID |
| `policy` | object | No | Same as Simple Merge |
| `resolutions.task` | array | No | Array of FieldResolution |
| `resolutions.todos` | array | No | Array of TodoFieldResolutions |

**FieldResolution**:
| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `path` | string | Yes | Dot notation path (e.g., "title", "meta.tags") |
| `strategy` | string | Yes | Enum: ours, theirs, union, lww, manual, max, min |
| `chosenParent` | string | Conditional | Required for ours/theirs |
| `value` | any | Conditional | Required for manual |
| `notes` | string | No | Explanation/rationale |

**TodoFieldResolutions**:
| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `todoTaskId` | string | Yes | GUID of the TodoTask |
| `fields` | array | Yes | Array of FieldResolution |

**Parents**: ≥ 2 (divergent heads).

**Effect**: Applies three-way merge from base to parents, using policy defaults or explicit resolutions. Deterministic and auditable.

#### Merge Strategies:

- **ours**: Use value from specified `chosenParent`
- **theirs**: Use value from the other `chosenParent`
- **union**: For arrays/sets, merge all distinct elements and sort lexicographically
- **lww**: Last-Write-Wins based on `lwwTiebreakers` order
- **manual**: Use explicit `value` provided
- **max**: For numeric fields, take maximum value
- **min**: For numeric fields, take minimum value

---

## Validation Rules

### v1 Node Compliance

Nodes MUST validate against the normative JSON Schema (see [Normative JSON Schema](#normative-json-schema)). Invalid nodes are **rejected and deleted immediately**.

### 5.1 Error Codes and Validation Reasons

To enable structured error handling and interoperability across implementations (TypeScript, Kotlin, Swift), the protocol defines standardized error codes for validation failures:

| Error Code | Rejection Reason | Description |
|------------|------------------|-------------|
| **E_INVALID_SIGNATURE** | Signature verification failed | Ed25519 signature does not match canonical body |
| **E_SCHEMA_MISMATCH** | Node fails JSON Schema validation | Missing required field, wrong type, or constraint violation |
| **E_HASH_MISMATCH** | Content hash verification failed | Computed SHA-256 hash ≠ node.id |
| **E_ENCODING_VIOLATION** | Invalid encoding format | Non-lowercase hex, wrong length, or encoding type mismatch |
| **E_FORBIDDEN_FIELD** | Payload contains reserved field | UPDATE with archived/deleted field, or other protocol violation |
| **E_DUPLICATE_CREATE** | Multiple CREATE nodes for same taskId | Second CREATE node rejected; original preserved |
| **E_INVALID_TODO_REF** | COMPLETE_TODO references non-existent todo | todoTaskId not found in reconstructed todoTasks array |
| **E_MISSING_DELETED_CHAIN** | DELETE without deletedChain | DELETE action missing required deletedChain payload field |
| **E_LAMPORT_VIOLATION** | Lamport clock invariant violated | Lamport ≠ max(parent.lamport) + 1 |
| **E_PARENT_NOT_FOUND** | Parent node ID not in DAG | Node references parent that doesn't exist |

**Usage in Implementations:**

**TypeScript Example:**
```typescript
enum ValidationError {
  E_INVALID_SIGNATURE = 'E_INVALID_SIGNATURE',
  E_SCHEMA_MISMATCH = 'E_SCHEMA_MISMATCH',
  E_HASH_MISMATCH = 'E_HASH_MISMATCH',
  // ...
}

function validateNode(node: RedoNode): ValidationError | null {
  if (!verifySignature(node)) return ValidationError.E_INVALID_SIGNATURE;
  if (!schemaValidate(node)) return ValidationError.E_SCHEMA_MISMATCH;
  // ...
  return null; // Valid
}
```

**Kotlin Example:**
```kotlin
enum class ValidationError {
  E_INVALID_SIGNATURE,
  E_SCHEMA_MISMATCH,
  E_HASH_MISMATCH,
  // ...
}

fun validateNode(node: RedoNode): ValidationError? {
  if (!verifySignature(node)) return ValidationError.E_INVALID_SIGNATURE
  if (!schemaValidate(node)) return ValidationError.E_SCHEMA_MISMATCH
  // ...
  return null // Valid
}
```

**Logging Best Practices:**
```typescript
// ✅ CORRECT: Structured logging with error code
console.error(`[${ValidationError.E_INVALID_SIGNATURE}] Node ${node.id} rejected: signature verification failed`);

// ❌ WRONG: Unstructured error messages
console.error(`Invalid node: bad signature`);
```

**Why Standardized Error Codes Matter:**
- ✅ Cross-platform interoperability - same error codes in all implementations
- ✅ Structured logging and metrics - count E_SCHEMA_MISMATCH frequency
- ✅ Debugging and forensics - quickly identify rejection categories
- ✅ API error responses - return machine-readable rejection reasons
- ✅ Testing and validation - verify implementations reject nodes consistently

### Content Integrity

`id` MUST equal `sha256:<hex of canonical JSON body>`, where the body excludes `id` and `signature`.

### Signature Verification

If `signature` is present, it MUST be a valid Ed25519 signature of the canonical body using `author.publicKey`.

**Signature Policy**:
- **Local-only nodes**: Signature is OPTIONAL for nodes that never leave the device
- **Synced nodes**: Signature is REQUIRED for all nodes transmitted to remote storage (Firebase, blockchain, etc.)
- **Verification**: Receiving implementations MUST verify signatures on all synced nodes and reject invalid signatures

### Rejection Policy - STRICT ENFORCEMENT

**CRITICAL: This policy applies to ALL REDO implementations (web, CLI, Android, iOS, desktop)**

Invalid nodes MUST be treated as follows:

**Detection & Rejection:**
- Any node failing v1 protocol validation is IMMEDIATELY rejected
- Invalid nodes are NEVER included in reconstructed state
- Invalid nodes are NEVER acknowledged in API responses
- Invalid nodes are NEVER transmitted over any API or sync operation
- Invalid nodes are NEVER saved to local storage (delete if found)

**Zero Tolerance:**
- NO backwards compatibility with non-v1 nodes
- NO "legacy" mode or transition support
- NO accepting Base58, Base64, or any non-hex encoding
- NO accepting nodes missing required fields
- NO accepting malformed signatures or hashes

### Understanding Rejection of Invalid Nodes - The "Broken Branch" Principle

**IMPORTANT CLARIFICATION (v1.5)**: When a protocol violation is detected, it does **NOT** corrupt or delete the entire task history. The invalid node and any nodes that descend from it are rejected and ignored during state reconstruction.

**The "Broken Branch" Principle:**

Think of the task history as a tree (a DAG). A valid history is a continuous path from a leaf node back to the CREATE root. An invalid node is a broken branch - the branch is severed at that point.

1. **Upstream History is Safe**: An invalid node can **NEVER** invalidate its valid parents or ancestors. The historical record remains intact up to the point of the violation.

2. **Downstream is Pruned**: The invalid node and its entire descendant sub-graph are pruned from the reconstructed state.

3. **State Reverts**: The task's current state is reconstructed based on the longest surviving valid branch(es). It's as if the invalid branch never happened.

**This is a critical security feature.** It prevents a single malformed node (whether accidental or malicious) from destroying the valid, historical data of a task. The only data lost is the invalid change and any subsequent changes that depended on it.

**Visual Representation:**
```
           Valid Trunk              Broken Branch
           ───────────              ─────────────

    [Root]────[Node1]────[Node2]────[Node3✗]
       ✅       ✅         ✅            │
                                       └──[Node4✗]

    Legend:
    ✅ = Preserved (valid ancestors)
    ✗  = Rejected (broken branch)

    Final State: [Root] + [Node1] + [Node2]
```

**Example:**
```
Root (CREATE) → Node1 (UPDATE) → Node2 (UPDATE) → Node3 (INVALID UPDATE with archived field)
                                                  ↓
                                                  Node4 (COMPLETE_TODO)

Result:
✅ Root, Node1, Node2: PRESERVED (valid ancestor history)
❌ Node3, Node4: REJECTED (broken branch)
📊 Task state = Root + Node1 + Node2 (reverts to last valid state)
```

**Key Point**: "Rejection" is what happens **inside the application** during state reconstruction. It is NOT a protocol action. You will never create, transmit, or receive a "REJECTION" node - it's purely an internal state transition based on deterministic validation rules.

**Implementation Requirements:**
```typescript
// ✅ CORRECT: Strict v1 validation
if (!RedoNodeUtils.isValidV1Node(node)) {
  console.warn(`Rejecting invalid v1 node: ${node.id}`);
  await storage.deleteNode(node.id);  // Delete immediately
  return;  // Do NOT process further
}
```

```typescript
// ❌ WRONG: Do NOT acknowledge or transmit invalid nodes
if (!RedoNodeUtils.isValidV1Node(node)) {
  await api.uploadNode(node);  // NEVER DO THIS
}
```

**Why Strict Enforcement?**
- Ensures cross-platform data integrity (web ↔ CLI ↔ Android ↔ iOS)
- Prevents sync corruption from malformed data
- Enables deterministic state reconstruction
- Protects against injection attacks
- Maintains SHA-256 hash verification across all platforms

**Debugging & Logging:**
- Invalid nodes SHOULD be logged as warnings with rejection reason
- Implementations MAY provide admin UI to view rejected nodes
- Implementations MAY export rejected nodes for forensic analysis
- Logging MUST NOT prevent immediate deletion/rejection

### Validation at Every Boundary - MANDATORY

**CRITICAL REQUIREMENT**: ALL implementations MUST validate nodes at EVERY persistence and transmission boundary.

**Validation points (ALL platforms - web, CLI, Android, iOS, desktop):**

1. **Before Writing to Persistence:**
   ```typescript
   // ✅ REQUIRED: Validate BEFORE saving to localStorage/IndexedDB/SQLite
   async saveChange(node: RedoNode): Promise<void> {
     if (!RedoNodeUtils.isValidV1Node(node)) {
       console.warn(`Rejecting invalid node before write: ${node.id}`);
       throw new Error('Invalid v1 node - refusing to persist');
     }
     await storage.save(node);
   }
   ```

2. **After Reading from Persistence:**
   ```typescript
   // ✅ REQUIRED: Validate AFTER reading from localStorage/IndexedDB/SQLite
   async getAllChanges(): Promise<RedoNode[]> {
     const rawNodes = await storage.readAll();

     // Filter out any invalid nodes (defensive)
     const validNodes = rawNodes.filter(node => {
       if (!RedoNodeUtils.isValidV1Node(node)) {
         console.warn(`Found invalid node in storage: ${node.id} - deleting`);
         storage.delete(node.id); // Clean up corruption
         return false;
       }
       return true;
     });

     return validNodes;
   }
   ```

3. **Before Sending to Network:**
   ```typescript
   // ✅ REQUIRED: Validate BEFORE uploading to Firebase/backend
   async uploadNode(node: RedoNode): Promise<void> {
     if (!RedoNodeUtils.isValidV1Node(node)) {
       console.warn(`Refusing to upload invalid node: ${node.id}`);
       throw new Error('Invalid v1 node - refusing to transmit');
     }
     await firebaseBackend.saveChange(node);
   }
   ```

4. **After Receiving from Network:**
   ```typescript
   // ✅ REQUIRED: Validate AFTER downloading from Firebase/backend
   async syncFromRemote(): Promise<void> {
     const remoteNodes = await firebaseBackend.getChanges();

     // Filter and delete invalid nodes immediately
     for (const node of remoteNodes) {
       if (!RedoNodeUtils.isValidV1Node(node)) {
         console.warn(`Received invalid node from remote: ${node.id} - rejecting`);
         await firebaseBackend.deleteNode(node.id); // Clean up remote corruption
         continue;
       }
       await localStorage.saveChange(node);
     }
   }
   ```

5. **Before State Reconstruction:**
   ```typescript
   // ✅ REQUIRED: Validate BEFORE using nodes for state reconstruction
   function reconstructState(nodes: RedoNode[]): RedoTask[] {
     // Filter out invalid nodes
     const validNodes = nodes.filter(node => {
       if (!RedoNodeUtils.isValidV1Node(node)) {
         console.warn(`Skipping invalid node in reconstruction: ${node.id}`);
         return false;
       }
       return true;
     });

     // ... reconstruct from validNodes only
   }
   ```

**Why Validate Everywhere?**
- **Defense in Depth**: Multiple layers prevent corruption from propagating
- **Cross-Platform Protection**: Web app can't corrupt CLI, CLI can't corrupt Android
- **Cache Poisoning Prevention**: Stale/invalid cached data gets filtered out
- **Network Attack Mitigation**: Invalid data from compromised backends gets rejected
- **Data Integrity**: Ensures reconstructed state only uses valid nodes

**Enforcement Strategy:**
- **Fail Fast**: Invalid nodes should cause errors/warnings immediately
- **Auto-Cleanup**: Delete invalid nodes from persistence when found
- **Never Propagate**: Don't save, send, or reconstruct from invalid nodes
- **Log Everything**: Warn about every invalid node with rejection reason

**Implementation Checklist:**
- [ ] Validate before localStorage.setItem() / IndexedDB.put() / SQLite INSERT
- [ ] Validate after localStorage.getItem() / IndexedDB.get() / SQLite SELECT
- [ ] Validate before Firebase saveChange() / API POST
- [ ] Validate after Firebase getChanges() / API GET
- [ ] Validate before StateReconstructor.reconstructTasksFromNodes()
- [ ] Validate in cache.save() before counting tasks
- [ ] Delete invalid nodes immediately when found
- [ ] Log warnings with rejection reasons

**Anti-Pattern - NEVER Do This:**
```typescript
// ❌ WRONG: Saving without validation
async saveChange(node: RedoNode): Promise<void> {
  await storage.save(node); // Missing validation!
}

// ❌ WRONG: Reconstructing without validation
function reconstructState(nodes: RedoNode[]): RedoTask[] {
  // Using nodes directly without filtering!
  for (const node of nodes) {
    applyAction(node); // Missing validation!
  }
}

// ❌ WRONG: Uploading without validation
async uploadNode(node: RedoNode): Promise<void> {
  await firebaseBackend.saveChange(node); // Missing validation!
}
```

### Size Limits

**Payload Size**: Maximum 1MB (1,048,576 bytes) when serialized to canonical JSON.

**Rationale**: Prevents denial-of-service attacks and ensures reasonable storage/transmission costs across backends.

**Enforcement**: Implementations MUST reject nodes exceeding this limit during creation and sync.

---

## State Reconstruction

### Algorithm

```typescript
function reconstructState(nodes: RedoNode[]): RedoTask[] {
  // 1. Collect all nodes for the user/task
  const sorted = sortByLogicalTime(nodes);

  // 2. Sort by: lamport (asc), then wall (asc), then id (content hash - lexicographic)
  const tasks = new Map<string, RedoTask>();

  // 3. Replay in order, applying actions to task map
  for (const node of sorted) {
    if (!isValidV1Node(node)) {
      console.warn(`Skipping invalid node: ${node.id}`);
      deleteNode(node.id);
      continue;
    }

    const task = tasks.get(node.taskId);

    switch (node.action) {
      case 'CREATE':
        tasks.set(node.taskId, createTaskFromPayload(node));
        break;

      case 'UPDATE':
        updateTaskFromPayload(task, node.data.payload);
        break;

      case 'COMPLETE_TODO':
        completeTodoByGuid(task, node.data.payload);  // v1.5: Use stable GUID, not index
        break;

      case 'CREATE_TODO':
        addTodoToTask(task, node.data.payload);
        break;

      case 'SNOOZE':
        snoozeTodo(task, node.data.payload);
        break;

      case 'ARCHIVE':
        task.archived = true;
        break;

      case 'UNARCHIVE':
        task.archived = false;
        break;

      case 'DELETE':
        tasks.delete(node.taskId);
        break;

      case 'MERGE':
        applyMerge(tasks, node);
        break;
    }
  }

  return Array.from(tasks.values());
}
```

### Sorting Rules

Nodes are sorted deterministically by:
1. **Primary**: `timestamp.lamport` (ascending)
2. **Tiebreak 1**: `timestamp.wall` (ascending)
3. **Tiebreak 2**: `id` (lexicographic - content hash)

**CRITICAL (v1.4)**: The final tiebreaker MUST be the node `id` (SHA-256 content hash), NOT `author.userId`. Using the content-addressed ID ensures truly deterministic, unbiased ordering that is independent of who created the node. This is the standard approach for content-addressed systems.

This ensures **deterministic ordering** across all devices.

### Merge Application

For `MERGE` nodes:

1. **Validate**: Ensure `base` is an ancestor of all `parents`, and all nodes reference the same `taskId`
2. **Hydrate states**: Reconstruct task state at `base` and at each parent
3. **Compute diffs**: Determine field-level changes from base to each parent
4. **Identify conflicts**: Fields changed differently in multiple parents
5. **Apply resolutions**:
   - If explicit resolution exists for a field, apply it
   - Else if no conflict (only one parent changed), take that value
   - Else apply `policy.defaultStrategy` (default: `lww`)
6. **Set merged state**: Update task with resolved values

### Merge Policy Evaluation (Deterministic Resolution Order)

The MERGE action resolves conflicting concurrent changes using a deterministic policy. This pseudocode formalizes the merge resolution algorithm:

```typescript
function applyMerge(tasks: Map<string, RedoTask>, mergeNode: RedoNode): void {
  const { base, parents, resolutions, policy } = mergeNode.data.payload;
  const taskId = mergeNode.taskId;

  // 1. Hydrate states at base and each parent
  const baseState = reconstructStateAtNode(base, taskId);
  const parentStates = parents.map(p => reconstructStateAtNode(p, taskId));

  // 2. Compute field-level diffs (base → each parent)
  const diffs = parentStates.map(parentState =>
    computeFieldDiff(baseState, parentState)
  );

  // 3. Identify conflicts (field changed differently in multiple parents)
  const conflicts = identifyConflicts(diffs);

  // 4. Resolve each field with deterministic priority
  const resolvedState = { ...baseState };

  for (const field of getAllChangedFields(diffs)) {
    // Priority 1: Explicit resolution in MERGE payload
    if (resolutions && field in resolutions) {
      resolvedState[field] = resolutions[field];
      continue;
    }

    // Priority 2: No conflict - only one parent changed this field
    const changingParents = diffs.filter(diff => field in diff);
    if (changingParents.length === 1) {
      resolvedState[field] = changingParents[0][field];
      continue;
    }

    // Priority 3: Conflict - apply policy strategy
    const strategy = policy?.defaultStrategy || 'lww';

    switch (strategy) {
      case 'lww': // Last-Write-Wins (highest lamport, wall, id)
        const sortedParents = parents
          .map((p, idx) => ({ parent: p, state: parentStates[idx], diff: diffs[idx] }))
          .sort((a, b) => compareLogicalTime(a.parent, b.parent)); // DESC

        resolvedState[field] = sortedParents[0].state[field];
        break;

      case 'union': // Combine arrays (for lists/tags)
        const values = diffs.map(diff => diff[field]).filter(v => v != null);
        resolvedState[field] = [...new Set(values.flat())];
        break;

      case 'max': // Numerical maximum
        const nums = diffs.map(diff => diff[field]).filter(v => typeof v === 'number');
        resolvedState[field] = Math.max(...nums);
        break;

      default:
        throw new Error(`Unknown merge strategy: ${strategy}`);
    }
  }

  // 5. Apply resolved state to task
  tasks.set(taskId, { ...tasks.get(taskId), ...resolvedState });
}

function compareLogicalTime(nodeA: RedoNode, nodeB: RedoNode): number {
  // Returns: positive if A > B, negative if A < B, 0 if equal
  if (nodeA.timestamp.lamport !== nodeB.timestamp.lamport) {
    return nodeB.timestamp.lamport - nodeA.timestamp.lamport; // DESC
  }
  if (nodeA.timestamp.wall !== nodeB.timestamp.wall) {
    return nodeB.timestamp.wall.localeCompare(nodeA.timestamp.wall); // DESC
  }
  return nodeB.id.localeCompare(nodeA.id); // DESC - content hash tiebreaker
}
```

**Key Properties:**
- **Deterministic**: Same input nodes → same resolved state on all devices
- **Commutative**: Processing merge in different order yields same result
- **Explicit**: Resolution priorities clearly defined (explicit > auto > policy)
- **Extensible**: New strategies (e.g., 'min', 'first') can be added without breaking existing merges

**Example Merge Scenario:**
```typescript
// Device A: UPDATE priority=5, lamport=10
// Device B: UPDATE priority=3, lamport=11
// MERGE with policy.defaultStrategy='lww'
// Result: priority=3 (Device B wins - higher lamport)
```

---

## Distributed TodoTask Consensus (Blockchain Model)

### Mental Model: Blockchain-Style Consensus

REDO uses **blockchain-style consensus** for TodoTask management in distributed environments. This is the same model as Bitcoin's "longest chain wins" rule.

**Analogy:**
- **Bitcoin**: Multiple miners create competing blocks → longest chain wins
- **REDO**: Multiple devices create competing TodoTasks → tallest (highest lamport) wins

### The Distributed TodoTask Challenge

In a centralized system, each task has ONE current TodoTask. But in a **distributed asynchronous system** where devices work offline independently:

**Scenario:**
```
Device A (offline):  CREATE_TODO (lamport: 5, deadline: Oct 20)
Device B (offline):  CREATE_TODO (lamport: 6, deadline: Oct 21)
Device C (offline):  CREATE_TODO (lamport: 7, deadline: Oct 20)

         ↓ Sync & Merge ↓

All 3 TODOs are VALID history!
Current TODO = highest lamport (7)
```

### Core Principle: "Tallest Chain Wins"

**Like Bitcoin's block height**, REDO uses **Lamport clock** as the "height" of the operation chain:

- **Higher lamport** = later in causal time = "taller" chain
- **Tallest chain wins** = TodoTask with highest (lamport, wall, id) is "current"
- **Orphaned TODOs** = earlier TodoTasks that lost the fork race

**Deterministic Selection:**
```typescript
// Current TODO = highest (lamport, wall, id) uncompleted TodoTask
function getCurrentTodo(task: RedoTask): TodoTask | null {
  const uncompletedTodos = task.todoTasks
    .filter(t => t.completed === null)
    .sort((a, b) => {
      if (a.lamport !== b.lamport) return b.lamport - a.lamport; // DESC
      if (a.wall !== b.wall) return b.wall.localeCompare(a.wall); // DESC
      return b.id.localeCompare(a.id); // DESC
    });

  return uncompletedTodos[0] || null; // Tallest = current
}
```

### Fork Scenario Example

**Timeline:**
```
t=0: Task "Do laundry" exists
       ↓
t=1: Device A offline: CREATE_TODO (L:5, deadline: Oct 20)
     Device B offline: CREATE_TODO (L:6, deadline: Oct 21)
       ↓
t=2: Device A completes TODO → COMPLETE_TODO (L:7)
     Device B still has uncompleted TODO (L:6)
       ↓
t=3: Sync & merge
       ↓
Result:
  - Device A's completion (L:7) counts ✅
  - Device B's TODO (L:6) is "orphaned" but preserved
  - Current state: Task has 1 completion, 0 active TODOs
```

**All operations are valid** - they represent legitimate actions in isolated contexts. After merge:
- Deterministic ordering (lamport, wall, id) resolves conflicts
- Completions ALWAYS count (even if TODO was orphaned)
- Highest uncompleted TODO becomes "current"

### Why Multiple Uncompleted TODOs Can Exist

In distributed systems, **concurrent CREATE_TODO operations are inevitable**:

**Valid Reasons:**
1. **Offline work**: Devices create TODOs independently
2. **Clock skew**: Devices have different wall clock times
3. **Merge conflicts**: Two users create TODOs while disconnected
4. **Recovery**: System recreates TODO after failure

**These are NOT bugs** - they're artifacts of distributed operation.

### State Reconstruction Rules

When replaying the change log to determine current state:

```typescript
function reconstructTodos(task: RedoTask, nodes: RedoNode[]): TodoTask[] {
  const todos: TodoTask[] = [];

  // Step 1: Collect all CREATE_TODO nodes
  for (const node of nodes.filter(n => n.action === 'CREATE_TODO')) {
    todos.push({
      guid: generateGuid(),
      deadline: node.data.payload.deadline,
      notes: node.data.payload.notes || '',
      completed: null,
      lamport: node.timestamp.lamport,  // Track lamport for sorting
      wall: node.timestamp.wall,
      nodeId: node.id
    });
  }

  // Step 2: Apply all COMPLETE_TODO operations
  for (const node of nodes.filter(n => n.action === 'COMPLETE_TODO')) {
    const todoIdToComplete = node.data.payload.todoTaskId;
    const todo = todos.find(t => t.guid === todoIdToComplete);
    if (todo) {
      todo.completed = node.data.payload.completed; // Use completion time from payload
    }
  }

  // Step 3: Sort by (lamport, wall, id) - deterministic total ordering
  todos.sort((a, b) => {
    if (a.lamport !== b.lamport) return a.lamport - b.lamport;
    if (a.wall !== b.wall) return a.wall.localeCompare(b.wall);
    return a.nodeId.localeCompare(b.nodeId);
  });

  return todos;
}
```

### UI Display Guidelines

**Show ONLY the current TODO** (tallest/highest):
```typescript
// ✅ CORRECT: Show only current TODO
const currentTodo = getCurrentTodo(task);
if (currentTodo && !currentTodo.completed) {
  renderTodo(currentTodo); // Show in UI
}

// ❌ WRONG: Show all uncompleted TODOs
const allUncompleted = task.todoTasks.filter(t => !t.completed);
allUncompleted.forEach(renderTodo); // Confusing - shows orphans!
```

**Historical TODOs** (completed or orphaned) should be:
- Preserved in data structure
- Hidden from primary UI
- Visible in advanced "History" view (optional)

### Completions Always Count

**CRITICAL**: TodoTask completions are independent of which CREATE_TODO won the fork:

```
Device A:  CREATE_TODO (L:5) → User completes (L:7)
Device B:  CREATE_TODO (L:6) → User edits notes (L:8)

After merge:
  - Device B's TODO (L:6) wins (higher lamport than A's L:5)
  - Device A's completion (L:7) STILL COUNTS
  - Result: Task shows 1 completion, current TODO is from Device B
```

This is correct behavior:
- User on Device A did real work (completion)
- User on Device B did real work (created TODO)
- Both actions are valid in their local context
- Merge preserves both histories

### Why This Design Works

**Benefits:**
1. ✅ **No coordination needed**: Devices work offline independently
2. ✅ **Deterministic convergence**: All devices agree on "current" TODO
3. ✅ **No data loss**: All operations preserved in history
4. ✅ **Resilient to failures**: System recovers from partial syncs
5. ✅ **Scales to N devices**: Works with any number of concurrent devices

**Comparison to Bitcoin:**

| REDO TodoTask | Bitcoin Block | Purpose |
|---------------|---------------|---------|
| Lamport clock | Block height | Causal ordering |
| CREATE_TODO | Mine block | Create new unit |
| Tallest chain wins | Longest chain wins | Consensus rule |
| Orphaned TODO | Orphan block | Valid but not current |
| Completion counts | Transaction confirmed | Work is preserved |
| (lamport, wall, id) | Cumulative difficulty | Tiebreaker |

**This is a proven distributed systems pattern** used by:
- Bitcoin (Nakamoto consensus)
- Git (merge resolution)
- CRDTs (conflict-free replicated data types)
- Vector clocks (distributed databases)

### Implementation Requirements

**TodoTask Data Model:**
```typescript
interface TodoTask {
  guid: string;
  deadline: string;
  notes: string;
  completed: string | null;

  // Required for distributed consensus:
  lamport: number;  // From CREATE_TODO node
  wall: string;     // From CREATE_TODO node
  nodeId: string;   // CREATE_TODO node ID (for tiebreaker)
}
```

**Key Functions:**
```typescript
// Get current TODO (UI display)
function getCurrentTodo(task: RedoTask): TodoTask | null;

// Get all TODOs (history view)
function getAllTodos(task: RedoTask): TodoTask[];

// Check if TODO is orphaned
function isOrphaned(todo: TodoTask, task: RedoTask): boolean {
  const current = getCurrentTodo(task);
  return current !== null && todo.guid !== current.guid && !todo.completed;
}
```

### Validation Rules

**ALLOW multiple uncompleted TODOs** - they're valid distributed history:
```typescript
// ✅ CORRECT: Preserve all TODOs
function reconstructState(nodes: RedoNode[]): RedoTask[] {
  // Apply all CREATE_TODO nodes
  // Apply all COMPLETE_TODO nodes
  // DON'T reject duplicate uncompleted TODOs
  // Let tallest-chain-wins determine current
}

// ❌ WRONG: Reject duplicate uncompleted TODOs
function reconstructState(nodes: RedoNode[]): RedoTask[] {
  const uncompletedCount = todos.filter(t => !t.completed).length;
  if (uncompletedCount > 1) {
    throw new Error("Multiple uncompleted TODOs not allowed");
  }
}
```

### Summary

**Key Takeaway**: Multiple uncompleted TodoTasks are **expected behavior** in distributed asynchronous systems. Use **blockchain-style consensus** (tallest/highest lamport wins) to deterministically choose the "current" TODO for UI display, while preserving all TODOs in the historical record.

**Mental Model**: Think of TodoTasks like Bitcoin blocks - multiple can exist at the same "height" (lamport) from different "miners" (devices), but deterministic ordering picks the canonical "longest chain" (current TODO).

---

## Task Ranking Algorithm

### Overview

REDO uses a **mathematically rigorous urgency-based ranking system** to prioritize tasks in the user interface. The ranking algorithm combines priority, complexity, and urgency factors using a **smooth sigmoid S-curve** for urgency calculation.

**Key Innovation**: The urgency curve uses a logistic sigmoid function with **continuous differentiability** and an **inflection point at the deadline**, creating natural acceleration before deadlines and graceful plateau after deadlines.

### Mathematical Foundation

#### Ranking Formula

$$
R = W_p \cdot U(t) \cdot W_c
$$

where:
- $R$ = final task rank (higher = more important)
- $W_p$ = priority weight (derived from task priority 1-5)
- $U(t)$ = urgency weight (sigmoid function of time until deadline)
- $W_c$ = complexity weight (derived from story points)

#### Urgency Curve: Smooth Sigmoid Function

The core innovation is the urgency calculation using a **logistic sigmoid**:

$$
U(t) = U_{\text{base}} + U_{\text{scale}} \cdot \frac{1}{1 + e^{kt}}
$$

where:
- $U(t)$ = urgency as a function of time until deadline
- $U_{\text{base}}$ = minimum urgency floor (typically 1.0)
- $U_{\text{scale}}$ = urgency range multiplier (typically 10.0)
- $k$ = steepness factor (typically 0.4)
- $t$ = days until deadline (positive = future, negative = overdue, zero = deadline)

#### Derivative Properties (Critical Design Constraint)

The sigmoid function was specifically chosen for its **smooth continuous derivatives**:

**First Derivative (Rate of Urgency Change):**

$$
\frac{dU}{dt} = -\frac{k \cdot U_{\text{scale}} \cdot e^{kt}}{(1 + e^{kt})^2}
$$

**Property:** $\frac{dU}{dt} > 0$ for all $t$ (note: negative sign cancels with decreasing $t$)
- **Meaning**: Urgency ALWAYS increases as deadline approaches (and continues increasing when overdue)
- **User benefit**: Tasks never "jump" in priority - changes are smooth and predictable

**Second Derivative (Acceleration of Urgency Change):**

$$
\frac{d^2U}{dt^2} = \frac{k^2 \cdot U_{\text{scale}} \cdot e^{kt} \cdot (e^{kt} - 1)}{(1 + e^{kt})^3}
$$

**Critical Properties:**

- $\frac{d^2U}{dt^2} > 0$ when $t > 0$ → **Accelerating before deadline (convex)**
  - **Meaning**: As deadline approaches, urgency rises faster and faster
  - **User benefit**: Imminent deadlines demand attention with exponentially increasing urgency

- $\frac{d^2U}{dt^2} = 0$ when $t = 0$ → **Inflection point at deadline**
  - **Meaning**: Deadline is the exact moment where urgency transitions from accelerating to decelerating
  - **Mathematical beauty**: The curve "changes direction" precisely at the deadline

- $\frac{d^2U}{dt^2} < 0$ when $t < 0$ → **Decelerating after deadline (concave)**
  - **Meaning**: Overdue tasks continue to increase in urgency, but at a decreasing rate
  - **User benefit**: Prevents overdue low-priority tasks from dominating high-priority upcoming tasks

### Design Rationale

#### Why Sigmoid Over Alternatives?

**Previous Approach (Exponential/Logarithmic Piecewise):**

$$
U_{\text{old}}(t) = \begin{cases}
U_{\text{base}} + \log(-t + 1) & \text{if } t < 0 \text{ (overdue)} \\
U_{\text{base}} + e^{-kt} & \text{if } t \geq 0 \text{ (before deadline)}
\end{cases}
$$

**Problem:** Discontinuous first derivative at $t = 0$ (deadline)!

**Issues with Piecewise Functions:**
- Discontinuous first derivative at deadline → sudden "jumps" in urgency
- Different functions before/after deadline → inconsistent behavior
- Arbitrary transition point → feels unnatural to users

**Sigmoid Advantages:**
✅ **Single continuous function** - no piecewise logic needed
✅ **Smooth everywhere** - infinitely differentiable
✅ **Natural S-curve** - matches human perception of urgency
✅ **Automatic inflection** - deadline is the natural turning point
✅ **Bounded growth** - overdue tasks don't explode to infinity
✅ **Mathematically elegant** - proven model from statistics/ML

#### Preventing Overdue Domination

**Problem Statement**: Without careful design, overdue tasks can dominate the ranking:

```
Scenario:
- Task A: Low priority (1), 30 days overdue
- Task B: High priority (5), due tomorrow

Without sigmoid plateau:
- Task A urgency → ∞ (unbounded growth)
- Task A rank = 1 × ∞ × complexity = ∞
- Task B rank = 5 × 100 × complexity = 500
- Result: Low-priority overdue task ranks higher! ❌
```

**Sigmoid Solution**: The logarithmic-style plateau ($\frac{d^2U}{dt^2} < 0$ when overdue) prevents unbounded growth:

```
With sigmoid plateau:
- Task A urgency → ~11.0 (asymptotic limit at Ubase + Uscale)
- Task A rank = 1 × 11 × complexity = 11
- Task B rank = 5 × 100 × complexity = 500
- Result: High-priority upcoming task correctly ranks higher! ✅
```

The $\frac{d^2U}{dt^2} < 0$ property ensures that as tasks become more overdue, the urgency increase **slows down** (concave curve), preventing old overdue tasks from completely overshadowing important upcoming work.

**Asymptotic Behavior:**

$$
\lim_{t \to -\infty} U(t) = U_{\text{base}} + U_{\text{scale}}
$$

$$
\lim_{t \to +\infty} U(t) = U_{\text{base}}
$$

### Implementation

#### Core Function

**Location:** `src/utils/userConfigurableTaskSorting.ts:125-152`

```typescript
function calculateConfigurableUrgency(
  daysUntilDue: number,
  targetDays: number,
  weights: AlgorithmWeights
): number {
  const URGENCY_BASE = weights.URGENCY_BASE || 1.0;
  const URGENCY_SCALE = weights.URGENCY_SCALE || 10.0;
  const k = 0.4; // Steepness factor

  // Sigmoid/logistic function
  // f(x) = 1 / (1 + e^(k×x))
  const sigmoidValue = 1 / (1 + Math.exp(k * daysUntilDue));

  // Map sigmoid [0, 1] to urgency scale
  const urgency = URGENCY_BASE + (URGENCY_SCALE * sigmoidValue);

  return Math.max(0.1, urgency);
}
```

#### Urgency Behavior Examples

**Far Future (14 days remaining):**

$$
U(14) = 1.0 + 10.0 \cdot \frac{1}{1 + e^{0.4 \times 14}} = 1.0 + 10.0 \cdot \frac{1}{1 + e^{5.6}} \approx 1.04
$$

Result: Very low urgency (task is far away)

**Near Deadline (1 day remaining):**

$$
U(1) = 1.0 + 10.0 \cdot \frac{1}{1 + e^{0.4}} \approx 1.0 + 10.0 \times 0.40 = 5.0
$$

Result: Moderate-high urgency (deadline approaching)

**At Deadline (0 days):**

$$
U(0) = 1.0 + 10.0 \cdot \frac{1}{1 + e^0} = 1.0 + 10.0 \times 0.5 = 6.0
$$

Result: High urgency (**inflection point** - $\frac{d^2U}{dt^2} = 0$)

**Moderately Overdue (7 days late):**

$$
U(-7) = 1.0 + 10.0 \cdot \frac{1}{1 + e^{-2.8}} \approx 10.4
$$

Result: Very high urgency (but plateauing - $\frac{d^2U}{dt^2} < 0$)

**Very Overdue (30 days late):**

$$
U(-30) = 1.0 + 10.0 \cdot \frac{1}{1 + e^{-12}} \approx 11.0
$$

Result: Maximum urgency (asymptotic limit - plateau effect)

#### Steepness Factor Tuning

The `k` parameter controls how "sharp" the S-curve is:

**Low k (0.2):** Gentle S-curve
- Urgency changes slowly near deadline
- Wide transition zone (~20 days)
- Good for: Long-term planning, relaxed workflows

**Medium k (0.4):** Balanced S-curve ✅ **Default**
- Urgency ramps noticeably in final ~7 days
- Clear acceleration before deadline
- Good for: General task management

**High k (1.0):** Sharp S-curve
- Urgency spikes dramatically in final ~2 days
- Very aggressive deadline pressure
- Good for: Crisis management, tight deadlines

### Integration with Ranking System

The sigmoid urgency is combined with other factors:

```typescript
function calculateConfigurableRank(
  task: RedoTask,
  currentDate: Date = new Date()
): TaskRanking {
  // 1. Calculate urgency (sigmoid-based)
  const daysUntilDue = calculateDaysUntilDue(task, currentDate);
  const urgency = calculateConfigurableUrgency(
    daysUntilDue,
    task.frequencyDays,
    weights
  );

  // 2. Calculate priority weight
  const priorityWeight = calculatePriorityWeight(task.priority, weights);

  // 3. Calculate complexity weight
  const complexityWeight = calculateComplexityWeight(task.storyPoints, weights);

  // 4. Combine factors
  const rank = priorityWeight × urgency × complexityWeight;

  return {
    rank,
    breakdown: {
      priority: priorityWeight,
      urgency,
      complexity: complexityWeight,
      daysUntilDue
    }
  };
}
```

### Visualization and Testing

**Ranking Playground Tool**: `src/pages/RankingPlayground.tsx`

An interactive visualization tool is available in Developer Mode:
- Adjust priority, complexity, frequency with sliders
- See live urgency curve with sigmoid S-shape
- Test edge cases (overdue, far future, at deadline)
- Visualize derivative properties (inflection point, acceleration zones)

**Access**: Profile Menu → "⚗️ RANKING PLAYGROUND" (Developer Mode only)

### Validation and Cross-Platform Consistency

**Deterministic Ordering**: All implementations (TypeScript web, Kotlin CLI, Android, iOS, desktop) MUST use:
1. Identical sigmoid formula: $U(t) = U_{\text{base}} + U_{\text{scale}} \cdot \frac{1}{1 + e^{kt}}$
2. Identical steepness factor: $k = 0.4$
3. Identical parameter values: $U_{\text{base}} = 1.0$, $U_{\text{scale}} = 10.0$
4. IEEE 754 floating-point arithmetic (standard across platforms)

**Test Vectors**: Implementations MUST pass these reference test cases:

```json
{
  "testVectors": [
    {
      "daysUntilDue": 14,
      "expectedUrgency": 1.037,
      "tolerance": 0.001
    },
    {
      "daysUntilDue": 0,
      "expectedUrgency": 6.0,
      "tolerance": 0.001
    },
    {
      "daysUntilDue": -7,
      "expectedUrgency": 10.42,
      "tolerance": 0.01
    },
    {
      "daysUntilDue": -30,
      "expectedUrgency": 10.999,
      "tolerance": 0.001
    }
  ]
}
```

### Performance Considerations

**Computational Complexity**: O(1) per task
- Single exponential calculation
- No loops or iterations
- Suitable for real-time ranking of 1000s of tasks

**Caching**: Not required - sigmoid calculation is fast enough to compute on every render.

**Sorting**: Final task list sorting is O(n log n) where n = number of tasks.

### Summary

The sigmoid-based urgency curve provides:

✅ **Mathematical Elegance**: Single continuous function, infinitely differentiable
✅ **Smooth Behavior**: No discontinuities or jumps - predictable for users
✅ **Natural Acceleration**: Tasks become more urgent faster as deadline approaches (f'' > 0)
✅ **Graceful Plateau**: Overdue tasks don't dominate forever (f'' < 0 when overdue)
✅ **Inflection at Deadline**: Exact turning point where urgency transitions (f'' = 0)
✅ **Cross-Platform Consistency**: IEEE 754 standard ensures identical results everywhere
✅ **Proven Model**: Logistic sigmoid used in statistics, ML, and cognitive psychology

This design ensures that task rankings feel natural, respond appropriately to deadlines, and scale well across thousands of tasks in distributed sync scenarios.

---

## Firebase Storage Architecture

**CRITICAL (v1.4) - Storage Model Clarification**: This protocol currently uses **per-user storage only**. The "global nodes collection" mentioned below is a **future enhancement** for efficient collaboration and is NOT part of the current v1 implementation.

### Current Architecture: Per-User Storage

**Active Storage Model** (v1.0-1.4): Each user stores their own nodes under their Firebase UID.

**Firestore path**: `users/{googleUserId}/changes/{nodeId}`

- All nodes uploaded by a user are stored in their personal namespace
- Simple security rules: `allow read, write: if request.auth.uid == googleUserId`
- No shared storage between users in v1 (collaboration is a future feature)
- Each device uploads to its authenticated user's path

### Future Enhancement: Global Nodes Collection (NOT IMPLEMENTED)

**Planned for v2+**: A global content-addressed store for efficient collaboration:

```json
{
  "content": { ... },
  "signature": "hex",
  "author": "crypto_userId",
  "accessList": ["userId1", ...],
  "createdAt": "ISO 8601"
}
```

**Firestore path**: `nodes/{sha256:hex}`

**Planned Architecture** (not yet implemented):
1. Clients upload to their per-user path: `users/{googleUserId}/changes/{nodeId}`
2. Cloud Function copies node to global store: `nodes/{nodeId}` (if not already present)
3. Cloud Function updates `accessList` on global node
4. Clients with permission can read from global store (deduplication)

**Status**: This is **design documentation only**. Current v1 implementations MUST use per-user storage exclusively.

### Identity Separation: OAuth vs Cryptographic

**IMPORTANT**: Firebase uses TWO independent identity systems:

1. **Google OAuth ID (Firebase UID)** - Controls cloud storage access
   - Used for: Firebase Firestore path segregation (`users/{googleUserId}/changes/...`)
   - Purpose: Access control - who can read/write to which Firebase collections
   - Example: `105903347225150947554` (numeric Google user ID)

2. **Cryptographic Identity (Public Key Hash)** - Proves node authorship
   - Used for: Node signatures and authorship (`author.userId` field)
   - Purpose: Verifies WHO created/signed each node (tamper-proof)
   - Example: `a1b2c3d4e5f6...` (SHA-256 hash of Ed25519 public key)

**Why Both?**
- Google ID: Firebase needs to segregate storage per user account (web2 access control)
- Crypto ID: DAG nodes can be authored by different devices/keys and shared across users (web3 verifiability)

**Key Principle**:
- Firebase paths use Google UID for **access control**
- Node signatures use crypto ID for **authorship verification**
- These identities are orthogonal - a single Google user can have multiple crypto keys (multi-device)
- Multiple Google users can share nodes authored by the same crypto key (collaboration)

### Firebase Storage Structure

All nodes uploaded by a Google user are stored under their Firebase UID:

**Firestore path**: `users/{googleUserId}/changes/{nodeId}`

- `googleUserId`: Firebase Authentication UID (from `auth.currentUser.uid`)
- `nodeId`: SHA-256 content hash of the node
- Each node contains `author.userId` field with the crypto public key hash (independent of Google ID)

**Example**:
```
users/
  105903347225150947554/           ← Google OAuth UID (access control)
    changes/
      sha256:abc123.../             ← Node ID (content hash)
        version: "1"
        author:
          userId: "a1b2c3d4..."     ← Crypto public key hash (authorship)
        signature: "..."             ← Ed25519 signature proving authorship
```

### Sync Process

**Upload**:
1. Authenticate with Firebase (get Google UID from `auth.currentUser.uid`)
2. Store node at `users/{googleUserId}/changes/{nodeId}`
3. Node contains `author.userId` field with crypto key hash (proves who signed it)

**Download**:
1. Authenticate with Firebase (verify `auth.currentUser.uid` matches path)
2. Query all changes from `users/{googleUserId}/changes/`
3. Validate v1 protocol compliance for each node
4. Verify signatures using `author.userId` public key (NOT Google UID!)
5. Reconstruct state from all valid nodes

---

## Git-Like Local-First Paradigm

The REDO protocol follows a **git-like distributed architecture** where local operations are ALWAYS instant and NEVER block on remote backends.

### Core Architecture Principle

**Local state IS the source of truth. Remote backends are replication targets, not blockers.**

This is identical to how git works:
- `git log` shows local commits INSTANTLY without querying `origin`
- `git commit` records changes LOCALLY without waiting for push
- `git fetch` retrieves remote changes in BACKGROUND (non-blocking)
- `git push` sends local changes to remote (async, can fail without breaking local operations)

### Implementation Requirements

#### Local Operations MUST Be Instant

All read operations MUST return from local storage ONLY:

```typescript
// ✅ CORRECT: Returns local state instantly
async getCurrentTasks(): Promise<RedoTask[]> {
  // Read ONLY from localStorage (instant)
  const localChanges = await changeLogStorage.getAllChanges();

  // Reconstruct tasks from local changes
  const tasks = StateReconstructor.reconstructTasksFromNodes(localChanges);

  // Trigger background sync (non-blocking)
  setTimeout(() => this.syncFromRemoteBackgrounds(), 100);

  return tasks; // Return immediately
}

// ❌ WRONG: Blocks on Firebase fetch
async getCurrentTasks(): Promise<RedoTask[]> {
  // NEVER do this - blocks UI waiting for network
  await this.firebaseBackend.getChanges();
  // ...
}
```

**Like git commands:**
- `getCurrentTasks()` = `git log` (reads local history only)
- `syncFromRemoteBackgrounds()` = `git fetch` (pulls remote changes in background)
- `saveChange()` = `git commit` (records change locally)
- `uploadChangeToBackend()` = `git push` (sends local changes to remote)

#### Write Operations MUST Not Block

All write operations MUST record changes locally first, then sync to remote in background:

```typescript
// ✅ CORRECT: Record locally, sync in background
async createTask(task: RedoTask): Promise<void> {
  // 1. Create change node and save to localStorage (instant)
  const change = RedoNodeUtils.createNode('CREATE', task.guid, payload, parents);
  await changeLogStorage.saveChange(change);

  // 2. Trigger background upload (non-blocking)
  setTimeout(() => this.uploadChangeToBackend(change), 100);

  // 3. Return immediately - don't wait for remote
}

// ❌ WRONG: Blocks on Firebase upload
async createTask(task: RedoTask): Promise<void> {
  const change = RedoNodeUtils.createNode('CREATE', task.guid, payload, parents);

  // NEVER do this - blocks UI waiting for network
  await this.firebaseBackend.saveChange(change);
  await changeLogStorage.saveChange(change);
}
```

#### No "Optimistic Updates" Needed

Because local storage is the source of truth, there's NO NEED for "optimistic update" patterns:

```typescript
// ✅ CORRECT: Just read from local storage (already instant)
async archiveTask(taskId: string): Promise<void> {
  // Record ARCHIVE action locally
  await distributedSyncService.recordChange('ARCHIVE', taskId, {});

  // Re-fetch from local storage (instant - no network)
  const tasks = await distributedSyncService.getCurrentTasks();
  setTasks(tasks);
}

// ❌ WRONG: Unnecessary "optimistic update" band-aid
async archiveTask(taskId: string): Promise<void> {
  // Remove from React state immediately
  setTasks(prevTasks => prevTasks.filter(t => t.guid !== taskId));

  // Then record change
  await distributedSyncService.recordChange('ARCHIVE', taskId, {});

  // Then fetch (blocks on network)
  const tasks = await distributedSyncService.getCurrentTasks();
  setTasks(tasks);
}
```

The "optimistic update" pattern is a code smell indicating that `getCurrentTasks()` is blocking on remote fetches. Fix the architecture instead of adding band-aids.

#### Background Sync Strategy

Remote synchronization MUST happen in background without blocking the UI:

```typescript
async syncFromRemoteBackgrounds(): Promise<void> {
  // Fetch changes from all remote backends (Firebase, etc.)
  const remoteChanges = await Promise.allSettled(
    backends.map(b => b.getChanges({}))
  );

  // Merge new changes into local storage
  const localChanges = await changeLogStorage.getAllChanges();
  const localIds = new Set(localChanges.map(c => c.id));
  const newChanges = remoteChanges.filter(c => !localIds.has(c.id));

  if (newChanges.length > 0) {
    // Save to localStorage
    for (const change of newChanges) {
      await changeLogStorage.saveChange(change);
    }

    // Notify UI to refresh (local read - instant)
    window.dispatchEvent(new CustomEvent('tasks-changed'));
  }
}
```

This function is called:
- AFTER returning local state from `getCurrentTasks()`
- Periodically in background (like `git fetch` on a timer)
- When user explicitly clicks "Sync" button
- NEVER synchronously in the main execution path

#### Comparison to Git Operations

| REDO Operation | Git Equivalent | Behavior |
|----------------|----------------|----------|
| `getCurrentTasks()` | `git log` | Reads local history only, INSTANT |
| `createTask()` | `git commit` | Records change locally, INSTANT |
| `syncFromRemoteBackgrounds()` | `git fetch` | Pulls remote changes in background, NON-BLOCKING |
| `uploadChangeToBackend()` | `git push` | Sends local changes to remote, ASYNC |
| Change log in localStorage | `.git/objects/` | Local history storage, ALWAYS available |
| Firebase/remote backend | `origin` remote | Replication target, NOT source of truth |

### Benefits of This Architecture

1. **Instant UI**: All operations return immediately from local storage
2. **Offline-First**: Works perfectly without network connectivity
3. **Network Resilience**: Slow/failed remote fetches don't block UI
4. **Simple Code**: No need for "optimistic update" patterns
5. **Git-Like Reliability**: Battle-tested distributed architecture
6. **Cross-Platform**: Same pattern works for web, mobile, desktop, CLI

### Anti-Patterns to Avoid

❌ **NEVER** await remote fetches in `getCurrentTasks()`
❌ **NEVER** await remote uploads in `createTask()`/`updateTask()`/etc.
❌ **NEVER** use "optimistic updates" to hide slow remote operations
❌ **NEVER** make UI wait for network operations
❌ **NEVER** treat remote backends as "source of truth" for reads

✅ **ALWAYS** read from local storage first
✅ **ALWAYS** write to local storage first
✅ **ALWAYS** sync to/from remote in background
✅ **ALWAYS** treat localStorage as the source of truth
✅ **ALWAYS** make remote sync async and non-blocking

---

## Implementation Requirements

### Cross-Platform Compatibility

**CRITICAL**: SHA-256 hashes MUST match exactly between implementations.

All implementations must:
- Use identical canonical JSON serialization (JCS/RFC 8785)
- Produce byte-identical hashes for the same logical node
- Verify cross-platform compatibility with shared test vectors

### TypeScript (Web App)

**Reference Path**: `/Users/vn57dec/WebstormProjects/redo-web-app/src/models/RedoNode.ts`

**Required classes**:
- `RedoNodeUtils.createNode()` - Create v1 nodes
- `RedoNodeUtils.isValidV1Node()` - Validate nodes
- `RedoNodeUtils.sortByLogicalTime()` - Sort nodes deterministically
- `StateReconstructor.reconstructTasksFromNodes()` - Rebuild state

### Kotlin (CLI)

**Reference Path**: `/Users/vn57dec/IdeaProjects/redo/src/main/kotlin/model/RedoNode.kt`

**Required classes**:
- `RedoNodeUtils.createNode()` - Create v1 nodes
- `RedoNodeUtils.isValidV1Node()` - Validate nodes
- `RedoNodeUtils.sortByTimestamp()` - Sort nodes deterministically
- `StateReconstructor.reconstructTasks()` - Rebuild state

**Kotlin data model sketch**:

```kotlin
@Serializable
data class RedoNode(
  val id: String,
  val version: Int = 1,
  val parents: List<String>,
  val timestamp: NodeTimestamp,
  val author: NodeAuthor,
  val action: ChangeAction,
  val taskId: String,
  val data: NodeData,
  val signature: String? = null
)

@Serializable
data class NodeTimestamp(
  val lamport: Long,
  val wall: String
)

@Serializable
data class NodeAuthor(
  val userId: String,
  val deviceId: String,
  val publicKey: String,
  val name: String? = null,
  val email: String? = null,
  val deviceName: String? = null
)

@Serializable
enum class ChangeAction {
  CREATE, UPDATE, DELETE,
  COMPLETE_TODO, CREATE_TODO, SNOOZE,
  ARCHIVE, UNARCHIVE, MERGE
}

@Serializable
data class NodeData(
  val payload: JsonObject // Raw for hashing before parsing
)

// Strongly-typed payloads after verification
sealed interface ActionPayload

@Serializable
data class CreatePayload(
  val title: String,
  val description: String? = null,
  val privacy: Boolean? = null,
  val storyPoints: Int? = null,
  val priority: Int? = null,
  val frequencyDays: Int? = null
) : ActionPayload

// ... (other payload classes)
```

---

## Normative JSON Schema

The following JSON Schema (draft 2020-12) is **normative**. All implementations MUST validate nodes against this schema.

```json
{
  "$id": "https://redo.spec/v1/redo-node.schema.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RedoNode (v1)",
  "type": "object",
  "required": ["id", "version", "parents", "timestamp", "author", "action", "taskId", "data"],
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^sha256:[0-9a-f]{64}$"
    },
    "version": {
      "type": "integer",
      "const": 1
    },
    "parents": {
      "type": "array",
      "items": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "minItems": 0,
      "maxItems": 10
    },
    "timestamp": {
      "type": "object",
      "required": ["lamport", "wall"],
      "properties": {
        "lamport": {
          "type": "integer",
          "minimum": 1
        },
        "wall": {
          "type": "string",
          "format": "date-time",
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"
        }
      },
      "additionalProperties": false
    },
    "author": {
      "type": "object",
      "required": ["userId", "deviceId", "publicKey"],
      "properties": {
        "userId": {
          "type": "string",
          "pattern": "^[0-9a-f]{32,64}$",
          "minLength": 32,
          "maxLength": 64
        },
        "deviceId": {
          "type": "string",
          "minLength": 1
        },
        "publicKey": {
          "type": "string",
          "pattern": "^[0-9a-f]{64}$"
        },
        "name": {
          "type": "string"
        },
        "email": {
          "type": "string",
          "format": "email"
        },
        "deviceName": {
          "type": "string"
        }
      },
      "additionalProperties": false
    },
    "action": {
      "type": "string",
      "enum": [
        "CREATE", "UPDATE", "DELETE",
        "COMPLETE_TODO", "CREATE_TODO", "SNOOZE",
        "ARCHIVE", "UNARCHIVE", "MERGE"
      ]
    },
    "taskId": {
      "type": "string",
      "format": "uuid"
    },
    "data": {
      "type": "object",
      "required": ["payload"],
      "properties": {
        "payload": {}
      },
      "additionalProperties": false
    },
    "signature": {
      "type": "string",
      "pattern": "^[0-9a-f]{128}$"
    }
  },
  "allOf": [
    {
      "if": {
        "properties": {
          "action": { "const": "CREATE" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "type": "array",
            "maxItems": 0
          },
          "timestamp": {
            "properties": {
              "lamport": {
                "const": 1
              }
            }
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "required": ["title"],
                "properties": {
                  "title": { "type": "string", "minLength": 1 },
                  "description": { "type": "string" },
                  "privacy": { "type": "boolean" },
                  "storyPoints": { "type": "integer", "minimum": 0 },
                  "priority": { "type": "integer" },
                  "frequencyDays": { "type": "integer", "minimum": 1 }
                },
                "additionalProperties": false
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": { "const": "UPDATE" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 1,
            "maxItems": 1
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "properties": {
                  "title": { "type": "string" },
                  "description": { "type": "string" },
                  "priority": { "type": "integer" },
                  "storyPoints": { "type": "integer", "minimum": 0 },
                  "frequencyDays": { "type": "integer", "minimum": 1 },
                  "privacy": { "type": "boolean" }
                },
                "additionalProperties": false,
                "minProperties": 1
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": { "const": "COMPLETE_TODO" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 1,
            "maxItems": 1
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "required": ["todoTaskId", "completed"],
                "properties": {
                  "todoTaskId": { "type": "string", "format": "uuid" },
                  "completed": { "type": "string", "format": "date-time" },
                  "notes": { "type": "string" }
                },
                "additionalProperties": false
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": { "const": "CREATE_TODO" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 1,
            "maxItems": 1
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "required": ["todoTaskId", "deadline"],
                "properties": {
                  "todoTaskId": { "type": "string", "format": "uuid" },
                  "deadline": { "type": "string", "format": "date-time" },
                  "notes": { "type": "string" }
                },
                "additionalProperties": false
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": { "const": "SNOOZE" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 1,
            "maxItems": 1
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "required": ["todoTaskId"],
                "properties": {
                  "todoTaskId": { "type": "string", "minLength": 1 },
                  "daysToExtend": { "type": "integer", "minimum": 1 },
                  "newDeadline": { "type": "string", "format": "date-time" },
                  "notes": { "type": "string" }
                },
                "oneOf": [
                  { "required": ["daysToExtend"] },
                  { "required": ["newDeadline"] }
                ],
                "additionalProperties": false
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": {
            "enum": ["ARCHIVE", "UNARCHIVE"]
          }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 1,
            "maxItems": 1
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "additionalProperties": false
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": { "const": "DELETE" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 1,
            "maxItems": 1
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "required": ["deletedChain"],
                "properties": {
                  "deletedChain": {
                    "type": "array",
                    "items": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "minItems": 1
                  }
                },
                "additionalProperties": false
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "action": { "const": "MERGE" }
        }
      },
      "then": {
        "properties": {
          "parents": {
            "minItems": 2,
            "maxItems": 10
          },
          "data": {
            "properties": {
              "payload": {
                "type": "object",
                "required": ["base"],
                "properties": {
                  "base": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "policy": {
                    "type": "object",
                    "properties": {
                      "defaultStrategy": {
                        "type": "string",
                        "enum": ["ours", "theirs", "union", "lww", "manual", "max", "min"]
                      },
                      "lwwTiebreakers": {
                        "type": "array",
                        "items": {
                          "type": "string",
                          "enum": ["lamport", "wall", "author"]
                        }
                      },
                      "arrayStrategy": {
                        "type": "string",
                        "enum": ["union", "lww"]
                      }
                    },
                    "additionalProperties": false
                  },
                  "resolutions": {
                    "type": "object",
                    "properties": {
                      "task": {
                        "type": "array",
                        "items": {
                          "type": "object",
                          "required": ["path", "strategy"],
                          "properties": {
                            "path": { "type": "string", "minLength": 1 },
                            "strategy": {
                              "type": "string",
                              "enum": ["ours", "theirs", "union", "lww", "manual", "max", "min"]
                            },
                            "chosenParent": {
                              "type": "string",
                              "pattern": "^sha256:[0-9a-f]{64}$"
                            },
                            "value": {},
                            "notes": { "type": "string" }
                          },
                          "allOf": [
                            {
                              "if": {
                                "properties": {
                                  "strategy": { "const": "manual" }
                                }
                              },
                              "then": {
                                "required": ["value"]
                              }
                            },
                            {
                              "if": {
                                "properties": {
                                  "strategy": {
                                    "enum": ["ours", "theirs"]
                                  }
                                }
                              },
                              "then": {
                                "required": ["chosenParent"]
                              }
                            }
                          ],
                          "additionalProperties": false
                        }
                      },
                      "todos": {
                        "type": "array",
                        "items": {
                          "type": "object",
                          "required": ["todoTaskId", "fields"],
                          "properties": {
                            "todoTaskId": { "type": "string", "minLength": 1 },
                            "fields": {
                              "type": "array",
                              "items": {
                                "type": "object",
                                "required": ["path", "strategy"],
                                "properties": {
                                  "path": { "type": "string", "minLength": 1 },
                                  "strategy": {
                                    "type": "string",
                                    "enum": ["ours", "theirs", "union", "lww", "manual", "max", "min"]
                                  },
                                  "chosenParent": {
                                    "type": "string",
                                    "pattern": "^sha256:[0-9a-f]{64}$"
                                  },
                                  "value": {},
                                  "notes": { "type": "string" }
                                },
                                "allOf": [
                                  {
                                    "if": {
                                      "properties": {
                                        "strategy": { "const": "manual" }
                                      }
                                    },
                                    "then": {
                                      "required": ["value"]
                                    }
                                  },
                                  {
                                    "if": {
                                      "properties": {
                                        "strategy": {
                                          "enum": ["ours", "theirs"]
                                        }
                                      }
                                    },
                                    "then": {
                                      "required": ["chosenParent"]
                                    }
                                  }
                                ],
                                "additionalProperties": false
                              }
                            }
                          },
                          "additionalProperties": false
                        }
                      }
                    },
                    "additionalProperties": false
                  }
                },
                "additionalProperties": false
              }
            }
          }
        }
      }
    }
  ],
  "additionalProperties": false
}
```

---

## Canonicalization and Hashing

### Section Overview

Section 13 now includes canonicalization rules **and** three normative sub-sections:
13.1 Canonical Hashing Test Vector, 13.2 Merge Policy Test Scenario, and 13.3 Reference Library Recommendations.

### RFC 8785 (JSON Canonicalization Scheme - JCS)

All implementations MUST use **RFC 8785 (JCS)** for canonical JSON serialization:

1. **UTF-8 encoding**
2. **Lexicographically sorted object keys** (by Unicode code point)
3. **Minimal JSON** (no insignificant whitespace)
4. **Numbers**:
   - Integers as digits (no leading zeros)
   - Decimals in minimal form (no trailing zeros)
   - No `NaN` or `Infinity`
5. **Booleans**: lowercase `true`/`false`
6. **Null**: lowercase `null`
7. **Strings**: UTF-8 with `\uXXXX` escapes for control chars; quotes escaped as `\"`

### Hash Computation

```
nodeId = "sha256:" + lowercase_hex(SHA256(canonicalJSON(body)))
```

Where:
- `body` is the RedoNode with `id` and `signature` fields **excluded**
- `lowercase_hex()` converts the hash to lowercase hexadecimal (64 chars)
- Result format: `sha256:` prefix + 64 lowercase hex characters

### Signature Computation

```
signature = lowercase_hex(Ed25519.sign(canonicalJSON(body), privateKey))
```

Where:
- `body` is the same canonical JSON used for hashing (excludes `id` and `signature`)
- `lowercase_hex()` converts the signature to lowercase hexadecimal (128 chars)
- Result format: 128 lowercase hex characters (no prefix)

---

## Reference Test Vectors

This section provides canonical test vectors for implementers to verify their hashing, merge resolution, and serialization logic.

### 13.1 Canonical Hashing Test Vector

**Input Node (before hashing):**
```json
{
  "version": 1,
  "parents": [],
  "timestamp": {
    "lamport": 1,
    "wall": "2025-10-26T00:00:00.000Z"
  },
  "author": {
    "userId": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
    "deviceId": "test_device",
    "publicKey": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
  },
  "action": "CREATE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": {
      "title": "Test Task",
      "priority": 1
    }
  }
}
```

**Expected Canonical JSON (RFC 8785):**
```json
{"action":"CREATE","author":{"deviceId":"test_device","publicKey":"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2","userId":"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"},"data":{"payload":{"priority":1,"title":"Test Task"}},"parents":[],"taskId":"550e8400-e29b-41d4-a716-446655440000","timestamp":{"lamport":1,"wall":"2025-10-26T00:00:00.000Z"},"version":1}
```

**Expected SHA-256 Hash:**
```
sha256:8f7e3d2c1b9a8f7e6d5c4b3a2918f7e6d5c4b3a29180f7e6d5c4b3a2918f7e6d
```
*(Note: This is a reference example. Actual hash depends on exact canonical serialization.)*

**Verification:**
```typescript
const canonicalJSON = canonicalize(node); // RFC 8785
const hash = sha256(canonicalJSON);
const id = `sha256:${hash.toLowerCase()}`;
assert(id === node.id);
```

### 13.2 Merge Policy Test Scenario

**Setup:**
```
Base State (lamport=1): { title: "Task", priority: 3 }
Parent A (lamport=2): { title: "Task Updated", priority: 3 }
Parent B (lamport=3): { title: "Task", priority: 5 }
```

**Merge Node:**
```json
{
  "action": "MERGE",
  "data": {
    "payload": {
      "base": "sha256:base_node_id...",
      "parents": ["sha256:parentA_id...", "sha256:parentB_id..."],
      "policy": { "defaultStrategy": "lww" }
    }
  }
}
```

**Expected Resolution (Last-Write-Wins):**
```json
{
  "title": "Task",         // Parent B wins (higher lamport=3)
  "priority": 5            // Parent B wins (higher lamport=3)
}
```

**Verification:**
```typescript
const resolved = applyMerge(baseState, [parentA, parentB], mergeNode);
assert(resolved.title === "Task");
assert(resolved.priority === 5);
```

### 13.3 Reference Library Recommendations

To ensure cross-platform consistency, implementers SHOULD use these battle-tested libraries:

| Platform | Canonicalization (RFC 8785) | SHA-256 Hashing | Ed25519 Signatures |
|----------|------------------------------|-----------------|-------------------|
| **TypeScript/Node.js** | `json-canonicalize` | `crypto` (built-in) | `@noble/ed25519` or `tweetnacl` |
| **Kotlin (JVM)** | `kotlinx.serialization` + custom | `java.security.MessageDigest` | `lazysodium-java` or `curve25519-java` |
| **Swift (iOS/Mac)** | `JSONSerialization` + custom | `CryptoKit.SHA256` | `CryptoKit` (iOS 13+) |
| **Browser (Web)** | `json-canonicalize` | `SubtleCrypto.digest()` | `@noble/ed25519` |

**Protocol Schema Hash (for Runtime Verification):**
```
sha256:REDO_v1_schema_hash_placeholder
```
*(Implementations MAY verify they're using the correct protocol version by checking this hash against the normative JSON Schema.)*

**Why Test Vectors Matter:**
- ✅ Verify hash computation matches across platforms
- ✅ Ensure merge policies resolve identically
- ✅ Catch canonicalization bugs (field ordering, number precision)
- ✅ Enable interoperability testing between implementations
- ✅ Provide reference inputs for CI/CD validation

---

## Example Flows

### Genesis Block Pattern (Recommended CREATE Flow - v1.2+)

**Node 1: CREATE (Genesis Block - Metadata Only)**
```json
{
  "id": "sha256:abc123...",
  "version": 1,
  "parents": [],
  "timestamp": {
    "lamport": 1,
    "wall": "2025-10-09T12:00:00.000Z"
  },
  "author": {
    "userId": "a1b2c3d4...",
    "deviceId": "device_xyz",
    "publicKey": "ed25519_public_key_hex"
  },
  "action": "CREATE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": {
      "title": "Buy milk",
      "priority": 3,
      "frequencyDays": 7
    }
  },
  "signature": "abcd1234..."
}
```

**Node 2: CREATE_TODO (First Actionable Instance)**
```json
{
  "id": "sha256:def456...",
  "version": 1,
  "parents": ["sha256:abc123..."],
  "timestamp": {
    "lamport": 2,
    "wall": "2025-10-09T12:00:01.000Z"
  },
  "author": {
    "userId": "a1b2c3d4...",
    "deviceId": "device_xyz",
    "publicKey": "ed25519_public_key_hex"
  },
  "action": "CREATE_TODO",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": {
      "deadline": "2025-10-16T12:00:00.000Z",
      "notes": ""
    }
  },
  "signature": "efgh5678..."
}
```

**Important (v1.2+)**: UIs SHOULD create both nodes together when user clicks "Create Task". The CREATE alone does NOT make the task actionable - the CREATE_TODO is required.

### Complete Todo Flow (Two Nodes)

**CRITICAL PROTOCOL REQUIREMENT**: Completing a recurring todo and creating the next todo MUST be recorded as TWO SEPARATE nodes in the change log. This is NEVER implicit.

**UI vs Protocol Behavior:**
- **UI**: User clicks one "Complete" button → feels like one action
- **Protocol**: Application MUST send TWO separate nodes to the change log:
  1. COMPLETE_TODO (marks current todo as completed)
  2. CREATE_TODO (creates next todo with deadline = completion_time + frequency_days)

**Why Two Nodes?**
- Allows distributed sync: One device can complete a todo while another creates a different todo
- Enables conflict resolution: Completion and creation are independent actions
- Provides audit trail: See exactly when todo was completed vs when next was created
- Supports recovery: If CREATE_TODO fails, system knows to retry without duplicating completion

**Implementation Note**: The two events should be sent sequentially with separate Lamport clocks. Do NOT combine them into a single UPDATE action.

---

**Node 1: COMPLETE_TODO**
```json
{
  "id": "sha256:def456...",
  "version": 1,
  "parents": ["sha256:abc123..."],
  "timestamp": {
    "lamport": 42,
    "wall": "2025-10-09T14:30:00.000Z"
  },
  "author": { ... },
  "action": "COMPLETE_TODO",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": {
      "todoTaskId": "3b6f8b9d-c5e4-4a2f-9d7b-1f3a5c8e2b4d",
      "completed": "2025-10-09T14:30:00.000Z",
      "notes": "Bought whole milk"
    }
  },
  "signature": "..."
}
```

**Node 2: CREATE_TODO**
```json
{
  "id": "sha256:ghi789...",
  "version": 1,
  "parents": ["sha256:def456..."],
  "timestamp": {
    "lamport": 43,
    "wall": "2025-10-09T14:30:01.000Z"
  },
  "author": { ... },
  "action": "CREATE_TODO",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": {
      "deadline": "2025-10-16T14:30:00.000Z",
      "notes": ""
    }
  },
  "signature": "..."
}
```

### Simple Merge Flow

```json
{
  "id": "sha256:merge123...",
  "version": 1,
  "parents": [
    "sha256:headA...",
    "sha256:headB..."
  ],
  "timestamp": {
    "lamport": 120,
    "wall": "2025-10-09T15:00:00.000Z"
  },
  "author": { ... },
  "action": "MERGE",
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "payload": {
      "base": "sha256:base999...",
      "policy": {
        "defaultStrategy": "lww",
        "lwwTiebreakers": ["lamport", "wall", "author"],
        "arrayStrategy": "union"
      }
    }
  },
  "signature": "..."
}
```

---

## Security Considerations

This section is non-normative and discusses security properties of the REDO v1 protocol.

### Replay Attack Resistance

The content-addressed nature of nodes provides inherent replay attack resistance:
- Each node is identified by its SHA-256 hash
- Replaying an existing node results in the same ID, causing deduplication
- No state change occurs from replayed nodes
- DAG structure prevents out-of-order replays from corrupting state

However, implementations SHOULD still validate timestamps and signatures to detect malformed replay attempts.

### Denial-of-Service (DoS) Mitigation

**Primary Defense**: 1MB payload size limit per node
- Network layer (Firebase Functions, API gateways) SHOULD enforce this limit before processing
- Prevents resource exhaustion from oversized nodes
- Clients SHOULD validate payload size before accepting nodes

**Additional Mitigations**:
- Rate limiting on node uploads (per-user, per-device)
- Maximum DAG depth limits per task (implementation-defined)
- Firebase security rules can restrict write rates and total storage per user

### Key Compromise and Revocation

**Current Limitation**: v1.6 does **NOT** include a key revocation mechanism.

**Implications**:
- Node signatures prove authorship by a specific private key at a point in time
- If a device's private key is compromised, nodes signed with it remain valid indefinitely
- Compromised keys could allow forgery of new nodes attributed to that key
- No protocol-level mechanism exists to invalidate previously-valid signatures

**Mitigation Strategies**:
- Secure key storage on devices (hardware-backed keystores, OS-level protection)
- Manual intervention required for compromised keys (contact system admin)
- Future versions may introduce REVOKE_KEY action or revocation lists

**Recommendation**: System administrators should establish out-of-band procedures for handling compromised keys in production environments.

---

## Version History

- **v1.7** (October 27, 2025): **CRITICAL BREAKING CHANGE** - Deterministic TodoTask IDs
  - **CRITICAL FIX**: The CREATE_TODO payload now REQUIRES a `todoTaskId` field (UUID v4).
  - **ROOT CAUSE**: The previous spec (v1.6) failed to include a stable ID in CREATE_TODO nodes. This forced reconstruction logic to generate a new random UUID on every replay, breaking all COMPLETE_TODO and SNOOZE references and leading to deterministic data corruption.
  - **IMPACT**: This was a fundamental protocol design flaw. All data created under v1.6 and prior that involves CREATE_TODO is considered unstable and non-recoverable.
  - **BEHAVIOR CHANGE**: State reconstruction now uses the todoTaskId from the CREATE_TODO payload to assign a stable GUID to todo instances, ensuring all references remain valid across reconstructions.
  - **ACTION REQUIRED**:
    - All client implementations MUST be updated to generate a `todoTaskId` upon creation of a CREATE_TODO node and include it in the payload.
    - All existing v1.6 and earlier data MUST be wiped.
    - Applications should display a migration notice to users explaining data will be cleared.
  - **Attribution**: Critical flaw and correct fix identified by Claude (Anthropic) during implementation review (Build 66).
  - **Status**: Breaking change - requires full data wipe

- **v1.6** (October 26, 2025): **ENHANCEMENT** - Developer Experience & Testability Improvements
  - **STRUCTURE:** Integrated all new materials contextually rather than appending them to the end of the spec
    - Reference Test Vectors → Section 13.1–13.3
    - Error Codes → Section 5.1
    - Reserved Field Names → Section 4
    - Merge Pseudocode → Section 7 (MERGE)
  - **NEW: Protocol Philosophy Section**
    - Added core design tenets: local-first, determinism, explicitness, recoverability
    - Frames intent behind strict enforcement rules
    - Emphasizes "Broken Branch" safety model and explicit actions
  - **NEW: Terminology Quick Reference Table**
    - Distinguishes "Broken Branch" from "Deleted Chain"
    - Clarifies persistence and restorability semantics
    - Added "If One Lives, All Ancestors Live" key principle
  - **NEW: Reserved Field Names Section**
    - Documents node-level, timestamp-level, author-level, and payload-level reserved fields
    - Prevents collisions with future protocol enhancements
    - Provides safe extension pattern via namespaced fields
  - **NEW: Error Codes and Validation Reasons (5.1)**
    - Standardized error codes (E_INVALID_SIGNATURE, E_SCHEMA_MISMATCH, etc.)
    - TypeScript and Kotlin implementation examples
    - Enables structured logging and cross-platform interoperability
  - **NEW: Merge Policy Evaluation Pseudocode**
    - Formalized deterministic merge resolution algorithm
    - Explicit priority order: explicit resolutions > auto-resolution > policy
    - Documented lww, union, max strategies with TypeScript implementation
  - **NEW: Reference Test Vectors (Section 13)**
    - 13.1: Canonical hashing test vector with expected SHA-256 hash
    - 13.2: Merge policy test scenario with expected resolution
    - 13.3: Reference library recommendations for TypeScript, Kotlin, Swift
    - Protocol schema hash for runtime verification
  - **NEW: Visual ASCII Diagram**
    - Added "Broken Branch" diagram in Validation Rules section
    - Clear visual representation of ancestor preservation vs. descendant pruning
    - Helps implementers quickly grasp core safety model
  - **NEW: Security Considerations Section**
    - Discusses replay attack resistance from content-addressed nodes
    - DoS mitigation via 1MB payload limit and rate limiting
    - Documents key compromise limitations (no revocation in v1.6)
    - Provides practical guidance for production security
  - **NO BEHAVIORAL CHANGES**: All changes are documentation enhancements only
  - **Why This Matters**:
    - Reduces implementation errors via clear examples
    - Enables interoperability testing with canonical test vectors
    - Provides structured error handling across platforms
    - Documents safe extension patterns for custom fields
  - **Status**: Production-ready with enhanced developer documentation
  - **Attribution**: Enhancement proposal by ChatGPT 4.0 based on developer feedback

- **v1.5** (October 26, 2025): **BREAKING CHANGE** - Protocol Compliance Tightening & Branch Resurrection Clarification
  - **BREAKING: Removed `archived` field from UPDATE** (use ARCHIVE/UNARCHIVE actions instead)
    - UPDATE with `archived` or `archive` field → Chain INVALIDATED
    - JSON Schema updated: UPDATE payload no longer allows archived field
    - Implementation enforcement: UPDATE filters out archived/deleted fields
    - Rationale: State management actions should be explicit, not hidden in metadata updates
  - **BREAKING: Added `deleted` field validation to UPDATE**
    - UPDATE with `deleted` field → Chain INVALIDATED
    - Use DELETE tombstone for deletion, not UPDATE
  - **NEW: DELETE tombstone enforcement in JSON Schema**
    - DELETE without `deletedChain` → Chain INVALIDATED
    - All implementations MUST build complete ancestry chain for DELETE nodes
    - Implementation already correct (DistributedSyncService.ts builds deletedChain)
  - **CLARIFIED: Branch Resurrection Semantics** ("If One Lives, All Ancestors Live")
    - If ANY node branches from a deleted ancestor, that ancestor MUST be preserved
    - Surviving nodes keep their entire ancestral lineage alive
    - DELETE tombstones only succeed in pruning dead-end branches
    - This is git-like behavior: branches can resurrect deleted history
  - **CLARIFIED: UNDELETE is NOT supported**
    - DELETE is terminal for that branch
    - No UNDELETE or RESTORE action defined
    - Deleted tasks can only be recreated as NEW tasks (new taskId)
    - Branch resurrection is NOT undeletion - it's history preservation
  - **CLARIFIED: INVALIDATE is application-level concept**
    - NOT a protocol action - purely internal state transition
    - Applications detect violations and mark chains as invalidated locally
    - Similar to Git ignoring malformed commits during log replay
  - **NEW MENTAL MODEL (Build 55): "Broken Branch" Principle**
    - Protocol violations don't destroy entire task history - they prune the broken branch
    - Invalid node and descendants REJECTED; ancestor history PRESERVED
    - State reverts to longest surviving valid branch
    - Changed language from "chain invalidated, task deleted" to "node and descendants rejected"
    - Added visual example showing branch pruning vs ancestor preservation
    - Consolidated enforcement rules for clarity (6 rules instead of 8)
    - Distinguished DELETE (intentional pruning) from violations (unintentional breaks)
  - **Consistency Fixes (Build 52)**:
    - Fixed JSON Schema for COMPLETE_TODO to use `todoTaskId` (UUID) not `todoIndex`
    - Fixed COMPLETE_TODO example flow to use stable GUID references
    - Fixed reconstructTodos pseudo-code to use GUID-based todo lookup
    - Updated all "v1.2 compliance" references to "v1.5 compliance"
  - **Status**: Zero-tolerance enforcement - invalid data ignored and deleted
  - **Attribution**: Issues identified by Gemini 2.0 Flash comprehensive code review

- **v1.4** (October 26, 2025): **BREAKING CHANGE** - Stability & Determinism Fixes
  - **CRITICAL FIX: COMPLETE_TODO now uses todoTaskId (stable GUID) instead of todoIndex**
    - Prevents race conditions in distributed scenarios
    - todoIndex is fragile: concurrent operations can reorder array
    - todoTaskId is stable: references todo by immutable UUID
    - Rationale: Using array indices in distributed systems causes incorrect completions
  - **CRITICAL FIX: Sorting tiebreaker now uses node `id` instead of `author.userId`**
    - Ensures truly deterministic, unbiased ordering
    - Standard approach for content-addressed systems
    - Prevents subtle ordering biases based on who created nodes
  - **Storage Architecture Clarification**: Per-user storage is current; global nodes are future
    - v1 implementations MUST use `users/{googleUserId}/changes/` only
    - Global `nodes/` collection documented as planned v2+ feature
    - Eliminates ambiguity about which storage model to implement
  - **Terminology Change**: "CORRUPT" → "INVALIDATE" for chain violations
    - More precise: describes deterministic rejection, not silent modification
    - "Invalidated chain" is clearer than "corrupted chain"
  - **userId Derivation Note**: First 32 hex chars of Ed25519 public key (16 bytes)
    - Clarifies this is half the public key, not a hash
    - Collision risk is astronomically low (2^128 space)
  - **Status**: Production-ready distributed consensus protocol
  - **Attribution**: Critical issues identified by Gemini 2.0 Flash code review

- **v1.3** (October 26, 2025): **CLARIFICATION** - UPDATE Semantics + Client Transaction Pattern
  - **UPDATE is now explicitly metadata-only**: Cannot create/modify todos
  - **Forbidden**: Using UPDATE to set deadlines or manage todoTasks array
  - **Clarified client practice**: CREATE + CREATE_TODO as single transaction
  - **UPDATE use cases**: Only for editing task metadata (title, description, priority, storyPoints, frequencyDays, privacy)
  - **No backwards compatibility required**: v1.2 clients already follow this pattern (this is a clarification, not a breaking change)
  - **Rationale**: Eliminates ambiguity about UPDATE's role - it's a metadata editor, not a todo manager
  - **Implementation impact**: Validates that UPDATE payloads never contain todo-related operations

- **v1.2** (October 26, 2025): **BREAKING CHANGE** - Genesis Block Pattern + STRICT ENFORCEMENT
  - **CREATE is now metadata-only genesis block** (does not create actionable todo)
  - **CREATE_TODO required for actionable todos** (including first instance)
  - **COMPLETE_TODO validation strictly enforced**: Must reference CREATE_TODO nodes, never CREATE
  - **MANDATORY UI flow**: `CREATE` MUST be immediately followed by `CREATE_TODO`
  - **NO BACKWARDS COMPATIBILITY**: Pre-v1.2 patterns REJECTED during active development
  - **Protocol violations CORRUPT chains**: Duplicate CREATE or invalid COMPLETE_TODO deletes task, rejects all descendants
  - **Zero tolerance policy**: All implementations MUST strictly validate v1.2 compliance
  - **Development philosophy**: Fix the code, not the protocol - no migration support until production
  - Rationale: Separates task metadata (genesis) from actionable instances (todos)
  - Inspired by Bitcoin genesis block pattern for distributed systems
  - **Status**: Active development - strict enforcement prevents bad patterns from scaling

- **v1.1** (October 26, 2025): Task Ranking Algorithm specification
  - Added comprehensive Task Ranking Algorithm section
  - Documented smooth sigmoid S-curve urgency calculation
  - Specified derivative properties (f', f'') and mathematical rationale
  - Defined cross-platform consistency requirements
  - Added test vectors for urgency calculation
  - Introduced Ranking Playground visualization tool
  - Emphasized inflection point at deadline design

- **v1.0** (October 09, 2025): Initial stable protocol
  - Content-addressed nodes with SHA-256
  - Lamport logical clocks
  - Strict v1 validation
  - Global Firebase nodes architecture
  - Explicit CREATE_TODO action (no implicit todo creation)
  - Renamed from ChangeLogEntry to RedoNode
  - Renamed data.fields to data.payload
  - Added comprehensive MERGE support with Simple/Detailed lanes
  - Normative JSON Schema

---

## Contact & Contributions

This protocol is maintained as part of the REDO project.

**Questions?** File an issue in the project repository.

**Proposed Changes?** Protocol changes require:
1. Version bump (e.g., v1 → v2)
2. Migration path for existing data
3. Cross-platform implementation updates
4. Test vector validation

---

**END OF SPECIFICATION**
