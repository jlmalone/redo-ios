# iOS Authentication Flow Architecture Documentation

**Generated:** 2025-11-16
**System:** Redo iOS (iOS task management application)
**Note:** Android project not available on this system; iOS implementation follows the same cross-platform v1 protocol as Android

---

## Overview

The Redo iOS application implements a **local-first, event-sourcing architecture** with optional Firebase cloud sync. The authentication flow involves:
1. Google OAuth 2.0 sign-in (user account)
2. Ed25519 cryptographic keypair generation (local identity)
3. Separation of crypto identity (userId) from Google OAuth ID
4. Secure storage in iOS Keychain
5. Firebase Firestore for multi-device sync

---

## 1. Google Sign-In Implementation

### File: `/home/user/redo-ios-package/Sources/RedoUI/Auth/GoogleAuthManager.swift`

**Location:** Lines 1-68 (sign-in flow)

#### Sign-In Initialization
```swift
public func signInWithGoogle(presentingViewController: UIViewController) async throws {
    // Get the client ID from Firebase configuration
    guard let clientID = FirebaseApp.app()?.options.clientID else {
        throw AuthError.missingClientID
    }

    // Configure Google Sign-In
    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

    // Perform sign in
    let result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: presentingViewController
    )
```

**Flow:**
1. **Client ID retrieval**: Obtained from Firebase configuration (GoogleService-Info.plist)
2. **GIDConfiguration**: Set up with Firebase client ID
3. **User sign-in**: GIDSignIn.sharedInstance.signIn() presents system sheet
4. **Token retrieval**: Both ID token and access token captured from result

#### Scopes
- **Current Implementation**: Uses default Google Sign-In scopes
- **Scopes Obtained**:
  - ID Token (for Firebase authentication)
  - Access Token (for Google APIs like Calendar, Tasks)
  - Refresh Token (for token refresh)

#### Token Handling
```swift
guard let idToken = result.user.idToken?.tokenString else {
    throw AuthError.missingIDToken
}

let accessToken = result.user.accessToken.tokenString

// Create Firebase credential
let credential = GoogleAuthProvider.credential(
    withIDToken: idToken,
    accessToken: accessToken
)

// Sign in to Firebase
let authResult = try await Auth.auth().signIn(with: credential)
```

### Sign-In UI Trigger

**File:** `/home/user/redo-ios-package/Sources/RedoUI/Views/SignInView.swift` (Lines 124-152)

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

            try await authManager.signInWithGoogle(presentingViewController: rootViewController)

            // Reinitialize Firebase sync after successful sign-in
            await viewModel.reinitializeSync()

            HapticManager.shared.success()
            isSigningIn = false
        } catch {
            authManager.errorMessage = error.localizedDescription
            showError = true
            isSigningIn = false
            HapticManager.shared.error()
        }
    }
}
```

**Trigger:** Tapping "Sign in with Google" button on the SignInView.swift

---

## 2. Ed25519 Cryptographic Keypair Generation

### File: `/home/user/redo-ios-package/Sources/RedoCrypto/Ed25519Manager.swift`

**Library:** Apple CryptoKit (Curve25519.Signing)

#### Key Generation
```swift
public static func generateKey() -> (publicKey: String, privateKey: String, userId: String) {
    let privateKey = Curve25519.Signing.PrivateKey()
    let publicKeyData = privateKey.publicKey.rawRepresentation
    let privateKeyData = privateKey.rawRepresentation

    // CRITICAL: Lowercase hexadecimal encoding (v1 protocol requirement)
    let publicKeyHex = publicKeyData.hexEncodedString(uppercase: false)
    let privateKeyHex = privateKeyData.hexEncodedString(uppercase: false)

    // User ID = first 32 chars of public key (per PROTOCOL.md)
    let userId = String(publicKeyHex.prefix(32))

    return (publicKeyHex, privateKeyHex, userId)
}
```

**Key Specifications:**
- **Algorithm**: Ed25519 (Curve25519.Signing)
- **Public Key Size**: 64 lowercase hex characters (32 bytes raw)
- **Private Key Size**: 64 lowercase hex characters (32 bytes raw)
- **Encoding**: Lowercase hexadecimal (v1 protocol requirement)
- **Hardware Acceleration**: Apple CryptoKit uses hardware acceleration when available

#### When/Where Keys Are Created

**File:** `/home/user/redo-ios-package/Sources/RedoUI/ViewModels/AppViewModel.swift` (Lines 83-105)

```swift
private func loadOrGenerateIdentity() async throws {
    // Check if we have existing keys in Keychain
    if let existingUserId = try? keychain.loadUserId(),
       let existingDeviceId = try? keychain.loadDeviceId() {
        userId = existingUserId
        deviceId = existingDeviceId
    } else {
        // Generate new Ed25519 keypair
        let (publicKey, privateKey, newUserId) = Ed25519Manager.generateKey()

        // Save to Keychain
        try keychain.savePublicKey(publicKey)
        try keychain.savePrivateKey(privateKey)
        try keychain.saveUserId(newUserId)

        // Generate device ID (UUID)
        let newDeviceId = UUID().uuidString
        try keychain.saveDeviceId(newDeviceId)

        userId = newUserId
        deviceId = newDeviceId
    }
}
```

**Timing:**
- **App Launch**: AppViewModel.initializeApp() calls loadOrGenerateIdentity()
- **Automatic Generation**: First launch only (keys persist in Keychain after that)
- **Per-Device**: One keypair generated per iOS device

---

## 3. UserId Derivation

### Derivation Logic

**File:** `/home/user/redo-ios-package/Sources/RedoCrypto/Ed25519Manager.swift` (Lines 101-108)

```swift
public static func getUserId(from publicKeyHex: String) -> String {
    String(publicKeyHex.prefix(32))
}

public static func isValidPublicKey(_ publicKeyHex: String) -> Bool {
    publicKeyHex.count == 64 && publicKeyHex.allSatisfy { $0.isHexDigit && $0.isLowercase || $0.isNumber }
}
```

**Definition:**
- **UserId** = First 32 characters of Ed25519 public key
- **Example**: 
  - Full public key: `9bf1a6192e3c4d5f8c7a2b1d9e0f3a5c` (64 chars)
  - Derived UserId: `9bf1a6192e3c4d5f8c7a2b1d` (32 chars, first half)

**Verification:**
Test case from `/home/user/redo-ios-package/Tests/RedoCryptoTests/Ed25519Tests.swift` (Lines 109-115):

```swift
func testUserIdDerivation() {
    let (publicKey, _, userId) = Ed25519Manager.generateKey()

    let derivedUserId = Ed25519Manager.getUserId(from: publicKey)
    XCTAssertEqual(userId, derivedUserId)
    XCTAssertEqual(derivedUserId.count, 32)
}
```

**Format Validation:**
```swift
// Must be exactly 32 lowercase hex characters
XCTAssertEqual(userId.count, 32)
XCTAssertTrue(userId.allSatisfy { $0.isHexDigit && $0.isLowercase })
```

### UserId Usage
- **ChangeLogEntry.author.userId**: Field identifying the device that created the event
- **Firebase Path Component**: Used in accessList for Firebase access control
- **Separate from Google OAuth ID**: Crypto identity ≠ Google authentication identity

---

## 4. Keypair Storage Mechanism

### File: `/home/user/redo-ios-package/Sources/RedoCore/Storage/KeychainService.swift`

**Storage Type:** iOS Keychain (secure enclave when available)

#### Storage Configuration
```swift
public init(service: String = "com.salient.vision.redo") {
    self.service = service
}

private let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: service,
    kSecAttrAccount: key,
    kSecValueData: data,
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
]
```

**Security Settings:**
- **Service Identifier**: "com.salient.vision.redo"
- **Accessibility**: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
  - Keys only accessible when device is unlocked
  - Encrypted at rest in secure enclave
  - Not accessible from passcode-only unlock

#### Storage Operations

**Save Private Key**
```swift
public func savePrivateKey(_ privateKey: String) throws {
    try save(string: privateKey, forKey: "ed25519_private_key")
}

public func save(string: String, forKey key: String) throws {
    guard let data = string.data(using: .utf8) else {
        throw KeychainError.invalidData
    }
    try save(data: data, forKey: key)
}
```

**Load Private Key**
```swift
public func loadPrivateKey() throws -> String? {
    try loadString(forKey: "ed25519_private_key")
}

public func load(forKey key: String) throws -> Data? {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: key,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecItemNotFound {
        return nil
    }

    guard status == errSecSuccess else {
        throw KeychainError.loadFailed(status: status)
    }

    guard let data = result as? Data else {
        throw KeychainError.invalidData
    }

    return data
}
```

**Save Public Key**
```swift
public func savePublicKey(_ publicKey: String) throws {
    try save(string: publicKey, forKey: "ed25519_public_key")
}
```

**Save UserId**
```swift
public func saveUserId(_ userId: String) throws {
    try save(string: userId, forKey: "user_id")
}
```

**Save Device ID**
```swift
public func saveDeviceId(_ deviceId: String) throws {
    try save(string: deviceId, forKey: "device_id")
}
```

#### Keychain Entry Summary

| Key Name | Content | Size | Format | Accessibility |
|----------|---------|------|--------|----------------|
| `ed25519_private_key` | Private key | 64 chars | lowercase hex | WhenUnlockedThisDeviceOnly |
| `ed25519_public_key` | Public key | 64 chars | lowercase hex | WhenUnlockedThisDeviceOnly |
| `user_id` | Derived UserId | 32 chars | lowercase hex | WhenUnlockedThisDeviceOnly |
| `device_id` | Device UUID | 36 chars | UUID string | WhenUnlockedThisDeviceOnly |
| `googleIDToken` | Google ID token | variable | JWT | WhenUnlockedThisDeviceOnly |
| `googleAccessToken` | Google access token | variable | JWT | WhenUnlockedThisDeviceOnly |
| `googleRefreshToken` | Google refresh token | variable | JWT | WhenUnlockedThisDeviceOnly |

#### Security Features
- **Hardware Encryption**: Uses secure enclave when available
- **Device Lock Integration**: Keys inaccessible when device is locked
- **Per-Device Isolation**: Keys stored locally, not synced via iCloud
- **No UserDefaults**: Never stores crypto keys in UserDefaults/plist
- **Token Separation**: Google OAuth tokens stored separately from crypto keys

---

## 5. Firebase UID Linking & Multi-Device Sync

### Critical Design: Two Separate User IDs

**Key Concept from PLANNING.md (Section 3.2):**
```
Crypto userId: First 32 chars of Ed25519 public key (for node signing/authorship)
Google OAuth ID: Subject ID from JWT (for Firebase storage paths)
These are SEPARATE and serve different purposes
```

### Firebase Collections Architecture

**File:** `/home/user/redo-ios-package/Sources/RedoUI/Sync/FirebaseSyncService.swift`

#### Collection Structure
```
firestore
├── nodes/
│   ├── {sha256:nodeId1}/
│   │   ├── id: "sha256:..."
│   │   ├── version: 1
│   │   ├── parents: ["sha256:..."]
│   │   ├── timestamp: { lamport: 5, wall: "2025-11-09T..." }
│   │   ├── author: {
│   │   │   ├── userId: "9bf1a6192e3c4d5f..." (crypto userId, first 32 of pub key)
│   │   │   ├── deviceId: "..."
│   │   │   ├── publicKey: "9bf1a6192e3c4d5f8c7a2b1d9e0f3a5c"
│   │   │   └── name: null
│   │   ├── action: "CREATE"
│   │   ├── taskId: "uuid"
│   │   ├── data: { fields: {...} }
│   │   ├── signature: "..."
│   │   ├── accessList: ["google-oauth-id-123..."] (Google OAuth ID)
│   │   └── createdAt: Timestamp
│   │
│   └── {sha256:nodeId2}/
│       └── ... (similar structure)
│
└── users/
    ├── {googleOAuthId1}/  (NOT crypto userId, NOT Firebase UID)
    │   ├── ownedNodes: ["sha256:nodeId1", "sha256:nodeId2", ...]
    │   └── createdAt: Timestamp
    │
    └── {googleOAuthId2}/
        └── ownedNodes: [...]
```

#### Push Changes to Firebase

**File:** Lines 51-103

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
    }

    // Update user's ownedNodes array
    // CRITICAL: Use Google OAuth ID for user document path
    let userRef = db.collection("users").document(userId)
    batch.setData([
        "ownedNodes": FieldValue.arrayUnion(ownedNodeIds)
    ], forDocument: userRef, merge: true)

    try await batch.commit()
}
```

**Key Points:**
- **Node document ID**: SHA-256 hash of canonical JSON (content-addressed)
- **author.userId**: Crypto userId (first 32 chars of public key)
- **author.publicKey**: Full Ed25519 public key (64 hex chars)
- **accessList**: Array of Google OAuth IDs (controls who can access)
- **users/{googleOAuthId}/ownedNodes**: Array of node IDs owned by user

#### Pull Changes from Firebase

**File:** Lines 107-136

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

**Sync Flow:**
1. Query users/{googleOAuthId} to get ownedNodes array
2. Fetch all node documents from nodes/ collection using ownedNodes IDs
3. Batch queries in chunks of 10 (Firebase 'in' query limit)
4. Parse and return ChangeLogEntry objects

#### Linking Google OAuth to Crypto Identity

**File:** `/home/user/redo-ios-package/Sources/RedoUI/ViewModels/AppViewModel.swift` (Lines 354-362)

```swift
private func initializeFirebaseSync() async {
    // Check if user is authenticated with Google OAuth
    guard let googleSubjectID = GoogleAuthManager.shared.getGoogleSubjectID() else {
        print("ℹ️ No Google authentication, running in offline mode")
        return
    }

    // Initialize Firebase sync service with Google OAuth ID
    firebaseSync = FirebaseSyncService(userId: googleSubjectID, deviceId: deviceId)

    // Perform initial sync
    await syncChanges()

    // Start real-time listener
    firebaseSync?.startRealtimeSync { [weak self] remoteChanges in
        // Handle incoming changes from other devices
    }
}
```

**Linking Process:**
1. User signs in with Google OAuth (GoogleAuthManager)
2. Firebase authentication established with Google credential
3. Google OAuth subject ID retrieved: `Auth.auth().currentUser?.uid`
4. FirebaseSyncService initialized with **Google OAuth ID** (NOT crypto userId)
5. Crypto keys were already generated and stored in Keychain during app init
6. Both identities active simultaneously:
   - **Crypto identity** (userId): Used in change log entries for authorship
   - **Google OAuth ID**: Used for Firebase paths and access control

### Multi-Device Handling

**Separate Crypto Keys Per Device:**
```swift
// Each device generates its own Ed25519 keypair
let (publicKey, privateKey, userId) = Ed25519Manager.generateKey()
let deviceId = UUID().uuidString
```

**Shared Google Account:**
- User signs into same Google account on multiple devices
- Same Google OAuth ID across devices
- Different crypto userIds per device (first 32 chars of different public keys)

**ChangeLogEntry Deduplication:**
```swift
let localIds = Set(localChanges.map { $0.id })
let missingChanges = remoteChanges.filter { !localIds.contains($0.id) }
```
- All changes are content-addressed (SHA-256 hash of canonical JSON)
- Same change (same author + action + timestamp) produces same ID across devices
- Duplicate detection prevents double-processing

---

## 6. Change Log Entry Structure with Crypto Identity

### File: `/home/user/redo-ios-package/Sources/RedoCore/Models/ChangeLogEntry.swift`

```swift
public struct ChangeLogEntry: Identifiable, Codable, Equatable {
    // Content-addressed ID (SHA-256 hash)
    public let id: String                      // "sha256:<64 lowercase hex>"
    
    // Protocol version
    public let version: Int                    // MUST be 1
    
    // DAG structure
    public let parents: [String]               // Parent change IDs
    
    // Hybrid logical clock
    public let timestamp: LogicalTimestamp     // Lamport + wall clock
    
    // Cryptographic authorship
    public let author: AuthorInfo              // UserId, DeviceId, PublicKey
    
    // State change
    public let action: ChangeAction            // CREATE, UPDATE, COMPLETE_TODO, etc.
    public let taskId: String?
    public let data: ChangeData
    
    // Digital signature
    public let signature: String?              // Ed25519 signature (128 hex chars)
}

public struct AuthorInfo: Codable, Equatable {
    public let userId: String                  // First 32 chars of Ed25519 public key
    public let deviceId: String
    public let name: String?
    public let publicKey: String?              // Ed25519 public key (64 hex chars)
}
```

### Signing and Verification

**Current Status:** Lines 346-348 in AppViewModel

```swift
// Sign entry (optional for now)
// TODO: Implement signing
```

**Expected Implementation** (from PROTOCOL.md):
```swift
let canonicalJson = try CanonicalJSON.stringify(entry)
let signature = try Ed25519Manager.sign(string: canonicalJson, privateKeyHex: privateKey)
```

---

## 7. Differences Between iOS and Cross-Platform Design

### iOS-Specific Considerations

**From CLAUDE.md (Section 3.2):**
> Android had sync path issues (Nov 2025):
> - ❌ Used Firebase UID for storage path
> - ❌ Web used Google OAuth subject ID
> - ❌ Different paths = no sync between platforms
> - ✅ Solution: iOS uses Google OAuth ID for Firebase paths (not Firebase UID)

**iOS Implementation:**
- ✅ Uses Google OAuth ID (subject ID) for Firebase paths
- ✅ Separate crypto identity from auth identity from day one
- ✅ Both identities properly documented and tested
- ✅ Lowercase hex encoding enforced at cryptography layer

---

## 8. Test Coverage

### Crypto Tests

**File:** `/home/user/redo-ios-package/Tests/RedoCryptoTests/Ed25519Tests.swift`

#### Test Cases
1. **Key Generation** (lines 8-22)
   - Public key: 64 lowercase hex chars
   - Private key: 64 lowercase hex chars
   - UserId: 32 chars (first half of public key)

2. **Multiple Key Generations** (lines 24-32)
   - Each key pair is unique

3. **Signing and Verification** (lines 36-54)
   - Sign string: produces 128 lowercase hex char signature
   - Verify: matches original public key

4. **Signature Validation** (lines 56-88)
   - Rejects tampered messages
   - Rejects wrong public key

5. **Cross-Platform Compatibility** (lines 92-105)
   - Deterministic signing (same output for same input)

6. **User ID Derivation** (lines 109-115)
   - UserId = first 32 chars of public key
   - UserId count = 32

7. **Format Validation** (lines 119-147)
   - Public key must be 64 lowercase hex
   - Rejects uppercase hex
   - Rejects non-hex characters
   - Signature must be 128 lowercase hex

---

## 9. Summary Table: Authentication Flow

| Component | Mechanism | Storage | Cross-Platform |
|-----------|-----------|---------|-----------------|
| **Google OAuth** | GIDSignIn, Firebase Auth | Keychain (GoogleAuthManager) | Standard Google OAuth 2.0 |
| **Crypto Identity** | Ed25519 keypair | Keychain (KeychainService) | v1 protocol compatible |
| **UserId** | First 32 chars of public key | Keychain | Deterministic derivation |
| **DeviceId** | UUID | Keychain | Per-device unique |
| **Firebase Path** | Google OAuth ID (subject ID) | N/A | Matches web/Android |
| **Change Authorship** | Crypto userId in ChangeLogEntry | Firestore (nodes/{id}/author/userId) | Ed25519 signature verification |
| **Access Control** | accessList array with OAuth ID | Firestore (nodes/{id}/accessList) | Google OAuth ID |

---

## 10. Error Handling

### GoogleAuthManager Errors
```swift
public enum AuthError: LocalizedError {
    case missingClientID         // Firebase config not found
    case missingIDToken          // Google Sign-In failed
    case notSignedIn             // User not authenticated
    case tokenRefreshFailed      // Token refresh error
}
```

### Keychain Errors
```swift
public enum KeychainError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case invalidData
}
```

### Crypto Errors
```swift
public enum CryptoError: Error, LocalizedError {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidSignature
    case invalidData
    case signingFailed
    case verificationFailed
}
```

---

## References

### Source Files
1. **GoogleAuthManager**: `/home/user/redo-ios-package/Sources/RedoUI/Auth/GoogleAuthManager.swift`
2. **Ed25519Manager**: `/home/user/redo-ios-package/Sources/RedoCrypto/Ed25519Manager.swift`
3. **KeychainService**: `/home/user/redo-ios-package/Sources/RedoCore/Storage/KeychainService.swift`
4. **FirebaseSyncService**: `/home/user/redo-ios-package/Sources/RedoUI/Sync/FirebaseSyncService.swift`
5. **AppViewModel**: `/home/user/redo-ios-package/Sources/RedoUI/ViewModels/AppViewModel.swift`
6. **SignInView**: `/home/user/redo-ios-package/Sources/RedoUI/Views/SignInView.swift`
7. **ChangeLogEntry**: `/home/user/redo-ios-package/Sources/RedoCore/Models/ChangeLogEntry.swift`
8. **Ed25519Tests**: `/home/user/redo-ios-package/Tests/RedoCryptoTests/Ed25519Tests.swift`

### Documentation Files
- PROTOCOL.md - Cross-platform v1 protocol specification
- PLANNING.md - Architecture decisions (Section 3.2 discusses Android lessons)
- CLAUDE.md - AI agent instructions for this project

---

## Next Steps for Developers

### For App Store Submission
1. Verify Firebase Security Rules enforce accessList checks
2. Test multi-device sync with same Google account
3. Verify signature verification (currently TODO)
4. Test key rotation and device removal flow

### For Android/Web Interop Testing
1. Create task on iOS, verify on Android/Web with same Google account
2. Create task on Web/Android, verify syncs to iOS
3. Test conflict resolution (Lamport clock ordering)
4. Test offline mode (tasks created while offline, synced when online)

### Missing Implementations
1. Signature verification in ChangeLogEntry (currently allows nil signature)
2. Public key rotation for compromised keys
3. Per-user Firebase security rules validation
4. Cross-device key revocation flow

