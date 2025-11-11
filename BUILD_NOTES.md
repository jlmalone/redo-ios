# Build Notes

## Building the Project

This is an **iOS-only application** that should be built using **Xcode**, not the Swift Package Manager command-line tools.

### ✅ To Build (Correct Method):

1. Open `Package.swift` in Xcode
2. Select an iOS target (device or simulator)
3. Build and run (⌘R)

### ❌ Command-Line Build Issues:

Running `swift build` from the command line will show errors like:

```
error: the library 'RedoUI' requires macos 10.13, but depends on the product 'GoogleSignIn' which requires macos 10.15
```

**This is a false error.** Swift Package Manager's command-line tools try to validate cross-platform compatibility even though:
- `Package.swift` specifies `platforms: [.iOS(.v17)]` (iOS-only)
- The code uses iOS-specific APIs (UIKit, SwiftUI iOS modifiers)
- GoogleSignIn is an iOS library

### Why This Happens:

SPM's dependency resolution tries to ensure cross-platform compatibility, but our dependencies (Firebase, GoogleSignIn) have different platform requirements. When building in Xcode with an iOS target selected, these errors don't occur because Xcode correctly understands the iOS-only context.

### iOS-Specific SwiftUI Modifiers Used:

The following SwiftUI modifiers are iOS-specific and will work in Xcode but may show as "unavailable" in SPM command-line builds:

- `.navigationBarTitleDisplayMode(.inline/.large)`
- `.toolbar { ToolbarItem(placement: .navigationBarTrailing) { ... } }`
- `.toolbar { ToolbarItem(placement: .navigationBarLeading) { ... } }`
- `UITabBar.appearance()`
- `UIViewController` presentation APIs

These are standard iOS SwiftUI APIs and work perfectly when building for iOS in Xcode.

## Summary

- ✅ **Xcode**: Full iOS support, builds correctly
- ❌ **swift build**: Cross-platform validation errors (can be ignored)
- 🎯 **Target Platform**: iOS 17+
