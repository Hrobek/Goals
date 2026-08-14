//
//  AuthSession.swift
//  Goals
//

import Foundation
import Observation
import AuthenticationServices

enum AppleSignInError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        String(localized: "auth.error.appleMissingCredential", defaultValue: "Apple didn't return an account credential.", bundle: AppLanguage.currentBundle)
    }
}

/// Holds the "who's using the app" identity. This is intentionally local-only — there is no
/// account sync, so signing out on one device has no effect anywhere else.
@MainActor
@Observable
final class AuthSession {
    private static let storageKey = "Goals.currentUser"

    private(set) var currentUser: AuthenticatedUser?

    let googleService: GoogleAuthProviding = GoogleSignInService()

    var isAuthenticated: Bool { currentUser != nil }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let user = try? JSONDecoder().decode(AuthenticatedUser.self, from: data) {
            currentUser = user
        }
    }

    func signIn(as user: AuthenticatedUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func completeAppleSignIn(with authorization: ASAuthorization) throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleSignInError.missingCredential
        }

        // Apple's `user` is a stable per-app id, but not a UUID — hash it so repeat sign-ins on
        // this device resolve to the same identity.
        let id = UUID.stable(for: "apple:\(credential.user)")
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let displayName = name.isEmpty ? String(localized: "auth.appleUserFallback", defaultValue: "Apple User", bundle: AppLanguage.currentBundle) : name

        signIn(as: AuthenticatedUser(id: id, displayName: displayName, email: credential.email, provider: .apple))
    }

    func signInWithGoogle() async throws {
        let user = try await googleService.signIn()
        signIn(as: user)
    }

    func register(email: String, password: String, displayName: String) throws {
        let user = try EmailAuthService.register(email: email, password: password, displayName: displayName)
        signIn(as: user)
    }

    func login(email: String, password: String) throws {
        let user = try EmailAuthService.login(email: email, password: password)
        signIn(as: user)
    }
}
