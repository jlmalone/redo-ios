# Running the Redo iOS App

## Quick Start

### Step 1: Open in Xcode

```bash
cd ~/ios_code/redo-ios
open Package.swift
```

OR double-click `Package.swift` in Finder.

### Step 2: Wait for Dependencies

Xcode will automatically:
- Resolve Swift Package dependencies (Firebase, GoogleSignIn, etc.)
- This may take 2-5 minutes on first open
- Watch the progress at the top of the Xcode window

### Step 3: Select the Redo Scheme

At the top of Xcode window:
1. Click the scheme dropdown (should show "Redo" or "My Mac")
2. Select **"Redo"** from the list
3. Next to it, select an iOS simulator (e.g., "iPhone 15 Pro")

### Step 4: Run the App

Press **⌘R** (Command-R) or click the Play button (▶) at the top left.

The app should build and launch in the simulator!

---

## Important Setup: Firebase Configuration

### ⚠️ Before First Run

The app needs a real Firebase configuration. The placeholder file will cause crashes.

1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Select your project** (or create a new one)
3. **Add an iOS app**:
   - Click "Add app" → iOS
   - Bundle ID: `vision.salient.redo` (or your choice)
   - App nickname: "Redo iOS"
   - Skip App Store ID
4. **Download GoogleService-Info.plist**
5. **Replace the placeholder**:
   ```bash
   cp ~/Downloads/GoogleService-Info.plist ~/ios_code/redo-ios/App/
   ```

### Firebase Features Used

- **Firebase Auth**: Google Sign-In for optional cloud sync
- **Firestore**: Cloud storage for task sync across devices
- **Firebase Core**: Configuration and initialization

---

## Troubleshooting

### Error: "No such module 'FirebaseCore'"

**Solution**: Wait for SPM to finish resolving dependencies. Look at the top of Xcode for progress.

### Error: "Bundle identifier cannot be empty"

**Solution**:
1. Select the "App" target in the project navigator (left sidebar)
2. Go to "Signing & Capabilities" tab
3. Check "Automatically manage signing"
4. Select your Apple Developer team

### Error: GoogleService-Info.plist errors

**Solution**: Replace the placeholder plist with your actual Firebase config (see above).

### Simulator won't launch

**Solution**:
```bash
# Restart CoreSimulator service
killall -9 com.apple.CoreSimulator.CoreSimulatorService
```

### Build fails with "no such file or directory"

**Solution**: Clean build folder with **⌘⇧K** (Command-Shift-K), then rebuild.

---

## Running on Physical Device

### Requirements:
- Apple Developer account (free or paid)
- Device connected via USB
- Device added to provisioning profile

### Steps:
1. Connect iPhone/iPad via USB
2. Trust this computer on device (if prompted)
3. In Xcode, select your device from scheme dropdown
4. Click Run (⌘R)
5. On device: Settings → General → VPN & Device Management
6. Trust your developer certificate
7. Open Redo app

---

## First Launch Experience

### What to Expect:

1. **Onboarding Screens**: Welcome, features tour, Matrix-themed intro
2. **Optional Sign-In**: Google OAuth for cloud sync (can skip for offline use)
3. **Main App**: Task list, calendar, analytics tabs

### Offline Mode:

- App works fully offline without signing in
- All tasks stored locally in encrypted change log
- Can enable sync later via Settings

### Signed-In Mode:

- Tasks sync across all your devices
- Web app integration at `~/WebstormProjects/redo-web-app`
- Android app integration at `~/StudioProjects/redo-android`

---

## Development Tips

### Hot Reload (SwiftUI Previews)

1. Open any View file (e.g., `TaskListView.swift`)
2. Press **⌘⌥P** (Command-Option-P) to show preview
3. Edit code and see changes instantly
4. Click "Try Again" if preview breaks

### Debugging

- Set breakpoints by clicking line numbers
- Press **⌘\** (Command-Backslash) to pause execution
- Use `print()` statements (visible in Xcode console)

### Viewing Console Logs

- **View → Debug Area → Activate Console** (⌘⇧C)
- All `print()` statements appear here
- Firebase logs also visible

### Clean Build

If you get mysterious errors:
1. **⌘⇧K** - Clean Build Folder
2. Close Xcode
3. `rm -rf ~/Library/Developer/Xcode/DerivedData/RedoApp-*`
4. Reopen Xcode and rebuild

---

## Project Structure in Xcode

```
redo-ios/
├── App/                          # Executable target (what you run)
│   ├── main.swift               # App entry point
│   └── GoogleService-Info.plist # Firebase config
├── Sources/
│   ├── RedoCore/                # Business logic (platform-agnostic)
│   ├── RedoCrypto/              # Ed25519, SHA-256, signing
│   └── RedoUI/                  # SwiftUI views and view models
└── Tests/                       # Unit tests
```

---

## Building for Release

### Archive for App Store:

1. Select "Any iOS Device (arm64)" as target
2. **Product → Archive**
3. Wait for build to complete
4. Xcode Organizer opens → click "Distribute App"
5. Follow App Store Connect submission flow

### Requirements:
- Paid Apple Developer account ($99/year)
- Proper bundle ID
- App icons (in Assets.xcassets)
- Screenshots for App Store listing

---

## Next Steps

- ✅ App running in simulator
- 🔧 Replace GoogleService-Info.plist with real config
- 🎨 Explore Matrix-themed UI
- 📝 Create your first task
- 🔄 Set up Firebase project for sync
- 📱 Test on physical device

Need help? Check other docs:
- `README.md` - Project overview and features
- `PLANNING.md` - Architecture deep dive
- `PROTOCOL.md` - Cross-platform sync protocol
- `BUILD_NOTES.md` - Why command-line builds show errors

Enjoy building with Redo! 🎯⚡
