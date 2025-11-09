# Redo iOS - Setup Guide

**Last Updated**: 2025-11-09

---

## Prerequisites

### Required
- macOS 14.0+ (Sonoma or later)
- Xcode 15.0+
- iOS 17.0+ device or simulator
- Swift 5.9+

### Optional (for Firebase sync)
- Firebase account (free tier)
- Google Cloud project
- CocoaPods or Swift Package Manager

---

## Quick Start (Local-Only Mode)

```bash
# 1. Clone or navigate to project
cd ~/ios_code/redo-ios

# 2. Build project
swift build

# 3. Run tests
swift test

# 4. Open in Xcode
open Package.swift
```

**That's it!** The app will run in local-only mode without Firebase.

---

## Detailed Setup

### 1. Project Structure

```
redo-ios/
├── Package.swift              # Swift Package Manager manifest
├── Sources/
│   ├── RedoCore/             # Business logic
│   ├── RedoCrypto/           # Cryptography
│   └── RedoUI/               # SwiftUI interface
├── Tests/                    # Unit tests
├── Docs/                     # Documentation
├── PLANNING.md               # Architecture document
├── CLAUDE.md                 # AI agent context
└── SETUP.md                  # This file
```

### 2. Dependencies

All dependencies managed via Swift Package Manager in `Package.swift`:

```swift
dependencies: [
    // Firebase (for cloud sync - optional)
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0"),

    // CryptoKit (for Ed25519 - included in iOS)
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
]
```

**First Build**:
```bash
swift package resolve  # Download dependencies
swift build           # Compile all modules
```

### 3. Xcode Setup

1. **Open Package**:
   ```bash
   cd ~/ios_code/redo-ios
   open Package.swift  # Opens in Xcode
   ```

2. **Select Scheme**:
   - Choose "RedoApp" scheme (top left)
   - Select iOS simulator or device

3. **Build & Run**:
   - Press Cmd+R or click Play button
   - App launches in local-only mode

### 4. Firebase Setup (Optional)

If you want cloud sync:

#### A. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create new project: "redo-ios" (or use existing "redo-app-prod")
3. Add iOS app with bundle ID: `vision.salient.redo.ios`

#### B. Download Config File

1. Download `GoogleService-Info.plist` from Firebase
2. Add to Xcode project:
   - Drag file into Xcode navigator
   - Target: RedoApp
   - Copy if needed: ✅

#### C. Enable Services

In Firebase Console:
1. **Authentication** → Sign-in method → Google (Enable)
2. **Firestore** → Create database → Production mode
3. **Security Rules**:
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // Global nodes collection
       match /nodes/{nodeId} {
         allow read: if request.auth != null &&
                     request.auth.uid in resource.data.accessList;
         allow write: if request.auth != null;
       }

       // User metadata
       match /users/{userId} {
         allow read, write: if request.auth != null &&
                             request.auth.uid == userId;
       }
     }
   }
   ```

#### D. Configure OAuth

1. **Google Cloud Console**:
   - Enable Google+ API
   - Create OAuth 2.0 client ID (iOS type)
   - Copy client ID

2. **Add to Xcode**:
   - Edit `Info.plist`
   - Add URL scheme: `com.googleusercontent.apps.YOUR_CLIENT_ID`

### 5. Running Tests

```bash
# All tests
swift test

# Specific module
swift test --filter RedoCoreTests

# Specific test
swift test --filter testValidV1Node

# With coverage
swift test --enable-code-coverage
```

**In Xcode**:
- Cmd+U to run all tests
- Cmd+6 to view Test Navigator
- Click diamond next to test to run individually

### 6. Building for Device

1. **Select Device**:
   - Connect iPhone/iPad via USB
   - Select from device menu (top left)

2. **Code Signing**:
   - Project Settings → Signing & Capabilities
   - Team: Select your Apple Developer account
   - Automatically manage signing: ✅

3. **Build & Run**:
   - Cmd+R or click Play
   - App installs on device

---

## Development Workflow

### Local Development

```bash
# Edit code in Xcode or favorite editor
# ...

# Build and test
swift build && swift test

# Run in simulator
open Package.swift  # Then Cmd+R in Xcode
```

### Adding New Features

1. **Add Model/Service**:
   ```bash
   # Create new file
   touch Sources/RedoCore/Services/NewService.swift

   # Edit and implement
   # Run tests
   swift test
   ```

2. **Add UI Component**:
   ```bash
   # Create view
   touch Sources/RedoUI/Views/NewView.swift

   # Add to navigation
   # Test in simulator
   ```

3. **Add Tests**:
   ```bash
   # Create test file
   touch Tests/RedoCoreTests/NewServiceTests.swift

   # Implement tests
   swift test --filter NewServiceTests
   ```

### Debugging

**Print Debugging**:
```swift
print("📍 Current state:", tasks.count)
print("🔐 User ID:", userId)
print("🔄 Syncing:", syncStatus)
```

**Breakpoints**:
- Click line number in Xcode gutter
- Cmd+R to run with debugger
- Inspect variables in bottom panel

**View Hierarchy**:
- Cmd+Shift+D while running
- Click "Debug View Hierarchy"
- Inspect SwiftUI view tree

---

## Troubleshooting

### Build Errors

**"No such module 'RedoCore'"**:
```bash
# Clean and rebuild
swift package clean
swift build
```

**"Failed to resolve dependencies"**:
```bash
# Reset package cache
rm -rf .build
swift package resolve
swift build
```

### Runtime Issues

**App crashes on launch**:
- Check console logs in Xcode (Cmd+Shift+Y)
- Verify Firebase config if using cloud sync
- Check file permissions for Documents directory

**State not persisting**:
- Check `redo_changes.json` exists:
  ```bash
  # Simulator
  ~/Library/Developer/CoreSimulator/Devices/[UUID]/data/Containers/Data/Application/[UUID]/Documents/

  # Device (via Xcode)
  Window → Devices and Simulators → Select device → Download container
  ```

**Sync not working**:
- Verify Firebase authentication
- Check internet connection
- Review Firestore security rules
- Enable debug logging:
  ```swift
  FirebaseConfiguration.shared.setLoggerLevel(.debug)
  ```

### Test Failures

**Hash mismatch errors**:
- Verify canonical JSON implementation
- Check that keys are sorted
- Ensure no whitespace in output

**Signature verification fails**:
- Verify Ed25519 key format (64 lowercase hex)
- Check that signing uses same message encoding
- Test with known test vectors from web/Android

---

## Performance Optimization

### Profiling

1. **Time Profiler**:
   - Xcode → Product → Profile (Cmd+I)
   - Select "Time Profiler"
   - Record and analyze

2. **Allocations**:
   - Profile → Allocations
   - Check for memory leaks
   - Verify task list doesn't retain old data

3. **Network**:
   - Profile → Network
   - Monitor Firebase sync traffic
   - Verify batching works (10 items per query)

### Optimization Tips

- Use `LazyVStack` for task lists (done)
- Cache Lamport clock in memory (done)
- Batch Firebase operations (done)
- Paginate change log if > 1000 items (TODO)

---

## Deployment

### TestFlight (Beta)

1. **Archive Build**:
   - Xcode → Product → Archive
   - Wait for build to complete

2. **Upload to App Store Connect**:
   - Window → Organizer
   - Select archive → Distribute App
   - TestFlight → Upload

3. **Add Testers**:
   - App Store Connect → TestFlight
   - Add internal/external testers
   - They receive email with install link

### App Store (Production)

1. **Prepare**:
   - Screenshots (6.7", 6.5", 5.5" displays)
   - App icon (1024x1024)
   - Description and keywords
   - Privacy policy URL

2. **Submit**:
   - App Store Connect → My Apps → + Version
   - Fill metadata
   - Submit for review

3. **Review**:
   - Typically 1-3 days
   - Check status in App Store Connect
   - Address any feedback

---

## File Locations

### Development Files
- Source code: `~/ios_code/redo-ios/Sources/`
- Tests: `~/ios_code/redo-ios/Tests/`
- Package manifest: `~/ios_code/redo-ios/Package.swift`

### Runtime Data (Simulator)
- Change log: `~/Library/Developer/CoreSimulator/Devices/[UUID]/data/Containers/Data/Application/[UUID]/Documents/redo_changes.json`
- Keychain: In iOS Keychain simulator
- UserDefaults: `~/Library/Developer/CoreSimulator/Devices/[UUID]/data/Containers/Data/Application/[UUID]/Library/Preferences/`

### Runtime Data (Device)
- Change log: App's Documents directory (sandboxed)
- Keychain: iOS Keychain (secure enclave)
- Firebase cache: `.firebaseCache/` in Documents

---

## Cross-Platform Testing

### With Web App

1. **Export iOS data**:
   ```swift
   let json = try viewModel.exportData()
   print(json)  // Copy output
   ```

2. **Import to web**:
   ```javascript
   // In browser console
   localStorage.setItem('redo_changes', '[paste JSON]')
   window.location.reload()
   ```

3. **Verify**:
   - Tasks appear in web app
   - Metadata matches (title, priority, etc.)
   - Timestamps are valid

### With Android App

1. **Generate keypair in iOS**
2. **Extract public key**:
   ```swift
   let publicKey = try keychain.loadPublicKey()
   print("Public key:", publicKey)
   ```

3. **Import to Android**:
   ```kotlin
   // In Android app
   sharedPreferences.edit()
       .putString("ed25519_public_key", "paste_here")
       .apply()
   ```

4. **Sync via Firebase**:
   - Create task in iOS
   - Wait for sync (check sync status icon)
   - Open Android app
   - Task should appear after sync

---

## Resources

### Documentation
- **Planning**: [PLANNING.md](PLANNING.md) - Architecture decisions
- **AI Context**: [CLAUDE.md](CLAUDE.md) - Development guidelines
- **Protocol**: `~/WebstormProjects/redo-web-app/PROTOCOL.md` - v1 spec
- **Web Architecture**: `~/WebstormProjects/redo-web-app/ARCHITECTURE.md`

### Reference Implementations
- **Web (leader)**: `~/WebstormProjects/redo-web-app/src/`
- **Android**: `~/StudioProjects/redo-android/app/src/`
- **Kotlin CLI**: `~/IdeaProjects/redo/core/src/`

### External Links
- [Swift Package Manager](https://swift.org/package-manager/)
- [SwiftUI Documentation](https://developer.apple.com/xcode/swiftui/)
- [Firebase iOS SDK](https://firebase.google.com/docs/ios/setup)
- [CryptoKit](https://developer.apple.com/documentation/cryptokit)

---

## Getting Help

### Check Documentation First
1. PLANNING.md - Architecture and design decisions
2. CLAUDE.md - Development guidelines and common pitfalls
3. This file (SETUP.md) - Setup and troubleshooting

### Common Questions

**Q: How do I add a new task action?**
A: See CLAUDE.md "Adding New Action" section

**Q: Why isn't Firebase syncing?**
A: Check Firebase config, security rules, and authentication status

**Q: How do I test cross-platform compatibility?**
A: See "Cross-Platform Testing" section above

**Q: Where is task data stored?**
A: `Documents/redo_changes.json` (change log) + Keychain (crypto keys)

---

## Next Steps

1. **Build and Run**: Open in Xcode, press Cmd+R
2. **Create First Task**: Tap + button, fill form, create
3. **Explore Code**: Start with `RedoApp.swift` and follow the flow
4. **Read Planning**: Review PLANNING.md for architecture details
5. **Add Features**: Follow patterns in existing code

**Happy Coding! 🎯**
