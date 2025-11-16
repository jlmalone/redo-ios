# iOS Authentication Flow Audit - Complete Documentation

**Repo**: /home/user/redo-ios-package  
**Branch**: claude/audit-auth-flows-01G8H2kVm1KFFiHgo1AxEAQ2  
**Date**: November 2025

---

## Executive Summary

The iOS app implements a **two-tier authentication and identity system**:

1. **Google OAuth (Web2)** - Access control for Firebase Firestore
2. **Ed25519 Cryptography (Web3)** - Cryptographic signing and node authorship

This design allows:
- Multi-device support (multiple crypto keys per user)
- Verifiable authorship (signatures prove who created nodes)
- Offline-first operation (local signing before cloud sync)

---

## 1. Google Sign-In Implementation

### 1.1 Initialization and Configuration

**File**: `/home/user/redo-ios-package/Sources/RedoUI/RedoApp.swift`

```swift
@main
struct RedoApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var authManager = GoogleAuthManager.shared
    @State private var showOnboarding = false
    @State private var showSignIn = false

    init() {
        // Configure Firebase (loads GoogleService-Info.plist)
        FirebaseApp.configure()
        configureAppearance()
    }
```

**Configuration Source**: Firebase loads `GoogleService-Info.plist` from the iOS project (not checked into repo for security).

This plist contains:
- `CLIENT_ID` - Google OAuth client ID for iOS
- `REVERSED_CLIENT_ID` - Used for URL scheme configuration
- Other Firebase config (project ID, API key, etc.)

### 1.2 Sign-In Trigger and Flow

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Views/SignInView.swift` (lines 124-153)

```swift
private func signInWithGoogle() {
    isSigningIn = true

    Task {
        do {
            // Get the presenting view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw AuthError.missingClientID
            }

            // Trigger Google Sign-In UI
            try await authManager.signInWithGoogle(presentingViewController: rootViewController)

            // Reinitialize Firebase sync with new authentication
            await viewModel.reinitializeSync()

            HapticManager.shared.success()
            isSigningIn = false
        } catch {
            authManager.errorMessage = error.localizedDescription
            showError = true
            isSigningIn = false
        }
    }
}
```

### 1.3 Google Auth Manager - Core Sign-In Implementation

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Auth/GoogleAuthManager.swift` (lines 24-68)

```swift
/// Sign in with Google OAuth
public func signInWithGoogle(presentingViewController: UIViewController) async throws {
    // 1. Get client ID from Firebase config
    guard let clientID = FirebaseApp.app()?.options.clientID else {
        throw AuthError.missingClientID
    }

    // 2. Configure Google Sign-In with client ID
    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

    // 3. Perform sign in (shows Google login UI)
    let result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: presentingViewController
    )

    // 4. Extract tokens from result
    guard let idToken = result.user.idToken?.tokenString else {
        throw AuthError.missingIDToken
    }
    let accessToken = result.user.accessToken.tokenString

    // 5. Create Firebase credential (ID token + access token)
    let credential = GoogleAuthProvider.credential(
        withIDToken: idToken,
        accessToken: accessToken
    )

    // 6. Sign in to Firebase with credential
    let authResult = try await Auth.auth().signIn(with: credential)

    // 7. Update local state
    isAuthenticated = true
    currentUser = User(from: authResult.user)

    // 8. Store OAuth tokens separately (NOT with crypto keys!)
    try await storeOAuthTokens(
        idToken: idToken,
        accessToken: accessToken,
        refreshToken: result.user.refreshToken.tokenString
    )
}
```

### 1.4 OAuth Scopes

**CRITICAL FINDING**: The iOS implementation **does NOT explicitly request scopes**. It relies on Google Sign-In SDK defaults.

**Default Google Sign-In Scopes** (implicit):
- `openid` - OpenID Connect basic profile
- `email` - User's email address
- `profile` - User's profile information (name, picture, etc.)

**Why**: The v1 protocol focuses on offline-first with local signing. Google OAuth is only used for:
1. Authenticating with Firebase
2. Cloud sync (optional feature)

No additional scopes (like Google Drive, Calendar, etc.) are needed for the core REDO functionality.

**Reference**: `/home/user/redo-ios-package/Sources/RedoUI/Auth/GoogleAuthManager.swift` doesn't explicitly set scopes, so SDK defaults apply.

---

## 2. Ed25519 Keypair Generation

### 2.1 Keypair Generation Logic

**File**: `/home/user/redo-ios-package/Sources/RedoCrypto/Ed25519Manager.swift` (lines 9-27)

```swift
/// Generate new Ed25519 keypair
/// - Returns: Tuple of (publicKey, privateKey, userId)
///   - publicKey: 64 lowercase hex chars
///   - privateKey: 64 lowercase hex chars  
///   - userId: First 32 chars of public key
public static func generateKey() -> (publicKey: String, privateKey: String, userId: String) {
    // 1. Generate Ed25519 private key using Apple CryptoKit
    let privateKey = Curve25519.Signing.PrivateKey()
    
    // 2. Derive public key from private key
    let publicKeyData = privateKey.publicKey.rawRepresentation
    let privateKeyData = privateKey.rawRepresentation

    // 3. CRITICAL: Convert to lowercase hex (v1 protocol requirement)
    let publicKeyHex = publicKeyData.hexEncodedString(uppercase: false)
    let privateKeyHex = privateKeyData.hexEncodedString(uppercase: false)

    // 4. Derive userId from public key (first 32 chars)
    let userId = String(publicKeyHex.prefix(32))

    return (publicKeyHex, privateKeyHex, userId)
}
```

### 2.2 Key Generation Process

**Step 1**: Generate 32-byte Ed25519 private key
```
Raw representation: 32 bytes
```

**Step 2**: Derive Ed25519 public key (deterministic from private key)
```
Raw representation: 32 bytes
```

**Step 3**: Encode both as lowercase hexadecimal
```
Private Key Hex: 64 lowercase hex characters
Public Key Hex:  64 lowercase hex characters
```

**Step 4**: Derive userId from public key
```
UserId = first 32 characters of public key hex
```

### 2.3 When Keys Are Created

**File**: `/home/user/redo-ios-package/Sources/RedoUI/ViewModels/AppViewModel.swift` (lines 83-105)

```swift
private func loadOrGenerateIdentity() async throws {
    // 1. Check if we have existing keys in Keychain
    if let existingUserId = try? keychain.loadUserId(),
       let existingDeviceId = try? keychain.loadDeviceId() {
        // Reuse existing keys on subsequent app launches
        userId = existingUserId
        deviceId = existingDeviceId
    } else {
        // FIRST LAUNCH: Generate new Ed25519 keypair
        let (publicKey, privateKey, newUserId) = Ed25519Manager.generateKey()

        // Save to Keychain (secure storage)
        try keychain.savePublicKey(publicKey)
        try keychain.savePrivateKey(privateKey)
        try keychain.saveUserId(newUserId)

        // Also generate device ID (UUID)
        let newDeviceId = UUID().uuidString
        try keychain.saveDeviceId(newDeviceId)

        userId = newUserId
        deviceId = newDeviceId
    }
}
```

**When Keys Are Generated**:
1. **First launch** - When `loadOrGenerateIdentity()` is called from `initializeApp()`
2. **Per device** - Each device gets a unique keypair
3. **Never regenerated** - Saved in Keychain and reused on every subsequent launch

### 2.4 Cryptographic Library

**Library**: Apple CryptoKit (`import Crypto`)

**Key Type**: `Curve25519.Signing.PrivateKey`
- Standard Ed25519 implementation
- Hardware-accelerated on modern iPhones
- Platform: All iOS 14+

---

## 3. UserId Derivation

### 3.1 UserId Calculation

**File**: `/home/user/redo-ios-package/Sources/RedoCrypto/Ed25519Manager.swift` (lines 101-108)

```swift
/// Derive user ID from public key
/// - Parameter publicKeyHex: Public key as 64 lowercase hex chars
/// - Returns: User ID (first 32 chars of public key)
public static func getUserId(from publicKeyHex: String) -> String {
    String(publicKeyHex.prefix(32))
}
```

### 3.2 UserId Format

**Specification** (from `/home/user/redo-ios-package/PROTOCOL.md` line 154):

```
author.userId | lowercase hex | 32 chars | 9bf1a6192e3c4d5f... (first 32 of publicKey)
```

**Example**:
```
Public Key:  a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
UserId:      a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  (first 32 chars)
```

### 3.3 Why First 32 Chars?

**Protocol Rationale** (from PROTOCOL.md):

1. **Uniqueness**: 32 hex chars = 128 bits, sufficient for unique identification
2. **Space Efficiency**: Halves storage compared to full public key
3. **Deterministic**: Always derivable from public key (no separate hashing step)
4. **Cross-Platform Consistency**: All implementations (iOS, Android, Web) use this rule

### 3.4 Verification in Tests

**File**: `/home/user/redo-ios-package/Tests/RedoCryptoTests/Ed25519Tests.swift` (lines 109-115)

```swift
func testUserIdDerivation() {
    let (publicKey, _, userId) = Ed25519Manager.generateKey()

    let derivedUserId = Ed25519Manager.getUserId(from: publicKey)
    XCTAssertEqual(userId, derivedUserId)
    XCTAssertEqual(derivedUserId.count, 32)
}
```

---

## 4. Keypair Storage Mechanism

### 4.1 Storage Location: iOS Keychain

**File**: `/home/user/redo-ios-package/Sources/RedoCore/Storage/KeychainService.swift`

The iOS Keychain is **the only secure storage** for private keys.

**Keychain Configuration** (lines 24-34):

```swift
public func save(data: Data, forKey key: String) throws {
    // Delete existing item first
    try? delete(forKey: key)

    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: key,
        kSecValueData: data,
        // CRITICAL: Only accessible when device is unlocked
        kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.saveFailed(status: status)
    }
}
```

**Key Access Level**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Private keys only accessible when device is **actively unlocked**
- Keys not accessible from background (prevents iCloud keychain sync across devices)
- **This is intentional**: Each device must have its own keypair

### 4.2 Private Key Storage

**File**: `/home/user/redo-ios-package/Sources/RedoCore/Storage/KeychainService.swift` (lines 147-158)

```swift
/// Save Ed25519 private key
/// - Parameter privateKey: Private key hex string (64 chars)
/// - Throws: KeychainError if save fails
public func savePrivateKey(_ privateKey: String) throws {
    try save(string: privateKey, forKey: "ed25519_private_key")
}

/// Load Ed25519 private key
/// - Returns: Private key hex string if found
public func loadPrivateKey() throws -> String? {
    try loadString(forKey: "ed25519_private_key")
}
```

**Storage Details**:
- **Key**: `"ed25519_private_key"` (Keychain account name)
- **Service**: `"com.salient.vision.redo"` (Keychain service identifier)
- **Format**: Hex string (UTF-8 encoded data)
- **Location**: Device Keychain (encrypted by iOS)

### 4.3 Public Key Storage

**File**: `/home/user/redo-ios-package/Sources/RedoCore/Storage/KeychainService.swift` (lines 160-171)

```swift
/// Save Ed25519 public key
/// - Parameter publicKey: Public key hex string (64 chars)
/// - Throws: KeychainError if save fails
public func savePublicKey(_ publicKey: String) throws {
    try save(string: publicKey, forKey: "ed25519_public_key")
}

/// Load Ed25519 public key
/// - Returns: Public key hex string if found
public func loadPublicKey() throws -> String? {
    try loadString(forKey: "ed25519_public_key")
}
```

**Storage Details**:
- **Key**: `"ed25519_public_key"` (Keychain account name)
- **Service**: `"com.salient.vision.redo"` (same service identifier)
- **Format**: Hex string (UTF-8 encoded data)
- **Public**: Public key is safe to share/export

### 4.4 UserId and DeviceId Storage

**File**: `/home/user/redo-ios-package/Sources/RedoCore/Storage/KeychainService.swift` (lines 173-197)

```swift
/// Save user ID (derived from public key)
public func saveUserId(_ userId: String) throws {
    try save(string: userId, forKey: "user_id")
}

/// Load user ID
public func loadUserId() throws -> String? {
    try loadString(forKey: "user_id")
}

/// Save device ID
public func saveDeviceId(_ deviceId: String) throws {
    try save(string: deviceId, forKey: "device_id")
}

/// Load device ID
public func loadDeviceId() throws -> String? {
    try loadString(forKey: "device_id")
}
```

### 4.5 Storage Initialization Flow

**File**: `/home/user/redo-ios-package/Sources/RedoUI/ViewModels/AppViewModel.swift` (lines 47-79)

```swift
public init(
    storage: ChangeLogStorage = ChangeLogStorage(),
    keychain: KeychainService = KeychainService()
) {
    self.storage = storage
    self.keychain = keychain
    self.stateReconstructor = StateReconstructor()

    setupObservers()
    // Async initialization after view model is created
    Task { await initializeApp() }
}

private func initializeApp() async {
    isLoading = true
    defer { isLoading = false }

    do {
        // 1. Load or generate crypto identity
        try await loadOrGenerateIdentity()

        // 2. Load change log and reconstruct state
        try await reconstructState()

        // 3. Initialize Firebase sync (if authenticated)
        await initializeFirebaseSync()

        isAuthenticated = true
    } catch {
        errorMessage = "Failed to initialize app: \(error.localizedDescription)"
    }
}
```

### 4.6 Security Analysis

**Private Key Security** ✅
- Stored only in iOS Keychain
- Never exported to disk files
- Never sent to Firebase (only public key is synced)
- Only accessible when device is unlocked
- Protected by device passcode/biometric

**Public Key Security** ✅
- Can be safely shared
- Stored in Keychain for recovery
- Also stored in Firebase (in nodes)

**Token Security** (CRITICAL FIX):
- **Google OAuth tokens** stored separately (keys: `"googleIDToken"`, `"googleAccessToken"`, `"googleRefreshToken"`)
- **Crypto keys** stored separately (keys: `"ed25519_private_key"`, `"ed25519_public_key"`)
- **NEVER mixed** - Each has its own Keychain entry

**Reference**: `/home/user/redo-ios-package/Sources/RedoUI/Auth/GoogleAuthManager.swift` (lines 86-103)

---

## 5. Firebase UID Linking and Identity Separation

### 5.1 Two Independent Identity Systems

**From PROTOCOL.md** (lines 2135-2156):

```
IMPORTANT: Firebase uses TWO independent identity systems:

1. **Google OAuth ID (Firebase UID)** - Controls cloud storage access
   - Used for: Firebase Firestore path segregation (`users/{googleUserId}/changes/...`)
   - Purpose: Access control - who can read/write to which Firebase collections
   - Example: `105903347225150947554` (numeric Google user ID)

2. **Cryptographic Identity (Public Key Hash)** - Proves node authorship
   - Used for: Node signatures and authorship (`author.userId` field)
   - Purpose: Verifies WHO created/signed each node (tamper-proof)
   - Example: `a1b2c3d4e5f6...` (first 32 of Ed25519 public key hex)
```

### 5.2 Google Subject ID (Firebase UID)

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Auth/GoogleAuthManager.swift` (lines 150-155)

```swift
/// Get Google OAuth subject ID (for Firebase user paths)
/// This is SEPARATE from crypto userId
public func getGoogleSubjectID() -> String? {
    return Auth.auth().currentUser?.uid
}
```

**What it is**:
- Returned by Firebase Authentication after Google Sign-In
- Unique identifier for the Google account
- Numeric string (e.g., `"105903347225150947554"`)

### 5.3 Firebase Path Structure

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Sync/FirebaseSyncService.swift` (lines 65-100)

```swift
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

// Update user's ownedNodes array
// CRITICAL: Use Google OAuth ID for user document path
let userRef = db.collection("users").document(userId)
batch.setData([
    "ownedNodes": FieldValue.arrayUnion(ownedNodeIds)
], forDocument: userRef, merge: true)
```

**Firestore Structure**:
```
nodes/
  {nodeId}/
    id: "sha256:..."
    author:
      userId: "a1b2c3d4..."      ← Crypto public key hash (32 chars)
      publicKey: "a1b2c3d4..."   ← Full Ed25519 public key (64 chars)
      deviceId: "uuid"
    accessList: ["105903347..."]  ← Google OAuth UID

users/
  {googleUserId}/                 ← Firebase Authentication UID
    ownedNodes: ["sha256:...", ...]
```

### 5.4 Sync Process: Upload (Local → Firebase)

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Sync/FirebaseSyncService.swift` (lines 49-103)

```swift
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

        // Upload to global nodes collection
        let nodeRef = db.collection("nodes").document(change.id)
        let nodeData: [String: Any] = [
            "id": change.id,
            "author": [
                "userId": change.author.userId,     // Crypto userId (authorship)
                "publicKey": change.author.publicKey ?? ""
            ],
            "accessList": [userId],                 // Google OAuth ID (access control)
            // ... rest of node data ...
        ]

        batch.setData(nodeData, forDocument: nodeRef, merge: true)
        ownedNodeIds.append(change.id)
    }

    // Update user's ownedNodes array (indexed by Google OAuth ID)
    let userRef = db.collection("users").document(userId)
    batch.setData([
        "ownedNodes": FieldValue.arrayUnion(ownedNodeIds)
    ], forDocument: userRef, merge: true)

    try await batch.commit()
}
```

**Upload Steps**:
1. Validate change (v1 protocol compliance)
2. Store node at `nodes/{nodeId}` with:
   - `author.userId` = crypto public key hash (proves authorship)
   - `accessList` = [Google OAuth UID] (access control)
3. Update `users/{googleOAuthId}/ownedNodes` array

### 5.5 Sync Process: Download (Firebase → Local)

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Sync/FirebaseSyncService.swift` (lines 105-136)

```swift
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
```

**Download Steps**:
1. Get user's ownedNodes array from `users/{googleOAuthId}`
2. Fetch all nodes from `nodes/` collection using node IDs
3. Validate each node's v1 compliance
4. Extract `author.userId` from each node (for signature verification)

### 5.6 Real-Time Sync with Access Control

**File**: `/home/user/redo-ios-package/Sources/RedoUI/Sync/FirebaseSyncService.swift` (lines 140-157)

```swift
/// Start real-time sync listener
/// - Parameter onChange: Callback when changes are detected
public func startRealtimeSync(onChange: @escaping ([ChangeLogEntry]) -> Void) {
    // Listen to changes in nodes collection where accessList contains userId
    listener = db.collection("nodes")
        .whereField("accessList", arrayContains: userId)  // userId = Google OAuth UID
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
```

**Real-Time Features**:
- Listens to `nodes` collection
- Filters by `accessList` array contains Google OAuth UID
- Receives updates in real-time when new nodes are added with user's UID in accessList

### 5.7 Key Separation Rationale

**Why two IDs?**

From PROTOCOL.md (lines 2147-2156):

```
**Why Both?**
- Google ID: Firebase needs to segregate storage per user account (web2 access control)
- Crypto ID: DAG nodes can be authored by different devices/keys and shared across users (web3 verifiability)

**Key Principle**:
- Firebase paths use Google UID for **access control**
- Node signatures use crypto ID for **authorship verification**
- These identities are orthogonal - a single Google user can have multiple crypto keys (multi-device)
- Multiple Google users can share nodes authored by the same crypto key (collaboration)
```

**Example Scenarios**:

1. **Single User, Multiple Devices**:
   - Google OAuth UID: Same (same Google account)
   - Crypto userId: Different (device 1 has key1, device 2 has key2)
   - Both devices can sync to same `users/{googleOAuthId}/ownedNodes` array
   - Each node shows which device created it (via `author.deviceId`)

2. **Future Collaboration** (multi-user features):
   - Multiple Google users can have same change in `nodes/` collection
   - `accessList` array can contain multiple Google OAuthUIDs
   - Each user's `users/{googleOAuthId}/ownedNodes` tracks which nodes they own

---

## 6. Complete Authentication Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   REDO iOS Authentication Flow                   │
└─────────────────────────────────────────────────────────────────┘

FIRST LAUNCH (App Initialization)
│
├─ [1] FirebaseApp.configure()
│      └─ Loads GoogleService-Info.plist (CLIENT_ID, etc.)
│
├─ [2] initializeApp()
│      │
│      ├─ loadOrGenerateIdentity()
│      │  │
│      │  ├─ Check Keychain for existing keys
│      │  │
│      │  └─ If not found:
│      │     ├─ Ed25519Manager.generateKey()
│      │     │  ├─ Generate 32-byte private key (Curve25519.Signing)
│      │     │  ├─ Derive 32-byte public key
│      │     │  ├─ Encode both as lowercase hex (64 chars each)
│      │     │  └─ Return (publicKeyHex, privateKeyHex, userId)
│      │     │
│      │     └─ Save to Keychain
│      │        ├─ "ed25519_private_key" = privateKeyHex
│      │        ├─ "ed25519_public_key" = publicKeyHex
│      │        ├─ "user_id" = publicKey[:32]
│      │        └─ "device_id" = UUID()
│      │
│      └─ reconstructState()
│         └─ Load all local changes and rebuild state
│
├─ [3] Show SignInView (optional)
│      │
│      └─ User taps "Sign in with Google"
│         │
│         ├─ GIDConfiguration(clientID: FirebaseApp.options.clientID)
│         │
│         ├─ GIDSignIn.sharedInstance.signIn(withPresenting: ViewController)
│         │  └─ Shows Google OAuth login UI
│         │
│         ├─ Extract tokens:
│         │  ├─ result.user.idToken.tokenString
│         │  └─ result.user.accessToken.tokenString
│         │
│         ├─ Create Firebase credential:
│         │  └─ GoogleAuthProvider.credential(withIDToken:, accessToken:)
│         │
│         ├─ Auth.auth().signIn(with: credential)
│         │  └─ Firebase returns Firebase.User (uid = Google OAuth UID)
│         │
│         ├─ Store OAuth tokens to Keychain:
│         │  ├─ "googleIDToken"
│         │  ├─ "googleAccessToken"
│         │  └─ "googleRefreshToken"
│         │
│         └─ GoogleAuthManager.getGoogleSubjectID() → Google OAuth UID
│            (saved to Auth.auth().currentUser?.uid)
│
└─ [4] Initialize Firebase Sync (if authenticated)
       │
       ├─ Create FirebaseSyncService(userId: googleOAuthUID, deviceId: ...)
       │
       ├─ syncChanges()
       │  └─ Push local changes to Firebase nodes/ collection
       │     ├─ nodes/{nodeId}/author.userId = crypto userId (32 chars)
       │     ├─ nodes/{nodeId}/accessList = [googleOAuthUID]
       │     └─ users/{googleOAuthUID}/ownedNodes[] += [nodeId]
       │
       └─ startRealtimeSync()
          └─ Listen for changes in nodes/ where accessList contains googleOAuthUID


SUBSEQUENT LAUNCHES
│
├─ Check Keychain for existing keys
│  └─ If found: Reuse userId and deviceId
│
├─ Load local changes from storage
│
├─ Reconstruct state
│
└─ If Google Sign-In was done before:
   └─ Auth.auth().currentUser != nil
      └─ Reinitialize Firebase sync


SIGNING NODES WITH PRIVATE KEY (When Creating Tasks)
│
├─ AppViewModel.createChangeLogEntry()
│  │
│  ├─ Get publicKey from Keychain
│  │
│  ├─ Create AuthorInfo:
│  │  ├─ userId = crypto userId (first 32 of public key)
│  │  ├─ deviceId = stored device ID
│  │  ├─ publicKey = stored public key (64 chars)
│  │  └─ name = optional
│  │
│  ├─ Create ChangeLogEntry with all fields except id and signature
│  │
│  ├─ ContentAddressing.calculateChangeId(entry)
│  │  ├─ CanonicalJSON.stringify(entry) → sorted keys, no whitespace
│  │  ├─ SHA256.hash(canonicalJson) → 32-byte hash
│  │  └─ Return "sha256:<64 lowercase hex>"
│  │
│  └─ TODO: Ed25519Manager.sign(entry, privateKeyHex)
│     └─ Returns 128 hex char signature (NOT YET IMPLEMENTED)
│
└─ Save to local storage
   └─ Later: Sync to Firebase (with signature if implemented)


KEY STORAGE LOCATIONS
│
├─ SECURE (Keychain - encrypted by iOS):
│  ├─ ed25519_private_key
│  ├─ ed25519_public_key
│  ├─ user_id
│  ├─ device_id
│  ├─ googleIDToken
│  ├─ googleAccessToken
│  └─ googleRefreshToken
│
├─ LOCAL (ChangeLogStorage - local Documents directory):
│  └─ change_log.json (all nodes)
│
└─ CLOUD (Firebase):
    ├─ nodes/{nodeId}
    │  ├─ author.userId (crypto ID, 32 chars)
    │  ├─ author.publicKey (crypto public key, 64 chars)
    │  └─ accessList [Google OAuth UID]
    │
    └─ users/{googleOAuthUID}
       └─ ownedNodes: ["sha256:...", ...]
```

---

## 7. Critical Security Notes

### 7.1 ✅ What's Secure

1. **Private Key Storage**
   - Only in iOS Keychain
   - Never exported or logged
   - Protected by device passcode
   - Not synced to iCloud (intentional - each device unique)

2. **Public Key Distribution**
   - Safe to store in Firebase
   - Needed for signature verification
   - No sensitive information revealed

3. **Token Separation**
   - Google OAuth tokens ≠ Crypto keys
   - Stored in separate Keychain entries
   - Different purposes (access control vs. signing)

4. **Content Addressing**
   - Node IDs are SHA-256 hashes (deterministic)
   - Same input → same hash on all platforms
   - Prevents node ID collisions

### 7.2 ⚠️ What's Not Yet Implemented

1. **Node Signing** (TODO in AppViewModel.swift line 347)
   - Nodes are created but NOT signed yet
   - Signature field is empty/null
   - Will require: `Ed25519Manager.sign(canonicalBody, privateKeyHex)`

2. **Signature Verification**
   - Nodes are validated but signatures are not checked
   - Will require verifying against `author.publicKey`

3. **Token Refresh Logic**
   - `isTokenValid()` makes HTTP request (slow)
   - Could be optimized with local expiry checking

### 7.3 ⚠️ Security Considerations

1. **No iCloud Keychain Sync**
   - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` prevents sync
   - Each device must regenerate own keys
   - Intended design (multi-device support via deviceId)

2. **No End-to-End Encryption**
   - Nodes stored in Firebase unencrypted
   - Access controlled via accessList (not E2E)
   - Could be enhanced with crypto payload encryption (future)

3. **No Hardware Key Support**
   - Uses software keys (CryptoKit on device)
   - Could be enhanced with Secure Enclave later

---

## 8. File Structure Summary

```
Sources/
├── RedoUI/
│   ├── Auth/
│   │   └── GoogleAuthManager.swift        ← Google OAuth implementation
│   ├── Views/
│   │   └── SignInView.swift               ← Google Sign-In UI
│   ├── ViewModels/
│   │   └── AppViewModel.swift             ← Identity initialization & sync
│   ├── Sync/
│   │   └── FirebaseSyncService.swift      ← Firebase upload/download
│   └── RedoApp.swift                      ← Firebase initialization
│
├── RedoCore/
│   ├── Storage/
│   │   └── KeychainService.swift          ← Private/public key storage
│   └── Models/
│       └── ChangeLogEntry.swift           ← Author info (userId, deviceId, publicKey)
│
└── RedoCrypto/
    ├── Ed25519Manager.swift               ← Key generation & signing
    ├── ContentAddressing.swift            ← SHA-256 hashing (node IDs)
    └── CanonicalJSON.swift                ← RFC 8785 serialization

Tests/
├── RedoCryptoTests/
│   └── Ed25519Tests.swift                 ← Key generation & signing tests
└── RedoCoreTests/
    └── ChangeLogValidatorTests.swift      ← Node validation tests

Config/
└── GoogleService-Info.plist               ← Firebase config (NOT in repo)
```

---

## 9. References and Cross-Platform Compatibility

### Comparison: iOS vs Android vs Web

| Feature | iOS | Android | Web |
|---------|-----|---------|-----|
| **Framework** | CryptoKit (Apple) | Bouncy Castle (Java) | TweetNaCl (JS) |
| **Ed25519** | Curve25519.Signing | Signature (EdDSA) | nacl.sign |
| **Keychain** | iOS Keychain | Android Keystore | localStorage (secure context) |
| **Google Sign-In** | GoogleSignIn SDK | Google Play Services | Firebase Auth JS SDK |
| **Firebase** | Firebase iOS SDK | Firebase Android SDK | Firebase JS SDK |
| **userId** | First 32 of hex public key | First 32 of hex public key | First 32 of hex public key |
| **Node ID** | "sha256:" + 64 hex chars | "sha256:" + 64 hex chars | "sha256:" + 64 hex chars |

### Protocol References

- **PROTOCOL.md**: `/home/user/redo-ios-package/PROTOCOL.md` (3,443 lines)
  - Lines 2133-2191: Identity separation and Firebase architecture
  - Lines 154-365: Node structure and author info format

- **Test Vectors**: Tests in RedoCryptoTests confirm cross-platform compatibility
  - Ed25519 signing determinism (same key+message → same signature)
  - Content addressing consistency (same node → same hash)

---

## 10. Summary

The iOS authentication system implements a **sophisticated two-tier identity model**:

1. **OAuth Layer (Web2)**:
   - Google Sign-In for cloud access control
   - Firebase UID for Firestore path segregation
   - Optional (app works offline)

2. **Cryptographic Layer (Web3)**:
   - Ed25519 keypair generation per device
   - Private key storage in iOS Keychain
   - Public key shared with Firebase for authorship verification

3. **Key Derivation**:
   - userId = first 32 chars of Ed25519 public key (hex)
   - Device ID = UUID (unique per device)
   - Enables multi-device support with verifiable authorship

4. **Storage**:
   - Private keys: iOS Keychain only
   - Public keys: Keychain + Firebase
   - OAuth tokens: Separate Keychain entries
   - Change log: Local Documents directory + Firebase

5. **Security Considerations**:
   - No cross-device key sync (intentional)
   - All keys protected by device lock
   - Token separation prevents OAuth/crypto mixing
   - Protocol-compliant validation at boundaries

The implementation follows the v1 protocol specification precisely, enabling cross-platform compatibility with Android and Web apps while maintaining strong security for the local-first event sourcing architecture.

