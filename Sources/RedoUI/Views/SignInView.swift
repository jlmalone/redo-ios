import SwiftUI

/// Google Sign-In view with Matrix theme
public struct SignInView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var authManager = GoogleAuthManager.shared
    @State private var isSigningIn = false
    @State private var showError = false

    let onSignInComplete: () -> Void

    public init(viewModel: AppViewModel, onSignInComplete: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSignInComplete = onSignInComplete
    }

    public var body: some View {
        ZStack {
            // Matrix background
            Color.matrixBackground.ignoresSafeArea()

            VStack(spacing: .matrixSpacingXLarge) {
                Spacer()

                // Logo and Title
                VStack(spacing: .matrixSpacingLarge) {
                    // Matrix-style title
                    Text("REDO")
                        .font(.matrixCustom(size: 64, weight: .bold))
                        .foregroundColor(.matrixNeon)
                        .neonGlow(radius: 20)

                    Text("Task Management Reimagined")
                        .font(.matrixHeadline)
                        .foregroundColor(.matrixTextSecondary)
                }

                Spacer()

                // Sign-In Section
                VStack(spacing: .matrixSpacingMedium) {
                    // Description
                    VStack(spacing: .matrixSpacingSmall) {
                        Text("Local-First Architecture")
                            .font(.matrixBodyBold)
                            .foregroundColor(.matrixTextPrimary)

                        Text("All tasks stored locally. Sign in to sync across devices.")
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Google Sign-In Button
                    Button(action: signInWithGoogle) {
                        HStack(spacing: .matrixSpacingMedium) {
                            if isSigningIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .matrixBackground))
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)

                                Text("Sign in with Google")
                                    .font(.matrixHeadline)
                            }
                        }
                        .foregroundColor(.matrixBackground)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.matrixNeon)
                        .cornerRadius(.matrixCornerRadius)
                        .neonGlow(color: .matrixNeon, radius: 12)
                    }
                    .disabled(isSigningIn)
                    .scaleOnTap()
                    .padding(.horizontal)

                    // Continue Offline
                    Button(action: continueOffline) {
                        Text("Continue Offline")
                            .font(.matrixBody)
                            .foregroundColor(.matrixTextSecondary)
                            .underline()
                    }
                    .padding(.top, .matrixSpacingSmall)
                }

                Spacer()

                // Footer
                VStack(spacing: .matrixSpacingSmall) {
                    Text("Event Sourcing • End-to-End Encryption")
                        .font(.matrixCaption2)
                        .foregroundColor(.matrixTextTertiary)

                    Text("v0.1.0 Beta")
                        .font(.matrixCaption2)
                        .foregroundColor(.matrixTextTertiary)
                }
                .padding(.bottom, .matrixSpacingLarge)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                showError = false
            }
        } message: {
            if let error = authManager.errorMessage {
                Text(error)
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, newValue in
            if newValue {
                onSignInComplete()
            }
        }
    }

    // MARK: - Actions

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

                // Reinitialize Firebase sync
                await viewModel.reinitializeSync()

                // Haptic feedback
                HapticManager.shared.success()

                isSigningIn = false
            } catch {
                authManager.errorMessage = error.localizedDescription
                showError = true
                isSigningIn = false

                // Haptic feedback
                HapticManager.shared.error()
            }
        }
    }

    private func continueOffline() {
        // Haptic feedback
        HapticManager.shared.buttonTapped()

        onSignInComplete()
    }
}

// MARK: - Preview

#if DEBUG
struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView(onSignInComplete: {})
    }
}
#endif
