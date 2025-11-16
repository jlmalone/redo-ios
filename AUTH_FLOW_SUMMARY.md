# iOS Authentication Flow - Quick Summary

## Key Finding: Two Separate Identity Systems

The Redo iOS app implements a critical architectural pattern learned from Android bugs:
- **Crypto Identity (userId)**: Ed25519 keypair, first 32 chars = crypto userId
- **Google OAuth ID**: Subject ID from JWT, used for Firebase paths
- These are SEPARATE and intentionally different

## 1. Google Sign-In Entry Point

**File**: `Sources/RedoUI/Auth/GoogleAuthManager.swift`
**Trigger**: SignInView.swift, button tap -> `signInWithGoogle()`
**Scopes**: Default Google Sign-In (ID token, Access token, Refresh token)

```swift
// Gets Firebase client ID from GoogleService-Info.plist
let config = GIDConfiguration(clientID: clientID)
let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
// Result contains idToken, accessToken, refreshToken
```

## 2. Ed25519 Keypair Generation

**File**: `Sources/RedoCrypto/Ed25519Manager.swift`
**Library**: Apple CryptoKit (Curve25519.Signing)
**When**: App launch (AppViewModel.initializeApp -> loadOrGenerateIdentity)
**Per-Device**: ONE keypair per iOS device

```
Algorithm: Ed25519
Public Key: 64 lowercase hex chars (32 bytes raw)
Private Key: 64 lowercase hex chars (32 bytes raw)
UserId: First 32 chars of public key (ALWAYS lowercase hex)
```

## 3. UserId Derivation Formula

**Simple calculation**:
```
publicKey = "9bf1a6192e3c4d5f8c7a2b1d9e0f3a5c6b5a4f3" (example, 64 chars)
userId = publicKey.prefix(32) = "9bf1a6192e3c4d5f8c7a2b1d" (32 chars)
```

**Test verification** (`Ed25519Tests.swift` line 109-115):
- userId count = exactly 32
- userId = first 32 chars of public key
- All lowercase hex

## 4. Keypair Storage - iOS Keychain

**File**: `Sources/RedoCore/Storage/KeychainService.swift`
**Service ID**: "com.salient.vision.redo"
**Accessibility**: kSecAttrAccessibleWhenUnlockedThisDeviceOnly

| Key | Content | Security |
|-----|---------|----------|
| `ed25519_private_key` | Private key (64 hex) | Hardware encrypted, device-lock protected |
| `ed25519_public_key` | Public key (64 hex) | Hardware encrypted, device-lock protected |
| `user_id` | Crypto userId (32 hex) | Hardware encrypted, device-lock protected |
| `device_id` | UUID string | Hardware encrypted, device-lock protected |
| `googleIDToken` | JWT token | SEPARATE from crypto keys |
| `googleAccessToken` | JWT token | SEPARATE from crypto keys |
| `googleRefreshToken` | JWT token | SEPARATE from crypto keys |

## 5. Firebase UID Linking

**Firebase Collections**:
```
nodes/{sha256:changeId}
  author.userId: "9bf1a..." (CRYPTO userId, 32 chars)
  author.publicKey: "9bf1a..." (FULL public key, 64 chars)
  accessList: ["google-oauth-123..."] (GOOGLE OAuth ID)
  
users/{googleOAuthId}  (NOT crypto userId!)
  ownedNodes: ["sha256:changeId1", "sha256:changeId2"]
```

**Linking Code** (`AppViewModel.swift` line 354-362):
```swift
let googleSubjectID = GoogleAuthManager.shared.getGoogleSubjectID()  // OAuth ID
firebaseSync = FirebaseSyncService(userId: googleSubjectID, deviceId: deviceId)
```

**Three IDs Active Simultaneously**:
1. **Google OAuth ID** (subject ID): For Firebase user paths
2. **Crypto userId**: For ChangeLogEntry authorship (first 32 of public key)
3. **Device ID**: UUID for per-device tracking

## 6. Multi-Device Sync Architecture

**Per Device**:
- New Ed25519 keypair generated (different crypto userId on each device)
- Same Google OAuth ID (user signs into same Google account)
- Different device ID (unique UUID)

**Content Addressing**:
- Change ID = SHA-256(canonical JSON)
- Same change = same ID across devices
- Deduplication prevents double-processing

## Critical Implementation Details

### Google Token Handling
```swift
// SEPARATE Keychain entries for OAuth tokens
try keychain.save(string: idToken, forKey: "googleIDToken")
try keychain.save(string: accessToken, forKey: "googleAccessToken")
try keychain.save(string: refreshToken, forKey: "googleRefreshToken")
// NOT mixed with crypto keys!
```

### Crypto Validation
```swift
// ENFORCED: Lowercase hex only
let publicKeyHex = publicKeyData.hexEncodedString(uppercase: false)
let isValid = publicKeyHex.count == 64 && 
              publicKeyHex.allSatisfy { $0.isHexDigit && $0.isLowercase }
```

### Keychain Queries
```swift
let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.salient.vision.redo",
    kSecAttrAccount: key,
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
]
```

## Test Coverage

**Ed25519Tests.swift** covers:
- Key generation format (64 hex chars public, private)
- UserId derivation (first 32 chars)
- Deterministic signing (same output for same input)
- Signature verification (correct/tampered messages)
- Format validation (rejects uppercase, wrong length, non-hex)

## Android Lessons Applied

From PLANNING.md Section 3.2:
- ✅ iOS uses Google OAuth ID for Firebase paths (learned from Android bug)
- ✅ Separate crypto identity from OAuth identity
- ✅ Both identities documented and tested
- ✅ Lowercase hex encoding enforced

## TODO Items in Code

1. **AppViewModel.swift line 347**: Signature signing not implemented
   ```swift
   // Sign entry (optional for now)
   // TODO: Implement signing
   ```

2. Missing: Public key rotation flow
3. Missing: Cross-device key revocation
4. Missing: Firebase security rules validation

## File Locations (Quick Reference)

| Component | File |
|-----------|------|
| Google OAuth | `Sources/RedoUI/Auth/GoogleAuthManager.swift` |
| Ed25519 Keys | `Sources/RedoCrypto/Ed25519Manager.swift` |
| Keychain Storage | `Sources/RedoCore/Storage/KeychainService.swift` |
| Firebase Sync | `Sources/RedoUI/Sync/FirebaseSyncService.swift` |
| App Init | `Sources/RedoUI/ViewModels/AppViewModel.swift` |
| Sign-In UI | `Sources/RedoUI/Views/SignInView.swift` |
| Change Log Model | `Sources/RedoCore/Models/ChangeLogEntry.swift` |
| Crypto Tests | `Tests/RedoCryptoTests/Ed25519Tests.swift` |

## Documentation Files

- **AUTH_FLOW_ANALYSIS.md** (full 500+ line detailed analysis)
- **PROTOCOL.md** (v1 protocol specification)
- **PLANNING.md** (architecture decisions, Android lessons)
- **CLAUDE.md** (AI agent instructions)

