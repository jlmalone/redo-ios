# Redo iOS - Asset Guidelines

This document provides instructions for creating and integrating the app icon and launch screen assets for Redo iOS.

## App Icon Design

### Design Concept

The Redo app icon should embody the **Matrix aesthetic** and **event sourcing** architecture:

- **Primary Symbol**: Git-like branching tree or arrow triangle (∇) representing event sourcing
- **Color Scheme**: Neon cyan-green (#00FFB8) on dark teal-black background (#020B09)
- **Style**: Minimal, modern, tech-forward with neon glow effect
- **Mood**: Professional, trustworthy, cutting-edge

### Icon Specifications

#### Required Sizes (iOS)

Create app icons in the following sizes for iOS App Store and devices:

| Size | Usage | Filename |
|------|-------|----------|
| 1024x1024 | App Store | AppIcon-1024.png |
| 180x180 | iPhone @3x | AppIcon-60@3x.png |
| 120x120 | iPhone @2x | AppIcon-60@2x.png |
| 167x167 | iPad Pro @2x | AppIcon-83.5@2x.png |
| 152x152 | iPad @2x | AppIcon-76@2x.png |
| 76x76 | iPad @1x | AppIcon-76.png |
| 40x40 | Spotlight @2x | AppIcon-20@2x.png |
| 29x29 | Settings @1x | AppIcon-29.png |

#### Design Guidelines

1. **No transparency** - Use solid background (#020B09)
2. **No text** - Icon only (save "REDO" text for launch screen)
3. **Safe area** - Keep critical elements 10% inset from edges
4. **Consistent glow** - Use neon shadow effects (3-layer shadow: 10px, 20px, 30px)
5. **Export as PNG** - 24-bit PNG with no alpha channel

### Design Options

#### Option 1: Event Sourcing Symbol
```
┌─────────────────────┐
│                     │
│        ∇            │  ← Git-like branching arrow
│       ╱ ╲           │    in neon cyan (#00FFB8)
│      ╱   ╲          │    with soft glow
│     ●─────●         │
│    ╱               │
│   ●                 │
│                     │
└─────────────────────┘
Background: #020B09 (dark teal-black)
Symbol: #00FFB8 (neon cyan-green) with glow
```

#### Option 2: Minimalist "R"
```
┌─────────────────────┐
│                     │
│     ██████          │  ← Monospace "R"
│     ██   ██         │    with glowing outline
│     ██████          │
│     ██  ██          │
│     ██   ██         │
│                     │
└─────────────────────┘
Outline glow: #00FFB8
Fill: #020B09
```

#### Option 3: Abstract Data Flow
```
┌─────────────────────┐
│                     │
│    ●→●→●→●          │  ← Sequential nodes
│      ↓ ↓ ↓          │    representing change log
│    ●→●→●→●          │    event flow
│                     │
└─────────────────────┘
Nodes/arrows: #00FFB8
Background: #020B09
```

### Recommended Tools

- **Figma** (recommended) - Free, excellent for icon design
- **Sketch** - Professional vector editor (macOS)
- **Adobe Illustrator** - Industry standard
- **SF Symbols** - Use as reference for iOS-style icons
- **Icon Generator** - [appicon.co](https://appicon.co) for automatic size generation

### Color Palette

```swift
Primary:     #00FFB8  // Neon cyan-green
Background:  #020B09  // Dark teal-black
Accent:      #00FFD4  // Brighter neon
Dim:         #80BFA3  // Dimmed neon (for shadows)
```

## Launch Screen Integration

### Using LaunchScreen.swift

The launch screen has been implemented in SwiftUI at `Sources/RedoUI/Views/LaunchScreen.swift`.

#### To integrate:

1. **Update your App file** to show LaunchScreen during initialization:

```swift
@main
struct RedoApp: App {
    @StateObject private var viewModel = AppViewModel()
    @State private var showLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchScreen()
                        .transition(.opacity)
                } else {
                    MainTabView()
                }
            }
            .task {
                // Simulate initialization
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                withAnimation(.easeOut(duration: 0.5)) {
                    showLaunchScreen = false
                }
            }
        }
    }
}
```

2. **Or use UIKit Launch Screen** (traditional approach):

In Xcode:
1. Create new file: File → New → Launch Screen (Storyboard)
2. Design using Interface Builder
3. Set in project settings: Target → General → Launch Screen File

### Launch Screen Design

The included `LaunchScreen.swift` features:

- ✅ **Animated Matrix background** - Subtle vertical lines
- ✅ **Neon glowing icon** - Git branch symbol with pulsing glow
- ✅ **REDO branding** - Large monospace title
- ✅ **Tagline** - "Local-First Task Management"
- ✅ **Loading indicator** - Animated dots
- ✅ **Version info** - App version and key features
- ✅ **Accessibility** - Hidden from VoiceOver (`.accessibilityHidden(true)`)

### Customization

To customize the launch screen, edit `LaunchScreen.swift`:

```swift
// Change icon
Image(systemName: "arrow.triangle.branch")  // ← Change to your custom symbol

// Change colors
.foregroundColor(.matrixNeon)  // ← Use your brand color

// Adjust animation speed
Animation.easeInOut(duration: 1.0)  // ← Faster/slower animations

// Modify glow intensity
.shadow(color: .matrixNeon, radius: 20)  // ← Adjust glow radius
```

## Adding App Icon to Project

### Method 1: Xcode Asset Catalog (Recommended)

1. Open Xcode
2. Navigate to `Assets.xcassets`
3. Find or create "AppIcon" asset
4. Drag and drop your icon images into the appropriate slots
5. Xcode will automatically handle all sizes and variants

### Method 2: Manual Configuration

If creating a custom asset catalog:

1. Create `AppIcon.appiconset` directory
2. Add all PNG files
3. Create `Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "AppIcon-60@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "AppIcon-60@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

## Testing Your Assets

### App Icon Testing

1. **Simulator**: Run app in iOS Simulator, check Home Screen
2. **Device**: Install on physical device via TestFlight or direct install
3. **Spotlight**: Search for app name, verify icon appears correctly
4. **Settings**: Check app icon in Settings app
5. **Multitasking**: Verify icon in app switcher

### Launch Screen Testing

1. **Kill app completely** (swipe up in app switcher)
2. **Relaunch** - Launch screen should appear briefly
3. **Dark mode** - Test in both light and dark mode
4. **Different devices** - Test on iPhone SE, iPhone Pro, iPad
5. **Accessibility** - Enable VoiceOver, verify launch screen is hidden

### Common Issues

#### App Icon Issues

**Problem**: Icon appears with white border
- **Solution**: Remove alpha channel, use solid background

**Problem**: Icon looks blurry
- **Solution**: Ensure you're providing @2x and @3x variants, not scaling

**Problem**: Icon doesn't update
- **Solution**: Delete app, clean build folder (Cmd+Shift+K), rebuild

#### Launch Screen Issues

**Problem**: Launch screen doesn't appear
- **Solution**: Check project target → General → Launch Screen File is set

**Problem**: Old launch screen still showing
- **Solution**: Delete app from device, clean build, reinstall

**Problem**: Launch screen appears too long
- **Solution**: Reduce sleep duration in initialization code

## Brand Consistency

### Matrix Theme Checklist

When creating assets, ensure they match the Matrix aesthetic:

- [x] **Dark background** (#020B09 or similar)
- [x] **Neon accents** (#00FFB8 primary, #00FFD4 highlights)
- [x] **Monospace typography** (SF Mono or similar)
- [x] **Glowing effects** (multi-layer shadows)
- [x] **Minimal design** (no unnecessary decoration)
- [x] **Tech-forward** (geometric shapes, clean lines)
- [x] **Professional** (not playful or casual)

### Cross-Platform Consistency

Redo is available on multiple platforms. Ensure your icon is recognizable across:

- **iOS** (this app)
- **Android** (~/StudioProjects/redo-android)
- **Web** (~/WebstormProjects/redo-web-app)

**Recommendation**: Use the same core symbol (Git branch/event sourcing icon) across all platforms, adapting only for platform-specific requirements (rounded corners on iOS, adaptive icons on Android, etc.).

## Resources

### Icon Design Inspiration

- [iOS Human Interface Guidelines - App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [SF Symbols](https://developer.apple.com/sf-symbols/) - Apple's icon library
- [Figma Community](https://www.figma.com/community) - Free icon templates
- [Dribbble](https://dribbble.com/search/app-icon) - Design inspiration

### Color Tools

- [Coolors.co](https://coolors.co) - Color palette generator
- [Contrast Checker](https://webaim.org/resources/contrastchecker/) - Accessibility contrast
- [Neon Glow Generator](https://www.cssmatic.com/box-shadow) - CSS/SwiftUI shadow effects

### Icon Generators

- [appicon.co](https://appicon.co) - Generate all sizes from one image
- [makeappicon.com](https://makeappicon.com) - Free icon generator
- [Icon Slate](http://www.kodlian.com/apps/icon-slate) - macOS icon designer

## Accessibility Considerations

### App Icon

- **High contrast** - Ensure icon is visible in all lighting conditions
- **No tiny details** - Icon will be small in many contexts
- **Distinctive shape** - Recognizable even without color
- **Color blind friendly** - Test with color blindness simulators

### Launch Screen

- **Hidden from VoiceOver** - Already implemented (`.accessibilityHidden(true)`)
- **Quick dismiss** - Don't keep users waiting
- **Reduce motion** - Respect system animation preferences
- **High contrast mode** - Ensure visibility with increased contrast

## Next Steps

1. **Design app icon** using one of the options above
2. **Generate all sizes** using appicon.co or similar tool
3. **Add to Xcode** via Assets.xcassets
4. **Test on device** to verify appearance
5. **Integrate launch screen** if desired (already implemented in LaunchScreen.swift)
6. **Submit to App Store** with finalized icon

## Questions?

For design questions or feedback:
- Review PLANNING.md for architecture context
- Check web app icon at ~/WebstormProjects/redo-web-app/public/
- Reference Android icon at ~/StudioProjects/redo-android/app/src/main/res/

---

**Last Updated**: 2025-11-09
**Status**: Ready for icon creation and integration
