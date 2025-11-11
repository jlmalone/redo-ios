# How to Run Redo iOS App

## The Issue

Swift Package Manager packages with iOS libraries can't be run directly as apps in the simulator. You need to create an actual iOS app project that uses the package.

## Solution: Create an Xcode iOS App Project

### Step 1: Create a New iOS App in Xcode

1. Open Xcode
2. **File → New → Project**
3. Select **iOS → App**
4. Click **Next**
5. Fill in:
   - **Product Name**: `Redo`
   - **Team**: Select your team (or None for local dev)
   - **Organization Identifier**: `vision.salient`
   - **Bundle Identifier**: Will be `vision.salient.Redo`
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - **Storage**: None
6. Click **Next**
7. **Save location**: Choose `~/ios_code/` (OUTSIDE the redo-ios directory)
8. Click **Create**

### Step 2: Add the Package as a Dependency

1. In your new Xcode project, select the **project** (not target) in the navigator
2. Go to **Package Dependencies** tab
3. Click **+** (Add Package Dependency)
4. Enter the **local path**: `file:///Users/josephmalone/ios_code/redo-ios`
5. Click **Add Package**
6. Select all libraries:
   - RedoCore
   - RedoCrypto
   - RedoUI
   - RedoWidgets (optional)
   - RedoIntents (optional)
7. Click **Add Package**

### Step 3: Replace ContentView

1. Delete the generated `ContentView.swift` file
2. Delete the generated `RedoApp.swift` (or whatever the @main file is)
3. Create a new Swift file: **File → New → File → Swift File**
4. Name it: `App.swift`
5. Add this code:

```swift
import SwiftUI
import RedoUI
import FirebaseCore

@main
struct RedoMainApp: App {
    init() {
        // Configure Firebase
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            // Use the RedoUI library's views
            MainTabView()
        }
    }
}
```

### Step 4: Add GoogleService-Info.plist

1. Download your `GoogleService-Info.plist` from Firebase Console
2. Drag it into your Xcode project
3. Make sure "Copy items if needed" is checked
4. Make sure your app target is selected

### Step 5: Configure Signing

1. Select the **target** in project navigator
2. Go to **Signing & Capabilities**
3. Check **Automatically manage signing**
4. Select your **Team**

### Step 6: Run!

1. Select a simulator from the scheme dropdown (e.g., "iPhone 15 Pro")
2. Press **⌘R** (Command-R) or click the Play button
3. The app should build and launch!

---

## Alternative: Use the Existing iOS Project Structure

Since SPM doesn't support iOS app targets well, the better approach is to create a full iOS app project that depends on this package as a local Swift Package.

The `redo-ios` directory remains a Swift Package with:
- RedoCore (business logic)
- RedoCrypto (signing/hashing)
- RedoUI (SwiftUI views)
- RedoWidgets (widgets extension)
- RedoIntents (Siri shortcuts)

But the **runnable iOS app** is a separate Xcode project that:
- Imports these packages as dependencies
- Has an app target with @main
- Contains GoogleService-Info.plist
- Has proper Info.plist and signing

This is the standard iOS development pattern for Swift Packages.

---

## Quick Start Script

Save this as `~/ios_code/create-redo-app.sh`:

```bash
#!/bin/bash
cd ~/ios_code

# Create app structure
mkdir -p RedoApp/RedoApp

# Create App.swift
cat > RedoApp/RedoApp/App.swift << 'EOF'
import SwiftUI
import RedoUI
import FirebaseCore

@main
struct RedoMainApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
EOF

echo "Created RedoApp structure"
echo "Now:"
echo "1. Open Xcode and create new iOS App project at ~/ios_code/RedoApp"
echo "2. Replace generated files with the App.swift above"
echo "3. Add redo-ios as local package dependency"
echo "4. Add GoogleService-Info.plist"
echo "5. Run!"
```

---

## Why This Approach?

Swift Package Manager is designed for:
- ✅ Libraries
- ✅ Command-line tools
- ✅ Multi-platform code sharing

It's NOT designed for:
- ❌ iOS app bundles
- ❌ App Store submissions
- ❌ Asset catalogs
- ❌ Storyboards
- ❌ App-specific configurations

For iOS apps, you need a `.xcodeproj` which contains:
- App target
- Bundle identifier
- Signing configuration
- Info.plist
- Asset catalogs
- LaunchScreen
- Capabilities (push notifications, etc.)

---

## Summary

**This package (`redo-ios`)** = Reusable Swift Package libraries

**New iOS project** = Actual app that imports this package

This is the recommended Apple approach for modular iOS development!
