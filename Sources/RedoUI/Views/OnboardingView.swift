import SwiftUI

/// Onboarding experience showing key Redo features
public struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "arrow.triangle.branch",
            title: "Event Sourcing",
            description: "Like Git for your tasks. Every change is tracked in an immutable log, giving you complete history and undo capabilities.",
            color: .matrixNeon
        ),
        OnboardingPage(
            icon: "wifi.slash",
            title: "Offline-First",
            description: "Works perfectly without internet. All operations are instant and local. Sync is optional and happens in the background.",
            color: .matrixCyan
        ),
        OnboardingPage(
            icon: "arrow.triangle.2.circlepath",
            title: "Real-Time Sync",
            description: "Sign in with Google to sync across devices. Changes appear instantly on all your devices when online.",
            color: .matrixAmber
        ),
        OnboardingPage(
            icon: "lock.shield",
            title: "Cryptographically Signed",
            description: "Each change is signed with your Ed25519 key. Your identity is cryptographically verified across all platforms.",
            color: .matrixPurple
        ),
        OnboardingPage(
            icon: "checkmark.circle.fill",
            title: "Ready to Redo",
            description: "A local-first task manager that respects your data, works offline, and syncs when you want it to.",
            color: .matrixSuccess
        )
    ]

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            // Matrix background
            Color.matrixBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()

                    if currentPage < pages.count - 1 {
                        Button(action: { skip() }) {
                            Text("Skip")
                                .font(.matrixBody)
                                .foregroundColor(.matrixTextSecondary)
                                .padding()
                        }
                    }
                }

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? pages[index].color : Color.matrixTextSecondary.opacity(0.3))
                            .frame(width: currentPage == index ? 12 : 8, height: currentPage == index ? 12 : 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.bottom, .matrixSpacingMedium)

                // Navigation buttons
                HStack(spacing: .matrixSpacingMedium) {
                    if currentPage > 0 {
                        Button(action: { previousPage() }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.matrixBodyBold)
                            .foregroundColor(.matrixTextPrimary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.matrixBackgroundSecondary)
                            .cornerRadius(.matrixCornerRadius)
                            .matrixBorder()
                        }
                    }

                    Button(action: { nextPage() }) {
                        HStack {
                            Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            if currentPage < pages.count - 1 {
                                Image(systemName: "chevron.right")
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                        }
                        .font(.matrixBodyBold)
                        .foregroundColor(.matrixBackground)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(pages[currentPage].color)
                        .cornerRadius(.matrixCornerRadius)
                        .neonGlow(color: pages[currentPage].color, radius: 12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, .matrixSpacingLarge)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Navigation

    private func nextPage() {
        if currentPage < pages.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPage += 1
            }
            HapticManager.shared.selectionChanged()
        } else {
            complete()
        }
    }

    private func previousPage() {
        if currentPage > 0 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPage -= 1
            }
            HapticManager.shared.selectionChanged()
        }
    }

    private func skip() {
        complete()
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        HapticManager.shared.success()

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: .matrixSpacingLarge) {
            Spacer()

            // Icon with animation
            ZStack {
                // Animated rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(page.color.opacity(0.2), lineWidth: 2)
                        .frame(width: 120 + CGFloat(index) * 40, height: 120 + CGFloat(index) * 40)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .opacity(isAnimating ? 0.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                            value: isAnimating
                        )
                }

                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 64))
                    .foregroundColor(page.color)
                    .neonGlow(color: page.color, radius: 16)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            .frame(height: 200)
            .padding(.bottom, .matrixSpacingLarge)

            // Title
            Text(page.title)
                .font(.matrixTitle)
                .foregroundColor(page.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Description
            Text(page.description)
                .font(.matrixBody)
                .foregroundColor(.matrixTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .matrixSpacingLarge)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isPresented: .constant(true))
    }
}
#endif
