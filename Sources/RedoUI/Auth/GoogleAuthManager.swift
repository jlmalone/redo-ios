import Foundation
import FirebaseAuth
import GoogleSignIn
import RedoCore

/// Manages Google OAuth authentication for Firebase
@MainActor
public class GoogleAuthManager: ObservableObject {
    @Published public var isAuthenticated = false
    @Published public var currentUser: User?
    @Published public var errorMessage: String?

    public static let shared = GoogleAuthManager()

    private init() {
        // Check if user is already authenticated
        if let firebaseUser = Auth.auth().currentUser {
            isAuthenticated = true
            currentUser = User(from: firebaseUser)
        }
    }

    // MARK: - Sign In

    /// Sign in with Google OAuth
    public func signInWithGoogle(presentingViewController: UIViewController) async throws {
        // Get the client ID from Firebase configuration
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Perform sign in
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController
        )

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }

        // Get access token
        let accessToken = result.user.accessToken.tokenString

        // Create Firebase credential
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        // Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)

        // Update state
        isAuthenticated = true
        currentUser = User(from: authResult.user)

        // Store OAuth tokens separately (NOT in crypto keychain)
        try await storeOAuthTokens(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: result.user.refreshToken.tokenString
        )
    }

    // MARK: - Sign Out

    /// Sign out from Google and Firebase
    public func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()

        isAuthenticated = false
        currentUser = nil

        // Clear OAuth tokens
        try clearOAuthTokens()
    }

    // MARK: - Token Management

    /// Store OAuth tokens separately from crypto keys
    /// CRITICAL: Google OAuth tokens are for Google APIs, NOT for crypto signing
    private func storeOAuthTokens(idToken: String, accessToken: String, refreshToken: String) async throws {
        let keychain = KeychainService()

        // Use separate keys from crypto keys
        try keychain.save(idToken, forKey: "googleIDToken")
        try keychain.save(accessToken, forKey: "googleAccessToken")
        try keychain.save(refreshToken, forKey: "googleRefreshToken")
    }

    private func clearOAuthTokens() throws {
        let keychain = KeychainService()

        try keychain.delete(forKey: "googleIDToken")
        try keychain.delete(forKey: "googleAccessToken")
        try keychain.delete(forKey: "googleRefreshToken")
    }

    /// Get current Google access token (for Google API calls)
    public func getGoogleAccessToken() async throws -> String {
        let keychain = KeychainService()

        if let token = try? keychain.load(forKey: "googleAccessToken") {
            // Check if token is still valid
            if try await isTokenValid(token) {
                return token
            }
        }

        // Token expired or missing, refresh it
        return try await refreshGoogleToken()
    }

    private func isTokenValid(_ token: String) async throws -> Bool {
        // Simple validation: check with Google tokeninfo endpoint
        let url = URL(string: "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=\(token)")!
        let (_, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse {
            return httpResponse.statusCode == 200
        }

        return false
    }

    private func refreshGoogleToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw AuthError.notSignedIn
        }

        // Refresh token
        try await user.refreshTokensIfNeeded()

        let newAccessToken = user.accessToken.tokenString

        // Store new token
        let keychain = KeychainService()
        try keychain.save(newAccessToken, forKey: "googleAccessToken")

        return newAccessToken
    }

    // MARK: - User Info

    /// Get Google OAuth subject ID (for Firebase user paths)
    /// This is SEPARATE from crypto userId
    public func getGoogleSubjectID() -> String? {
        return Auth.auth().currentUser?.uid
    }

    /// Get user email
    public func getUserEmail() -> String? {
        return Auth.auth().currentUser?.email
    }
}

// MARK: - User Model

public struct User: Identifiable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let photoURL: URL?

    init(from firebaseUser: FirebaseAuth.User) {
        self.id = firebaseUser.uid
        self.email = firebaseUser.email
        self.displayName = firebaseUser.displayName
        self.photoURL = firebaseUser.photoURL
    }
}

// MARK: - Auth Errors

public enum AuthError: LocalizedError {
    case missingClientID
    case missingIDToken
    case notSignedIn
    case tokenRefreshFailed

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Firebase client ID not found. Check GoogleService-Info.plist"
        case .missingIDToken:
            return "Failed to get ID token from Google Sign-In"
        case .notSignedIn:
            return "User is not signed in"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        }
    }
}

// MARK: - Keychain Extension for OAuth Tokens

extension KeychainService {
    func save(_ value: String, forKey key: String) throws {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    func load(forKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return value
    }

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
