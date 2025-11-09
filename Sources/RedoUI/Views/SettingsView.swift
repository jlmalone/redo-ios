import SwiftUI
import RedoCore
import RedoCrypto

/// Settings and configuration view
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var exportedJSON = ""
    @State private var importText = ""
    @State private var showingClearDataConfirmation = false
    @StateObject private var authManager = GoogleAuthManager.shared
    @State private var showingSignInSheet = false
    @State private var showingOnboarding = false

    private let keychain = KeychainService()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                List {
                    // Authentication Section
                    authenticationSection

                    // Identity Section
                    identitySection

                    // Data Management Section
                    dataManagementSection

                    // Sync Section
                    syncSection

                    // About Section
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingExportSheet) {
                ExportView(json: exportedJSON)
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportView(importText: $importText, onImport: handleImport)
            }
            .sheet(isPresented: $showingSignInSheet) {
                SignInView(viewModel: viewModel) {
                    showingSignInSheet = false
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView(isPresented: $showingOnboarding)
            }
            .alert("Clear All Data?", isPresented: $showingClearDataConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear Data", role: .destructive, action: clearAllData)
            } message: {
                Text("This will delete all tasks and change history. This action cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var authenticationSection: some View {
        Section {
            if authManager.isAuthenticated {
                // Signed in state
                VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.matrixSuccess)

                        Text("Signed In")
                            .font(.matrixBodyBold)
                            .foregroundColor(.matrixSuccess)

                        Spacer()
                    }

                    if let email = authManager.getUserEmail() {
                        Text(email)
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextSecondary)
                    }
                }

                // Sign out button
                Button(action: signOut) {
                    HStack {
                        Image(systemName: "arrow.right.square")
                            .foregroundColor(.matrixError)

                        Text("Sign Out")
                            .foregroundColor(.matrixError)

                        Spacer()
                    }
                }
            } else {
                // Not signed in state
                Button(action: { showingSignInSheet = true }) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.matrixNeon)

                        Text("Sign in with Google")
                            .foregroundColor(.matrixTextPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.matrixTextSecondary)
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Authentication")
                .foregroundColor(.matrixNeon)
        } footer: {
            Text(authManager.isAuthenticated
                ? "Signed in to sync tasks across devices."
                : "Sign in to sync your tasks across devices. You can continue using Redo offline without signing in.")
                .foregroundColor(.matrixTextSecondary)
        }
        .listRowBackground(Color.matrixBackgroundSecondary)
    }

    private var identitySection: some View {
        Section {
            // User ID
            SettingsRow(
                icon: "person.circle",
                iconColor: .matrixNeon,
                title: "User ID",
                value: formatUserId(viewModel.userId),
                action: { copyToClipboard(viewModel.userId) }
            )

            // Device ID
            SettingsRow(
                icon: "iphone",
                iconColor: .matrixCyan,
                title: "Device ID",
                value: formatDeviceId(viewModel.deviceId),
                action: { copyToClipboard(viewModel.deviceId) }
            )

            // Public Key
            if let publicKey = try? keychain.loadPublicKey() {
                SettingsRow(
                    icon: "key",
                    iconColor: .matrixAmber,
                    title: "Public Key",
                    value: formatKey(publicKey),
                    action: { copyToClipboard(publicKey) }
                )
            }
        } header: {
            Text("Identity")
                .foregroundColor(.matrixNeon)
        } footer: {
            Text("Your cryptographic identity. Tap to copy.")
                .foregroundColor(.matrixTextSecondary)
        }
        .listRowBackground(Color.matrixBackgroundSecondary)
    }

    private var dataManagementSection: some View {
        Section {
            // Export
            Button(action: exportData) {
                SettingsRowContent(
                    icon: "square.and.arrow.up",
                    iconColor: .matrixSuccess,
                    title: "Export Data",
                    value: nil
                )
            }

            // Import
            Button(action: { showingImportSheet = true }) {
                SettingsRowContent(
                    icon: "square.and.arrow.down",
                    iconColor: .matrixInfo,
                    title: "Import Data",
                    value: nil
                )
            }

            // Clear All Data
            Button(action: { showingClearDataConfirmation = true }) {
                SettingsRowContent(
                    icon: "trash",
                    iconColor: .matrixError,
                    title: "Clear All Data",
                    value: nil
                )
            }
        } header: {
            Text("Data Management")
                .foregroundColor(.matrixNeon)
        } footer: {
            Text("Export your tasks as JSON or import from backup.")
                .foregroundColor(.matrixTextSecondary)
        }
        .listRowBackground(Color.matrixBackgroundSecondary)
    }

    private var syncSection: some View {
        Section {
            // Sync Status
            HStack {
                Image(systemName: syncStatusIcon)
                    .foregroundColor(syncStatusColor)

                Text("Sync Status")
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                Text(syncStatusText)
                    .foregroundColor(syncStatusColor)
            }

            // Last Sync (placeholder)
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.matrixTextSecondary)

                Text("Last Sync")
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                Text("Never")
                    .foregroundColor(.matrixTextSecondary)
            }
        } header: {
            Text("Synchronization")
                .foregroundColor(.matrixNeon)
        } footer: {
            Text("Cloud sync requires Google OAuth authentication.")
                .foregroundColor(.matrixTextSecondary)
        }
        .listRowBackground(Color.matrixBackgroundSecondary)
    }

    private var aboutSection: some View {
        Section {
            // Show Onboarding
            Button(action: { showingOnboarding = true }) {
                SettingsRowContent(
                    icon: "info.circle",
                    iconColor: .matrixNeon,
                    title: "Show Onboarding",
                    value: nil
                )
            }

            // Version
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(.matrixNeon)

                Text("Version")
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                Text("0.1.0 (Beta)")
                    .foregroundColor(.matrixTextSecondary)
            }

            // Protocol Version
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.matrixCyan)

                Text("Protocol")
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                Text("v1")
                    .foregroundColor(.matrixTextSecondary)
            }

            // Event Sourcing
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.matrixAmber)

                Text("Architecture")
                    .foregroundColor(.matrixTextPrimary)

                Spacer()

                Text("Event Sourcing")
                    .foregroundColor(.matrixTextSecondary)
            }
        } header: {
            Text("About")
                .foregroundColor(.matrixNeon)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Redo iOS - Local-first task management")
                Text("Built with SwiftUI and lessons from web & Android")
                Text("© 2025 Vision Salient")
            }
            .font(.matrixCaption2)
            .foregroundColor(.matrixTextSecondary)
        }
        .listRowBackground(Color.matrixBackgroundSecondary)
    }

    // MARK: - Actions

    private func signOut() {
        do {
            try authManager.signOut()
            HapticManager.shared.success()
        } catch {
            viewModel.errorMessage = "Failed to sign out: \(error.localizedDescription)"
            HapticManager.shared.error()
        }
    }

    private func exportData() {
        do {
            exportedJSON = try viewModel.exportData()
            showingExportSheet = true
        } catch {
            viewModel.errorMessage = "Failed to export: \(error.localizedDescription)"
        }
    }

    private func handleImport() {
        guard !importText.isEmpty else { return }

        Task {
            do {
                try await viewModel.importData(importText)
                showingImportSheet = false
                importText = ""
            } catch {
                viewModel.errorMessage = "Failed to import: \(error.localizedDescription)"
            }
        }
    }

    private func clearAllData() {
        Task {
            do {
                let storage = ChangeLogStorage()
                try storage.deleteAllChanges(userId: viewModel.userId)
                try await viewModel.reconstructState()
            } catch {
                viewModel.errorMessage = "Failed to clear data: \(error.localizedDescription)"
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text

        // Show feedback (haptic + visual indicator would be better)
        print("Copied to clipboard: \(text.prefix(20))...")
    }

    // MARK: - Helpers

    private func formatUserId(_ userId: String) -> String {
        "\(userId.prefix(8))...\(userId.suffix(4))"
    }

    private func formatDeviceId(_ deviceId: String) -> String {
        "\(deviceId.prefix(12))..."
    }

    private func formatKey(_ key: String) -> String {
        "\(key.prefix(8))...\(key.suffix(8))"
    }

    private var syncStatusIcon: String {
        switch viewModel.syncStatus {
        case .idle: return "cloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "cloud.fill"
        case .failed: return "cloud.slash"
        }
    }

    private var syncStatusColor: Color {
        switch viewModel.syncStatus {
        case .idle: return .matrixTextSecondary
        case .syncing: return .matrixNeon
        case .synced: return .matrixSuccess
        case .failed: return .matrixError
        }
    }

    private var syncStatusText: String {
        switch viewModel.syncStatus {
        case .idle: return "Offline"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .failed(let error): return "Failed: \(error)"
        }
    }
}

// MARK: - Supporting Views

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(icon: icon, iconColor: iconColor, title: title, value: value)
        }
    }
}

struct SettingsRowContent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(title)
                .foregroundColor(.matrixTextPrimary)

            Spacer()

            if let value = value {
                Text(value)
                    .foregroundColor(.matrixTextSecondary)
                    .font(.matrixCallout)
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.matrixTextSecondary)
                .font(.caption)
        }
    }
}

// MARK: - Export View

struct ExportView: View {
    let json: String

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                VStack(spacing: .matrixSpacingLarge) {
                    // Instructions
                    Text("Share or copy this JSON to backup your data.")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding()

                    // JSON Preview
                    ScrollView {
                        Text(json)
                            .font(.matrixCaption)
                            .foregroundColor(.matrixTextPrimary)
                            .padding()
                            .background(Color.matrixBackgroundSecondary)
                            .cornerRadius(.matrixCornerRadius)
                            .matrixBorder()
                    }

                    // Actions
                    HStack(spacing: .matrixSpacingMedium) {
                        Button(action: {
                            UIPasteboard.general.string = json
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.matrixHeadline)
                                .foregroundColor(.matrixBackground)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.matrixNeon)
                                .cornerRadius(.matrixCornerRadius)
                        }

                        ShareLink(item: json) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.matrixHeadline)
                                .foregroundColor(.matrixNeon)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.matrixBackgroundSecondary)
                                .cornerRadius(.matrixCornerRadius)
                                .matrixBorder()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.matrixNeon)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Import View

struct ImportView: View {
    @Binding var importText: String
    let onImport: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                VStack(spacing: .matrixSpacingLarge) {
                    // Instructions
                    Text("Paste your exported JSON below to restore your data.")
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding()

                    // Text Editor
                    TextEditor(text: $importText)
                        .font(.matrixCaption)
                        .foregroundColor(.matrixTextPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.matrixBackgroundSecondary)
                        .cornerRadius(.matrixCornerRadius)
                        .matrixBorder()

                    // Import Button
                    Button(action: {
                        onImport()
                    }) {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                            .font(.matrixHeadline)
                            .foregroundColor(.matrixBackground)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(importText.isEmpty ? Color.matrixTextSecondary : Color.matrixNeon)
                            .cornerRadius(.matrixCornerRadius)
                            .neonGlow(color: importText.isEmpty ? .clear : .matrixNeon)
                    }
                    .disabled(importText.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.matrixTextSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        UIPasteboard.general.string.map { importText = $0 }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.matrixNeon)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
