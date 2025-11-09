import SwiftUI
import FirebaseCore

@main
struct RedoApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var authManager = GoogleAuthManager.shared
    @State private var showOnboarding = false
    @State private var showSignIn = false

    init() {
        // Configure Firebase
        FirebaseApp.configure()

        // Configure appearance for Matrix theme
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showOnboarding {
                    OnboardingView(isPresented: $showOnboarding)
                } else if showSignIn && !authManager.isAuthenticated {
                    SignInView(viewModel: viewModel) {
                        showSignIn = false
                    }
                } else {
                    MainTabView()
                }
            }
            .onAppear {
                // Show onboarding on first launch
                if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                    showOnboarding = true
                } else if !authManager.isAuthenticated && !UserDefaults.standard.bool(forKey: "hasSeenSignIn") {
                    // Show sign-in after onboarding if not authenticated
                    // Users can skip and use offline mode
                    showSignIn = true
                    UserDefaults.standard.set(true, forKey: "hasSeenSignIn")
                }
            }
            .onChange(of: showOnboarding) { _, newValue in
                // After onboarding completes, show sign-in if not authenticated
                if !newValue && !authManager.isAuthenticated && !UserDefaults.standard.bool(forKey: "hasSeenSignIn") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showSignIn = true
                        UserDefaults.standard.set(true, forKey: "hasSeenSignIn")
                    }
                }
            }
        }
    }

    private func configureAppearance() {
        // Navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.matrixBackground)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(Color.matrixNeon),
            .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Color.matrixNeon),
            .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Tab bar appearance (for future use)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Color.matrixBackground)

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Set global tint color
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Color.matrixNeon)
    }
}
