import SwiftUI

// MARK: - Matrix Color Palette

extension Color {
    // Background colors (matching web app exactly)
    static let matrixBackground = Color(hex: "020B09")          // Very dark teal-black
    static let matrixBackgroundSecondary = Color(hex: "0A1815") // Slightly lighter
    static let matrixBackgroundTertiary = Color(hex: "0F1F1C")  // Panel background

    // Neon colors (bright and vibrant like web app)
    static let matrixNeon = Color(hex: "00FFB8")                // Primary neon cyan-green
    static let matrixNeonBright = Color(hex: "00FFD4")          // Brighter variant
    static let matrixNeonDim = Color(hex: "00FFB8").opacity(0.6)
    static let matrixNeonFaint = Color(hex: "00FFB8").opacity(0.3)

    // Accent colors
    static let matrixAmber = Color(hex: "FFC833")               // Warning/highlight
    static let matrixCyan = Color(hex: "00D9FF")                // Info
    static let matrixPurple = Color(hex: "B300FF")              // Special

    // Text colors
    static let matrixTextPrimary = Color(hex: "B8FFE6")         // Light cyan-green
    static let matrixTextSecondary = Color(hex: "80BFA3")       // Dimmed
    static let matrixTextTertiary = Color(hex: "4D8066")        // Very dimmed

    // Status colors
    static let matrixSuccess = Color(hex: "00FF88")             // Success green
    static let matrixError = Color(hex: "FF4444")               // Error red
    static let matrixWarning = Color(hex: "FFAA00")             // Warning orange
    static let matrixInfo = Color(hex: "00AAFF")                // Info blue

    // MARK: - Convenience Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Matrix Typography

extension Font {
    // Use SF Mono (iOS system monospace) for Matrix aesthetic
    // NOTE: All fonts automatically support Dynamic Type (user text size preferences)
    // SwiftUI's .system() respects accessibility text size settings

    static let matrixTitle = Font.system(.largeTitle, design: .monospaced).weight(.bold)
    static let matrixTitle2 = Font.system(.title2, design: .monospaced).weight(.semibold)
    static let matrixTitle3 = Font.system(.title3, design: .monospaced).weight(.semibold)
    static let matrixHeadline = Font.system(.headline, design: .monospaced).weight(.semibold)
    static let matrixBody = Font.system(.body, design: .monospaced)
    static let matrixBodyBold = Font.system(.body, design: .monospaced).weight(.bold)
    static let matrixCallout = Font.system(.callout, design: .monospaced)
    static let matrixCaption = Font.system(.caption, design: .monospaced)
    static let matrixCaption2 = Font.system(.caption2, design: .monospaced)

    // Custom sizes (use sparingly - prefer system styles for better Dynamic Type support)
    static func matrixCustom(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Neon Glow Effect

struct NeonGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.7), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.5), radius: radius * 2, x: 0, y: 0)
            .shadow(color: color.opacity(0.3), radius: radius * 3, x: 0, y: 0)
    }
}

extension View {
    func neonGlow(color: Color = .matrixNeon, radius: CGFloat = 10) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius))
    }
}

// MARK: - Matrix Background Gradient

struct MatrixGradientModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [.matrixBackground, .matrixBackgroundSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

extension View {
    func matrixGradientBackground() -> some View {
        modifier(MatrixGradientModifier())
    }
}

// MARK: - Matrix Border

struct MatrixBorderModifier: ViewModifier {
    let color: Color
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: width)
            )
    }
}

extension View {
    func matrixBorder(color: Color = .matrixNeonFaint, width: CGFloat = 1) -> some View {
        modifier(MatrixBorderModifier(color: color, width: width))
    }
}

// MARK: - Priority Colors

extension Color {
    static func priorityColor(for priority: Int) -> Color {
        switch priority {
        case 1:
            return .matrixTextSecondary  // Low
        case 2:
            return .matrixTextPrimary    // Medium-Low
        case 3:
            return .matrixNeon           // Medium
        case 4:
            return .matrixAmber          // Medium-High
        case 5:
            return .matrixError          // High
        default:
            return .matrixNeon
        }
    }

    static func urgencyColor(for status: String) -> Color {
        switch status.lowercased() {
        case "critical":
            return .matrixError
        case "high":
            return .matrixWarning
        case "medium":
            return .matrixAmber
        case "low":
            return .matrixNeon
        default:
            return .matrixTextSecondary
        }
    }
}

// MARK: - Standard Spacing

extension CGFloat {
    static let matrixSpacingTiny: CGFloat = 4
    static let matrixSpacingSmall: CGFloat = 8
    static let matrixSpacingMedium: CGFloat = 12
    static let matrixSpacingLarge: CGFloat = 16
    static let matrixSpacingXLarge: CGFloat = 24
    static let matrixSpacingXXLarge: CGFloat = 32

    static let matrixCornerRadius: CGFloat = 12
    static let matrixBorderWidth: CGFloat = 1
}

// MARK: - Enhanced Animation Effects

/// Pulsing glow effect for attention-grabbing elements
struct PulsingGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isPulsing ? 0.8 : 0.4), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(isPulsing ? 0.6 : 0.3), radius: radius * 2, x: 0, y: 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

/// Shimmer loading effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .matrixNeon.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(30))
                    .offset(x: phase)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = 400
                        }
                    }
            )
            .clipped()
    }
}

/// Scale effect on tap for buttons
struct ScaleOnTapModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
            )
    }
}

extension View {
    /// Apply pulsing neon glow effect
    func pulsingNeonGlow(color: Color = .matrixNeon, radius: CGFloat = 10) -> some View {
        self.modifier(PulsingGlowModifier(color: color, radius: radius))
    }

    /// Apply shimmer loading effect
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }

    /// Apply smooth scale animation on tap
    func scaleOnTap() -> some View {
        self.modifier(ScaleOnTapModifier())
    }
}

// MARK: - Matrix Title Effect (Animated Gradient Text)

struct MatrixTitleEffectModifier: ViewModifier {
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: [.matrixNeonBright, .matrixNeon, .matrixCyan, .matrixNeonBright],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    offset = 1
                }
            }
    }
}

extension View {
    /// Apply animated gradient text effect (Matrix style)
    func matrixTitleEffect() -> some View {
        self.modifier(MatrixTitleEffectModifier())
    }
}
