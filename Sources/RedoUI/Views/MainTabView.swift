import SwiftUI

/// Main tab bar navigation
public struct MainTabView: View {
    @StateObject private var viewModel = AppViewModel()

    public init() {}

    public var body: some View {
        TabView {
            // Tasks Tab
            TaskListView(viewModel: viewModel)
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }

            // Calendar Tab
            CalendarView(viewModel: viewModel)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            // Activity Tab
            ActivityView(viewModel: viewModel)
                .tabItem {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }

            // Analytics Tab
            AnalyticsView(viewModel: viewModel)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }

            // Settings Tab
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .accentColor(.matrixNeon)
        .preferredColorScheme(.dark)
        .onAppear {
            // Configure tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.matrixBackgroundSecondary)

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
