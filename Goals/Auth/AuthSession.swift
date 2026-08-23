//
//  AuthSession.swift
//  Goals
//

import Foundation
import Observation
import AuthenticationServices
import SwiftData
import WidgetKit

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
    /// Pre-App-Group storage key, kept only so `migrateLegacyStandardDefaultsIfNeeded` can find and
    /// retire a session written before the identity moved into the shared suite.
    private static let legacyStorageKey = "Goals.currentUser"

    private(set) var currentUser: AuthenticatedUser?

    let googleService: GoogleAuthProviding = GoogleSignInService()

    var isAuthenticated: Bool { currentUser != nil }

    init() {
        migrateLegacyStandardDefaultsIfNeeded()
        currentUser = CurrentUser.current
    }

    func signIn(as user: AuthenticatedUser, context: ModelContext? = nil) {
        currentUser = user
        CurrentUser.set(user)
        if let context {
            OwnershipMigration.claimOrphanData(for: user.id, context: context)
            Category.migrateDefaultKeysIfNeeded(context: context, for: user.id)
            Category.seedDefaultsIfNeeded(context: context, for: user.id)
        }
        // The home screen widget caches the previous identity's goals until its next redraw —
        // without this, a quick-action tap right after switching accounts could still write to
        // whichever goal the stale widget is showing.
        WidgetCenter.shared.reloadAllTimelines()
    }

    func signOut() {
        currentUser = nil
        CurrentUser.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// One-time carry-over: identity used to live in `UserDefaults.standard`, which the widget
    /// can't see. Runs before the App Group is consulted so an already-logged-in user isn't
    /// spuriously signed out by the switch.
    private func migrateLegacyStandardDefaultsIfNeeded() {
        guard CurrentUser.current == nil,
              let data = UserDefaults.standard.data(forKey: Self.legacyStorageKey),
              let user = try? JSONDecoder().decode(AuthenticatedUser.self, from: data)
        else { return }
        CurrentUser.set(user)
        UserDefaults.standard.removeObject(forKey: Self.legacyStorageKey)
    }

    func completeAppleSignIn(with authorization: ASAuthorization, context: ModelContext? = nil) throws {
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

        signIn(as: AuthenticatedUser(id: id, displayName: displayName, email: credential.email, provider: .apple), context: context)
    }

    func signInWithGoogle(context: ModelContext? = nil) async throws {
        let user = try await googleService.signIn()
        signIn(as: user, context: context)
    }

    func register(email: String, password: String, displayName: String, context: ModelContext? = nil) throws {
        let user = try EmailAuthService.register(email: email, password: password, displayName: displayName)
        signIn(as: user, context: context)
    }

    func login(email: String, password: String, context: ModelContext? = nil) throws {
        let user = try EmailAuthService.login(email: email, password: password)
        signIn(as: user, context: context)
    }
}
