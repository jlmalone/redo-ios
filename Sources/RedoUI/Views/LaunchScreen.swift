import SwiftUI

/// Launch screen with Matrix branding
/// Shown while the app initializes
public struct LaunchScreen: View {
    @State private var isAnimating = false
    @State private var glowIntensity: CGFloat = 0.3

    public init() {}

    public var body: some View {
        ZStack {
            // Matrix background
            Color.matrixBackground.ignoresSafeArea()

            // Animated background pattern (subtle)
            GeometryReader { geometry in
                ForEach(0..<5) { index in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.matrixNeon.opacity(0.05), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 2, height: geometry.size.height)
                        .offset(
                            x: CGFloat(index) * geometry.size.width / 5,
                            y: isAnimating ? -geometry.size.height : geometry.size.height
                        )
                        .animation(
                            Animation.linear(duration: 2.0 + Double(index) * 0.5)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }
            }

            // Main content
            VStack(spacing: 32) {
                // Logo/Icon
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                Color.matrixNeon.opacity(0.2),
                                lineWidth: 2
                            )
                            .frame(width: 120 + CGFloat(index) * 30)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                            .opacity(isAnimating ? 0.0 : 0.5)
                            .animation(
                                Animation.easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }

                    // Center icon
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.matrixNeon)
                        .shadow(color: .matrixNeon, radius: glowIntensity * 20)
                        .shadow(color: .matrixNeon, radius: glowIntensity * 40)
                        .shadow(color: .matrixNeon, radius: glowIntensity * 60)
                        .scaleEffect(isAnimating ? 1.05 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                }

                // App name
                VStack(spacing: 8) {
                    Text("REDO")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.matrixNeon)
                        .shadow(color: .matrixNeon, radius: glowIntensity * 15)
                        .shadow(color: .matrixNeon, radius: glowIntensity * 30)

                    Text("Local-First Task Management")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.matrixTextSecondary)
                        .opacity(isAnimating ? 1.0 : 0.7)
                        .animation(
                            Animation.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                }

                // Loading indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.matrixNeon)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isAnimating ? 1.0 : 0.5)
                            .opacity(isAnimating ? 1.0 : 0.3)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                .padding(.top, 32)
            }

            // Version info (bottom)
            VStack {
                Spacer()

                VStack(spacing: 4) {
                    Text("v0.1.0 Beta")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.matrixTextTertiary)

                    Text("Event Sourcing • Offline-First • E2EE")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.matrixTextTertiary.opacity(0.6))
                }
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isAnimating = true

            // Pulse glow intensity
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                glowIntensity = 0.3 + sin(Date().timeIntervalSince1970 * 2) * 0.2
            }
        }
        .accessibilityHidden(true) // Hide from VoiceOver during launch
    }
}

// MARK: - Preview

#if DEBUG
struct LaunchScreen_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreen()
    }
}
#endif
