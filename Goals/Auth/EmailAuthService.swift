//
//  EmailAuthService.swift
//  Goals
//

import Foundation
import CryptoKit

enum EmailAuthError: LocalizedError {
    case accountAlreadyExists
    case accountNotFound
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .accountAlreadyExists:
            String(localized: "auth.error.accountExists", defaultValue: "An account with this email already exists.", bundle: AppLanguage.currentBundle)
        case .accountNotFound:
            String(localized: "auth.error.accountNotFound", defaultValue: "No account found for this email.", bundle: AppLanguage.currentBundle)
        case .invalidCredentials:
            String(localized: "auth.error.invalidCredentials", defaultValue: "Incorrect email or password.", bundle: AppLanguage.currentBundle)
        }
    }
}

/// Local-only email/password "auth". There is no backend: credentials are hashed with a
/// per-account random salt and stored in the Keychain purely to give the app a stable identity.
enum EmailAuthService {
    private struct StoredCredential: Codable {
        var id: UUID
        var displayName: String
        var salt: Data
        var hash: Data
    }

    private static func key(for email: String) -> String {
        "email." + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// App Store review has no way to pre-provision a local account on the reviewer's device,
    /// so signing in with these exact credentials auto-registers them on first attempt.
    private static let appReviewEmail = "appreview@example.com"
    private static let appReviewPassword = "Review2026!"

    private static func hash(password: String, salt: Data) -> Data {
        var digest = SHA256()
        digest.update(data: salt)
        digest.update(data: Data(password.utf8))
        return Data(digest.finalize())
    }

    static func register(email: String, password: String, displayName: String) throws -> AuthenticatedUser {
        let accountKey = key(for: email)
        guard KeychainStore.get(for: accountKey) == nil else {
            throw EmailAuthError.accountAlreadyExists
        }

        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }

        let credential = StoredCredential(
            id: UUID(),
            displayName: displayName,
            salt: salt,
            hash: hash(password: password, salt: salt)
        )
        let data = try JSONEncoder().encode(credential)
        KeychainStore.set(data, for: accountKey)

        return AuthenticatedUser(id: credential.id, displayName: displayName, email: email, provider: .email)
    }

    static func login(email: String, password: String) throws -> AuthenticatedUser {
        let accountKey = key(for: email)
        guard let data = KeychainStore.get(for: accountKey) else {
            if key(for: email) == key(for: appReviewEmail), password == appReviewPassword {
                return try register(email: appReviewEmail, password: appReviewPassword, displayName: "App Review")
            }
            throw EmailAuthError.accountNotFound
        }
        let credential = try JSONDecoder().decode(StoredCredential.self, from: data)
        guard hash(password: password, salt: credential.salt) == credential.hash else {
            throw EmailAuthError.invalidCredentials
        }
        return AuthenticatedUser(id: credential.id, displayName: credential.displayName, email: email, provider: .email)
    }
}
