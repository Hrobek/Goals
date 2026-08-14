//
//  GoogleSignInService.swift
//  Goals
//

import Foundation
import CryptoKit
import AuthenticationServices
import UIKit

enum GoogleSignInError: LocalizedError {
    case notConfigured
    case cancelled
    case missingIDToken
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "auth.error.googleNotConfigured", defaultValue: "Google Sign-In isn't set up for this build yet.", bundle: AppLanguage.currentBundle)
        case .cancelled:
            String(localized: "auth.error.cancelled", defaultValue: "Sign in was cancelled.", bundle: AppLanguage.currentBundle)
        case .missingIDToken:
            String(localized: "auth.error.googleMissingToken", defaultValue: "Google didn't return an ID token.", bundle: AppLanguage.currentBundle)
        case .invalidResponse:
            String(localized: "auth.error.googleInvalidResponse", defaultValue: "Google returned an unexpected response.", bundle: AppLanguage.currentBundle)
        }
    }
}

protocol GoogleAuthProviding {
    /// Whether the app is ready to attempt a real Google sign-in (client ID present).
    var isConfigured: Bool { get }
    @MainActor func signIn() async throws -> AuthenticatedUser
}

/// Google sign-in over plain OAuth 2.0 with PKCE, driven by `ASWebAuthenticationSession`.
///
/// Deliberately no `GoogleSignIn-iOS` SDK: this needs no Swift Package, no `URL Types` entry
/// (the session intercepts its own callback scheme), and no client secret — only the iOS OAuth
/// client ID, which `GoogleAuthConfiguration` reads from the bundle. It is the flow Google
/// documents for native apps ("OAuth 2.0 for Mobile & Desktop Apps").
final class GoogleSignInService: NSObject, GoogleAuthProviding {
    private let configuration = GoogleAuthConfiguration.current
    /// Held for the lifetime of the flow — a released session closes the browser sheet.
    private var session: ASWebAuthenticationSession?

    var isConfigured: Bool { configuration != nil }

    @MainActor
    func signIn() async throws -> AuthenticatedUser {
        guard let configuration else { throw GoogleSignInError.notConfigured }

        let verifier = Self.randomURLSafeString()
        let state = Self.randomURLSafeString()
        let authorizationURL = try Self.authorizationURL(configuration: configuration, verifier: verifier, state: state)

        let callbackURL = try await authenticate(url: authorizationURL, scheme: configuration.reversedClientID)
        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let idToken = try await Self.exchange(code: code, verifier: verifier, configuration: configuration)
        return try Self.user(fromIDToken: idToken)
    }

    // MARK: - Browser step

    @MainActor
    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    let isCancel = nsError.domain == ASWebAuthenticationSessionError.errorDomain
                        && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    continuation.resume(throwing: isCancel ? GoogleSignInError.cancelled : error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInError.invalidResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Shared cookies, so an already signed-in Google account is one tap.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    // MARK: - OAuth plumbing

    private static func authorizationURL(
        configuration: GoogleAuthConfiguration,
        verifier: String,
        state: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else { throw GoogleSignInError.invalidResponse }
        return url
    }

    private static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "error" })?.value != nil {
            throw GoogleSignInError.cancelled
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.invalidResponse
        }
        return code
    }

    private static func exchange(
        code: String,
        verifier: String,
        configuration: GoogleAuthConfiguration
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleSignInError.invalidResponse
        }

        struct TokenResponse: Decodable {
            let idToken: String?

            enum CodingKeys: String, CodingKey {
                case idToken = "id_token"
            }
        }

        guard let idToken = try JSONDecoder().decode(TokenResponse.self, from: data).idToken else {
            throw GoogleSignInError.missingIDToken
        }
        return idToken
    }

    /// The ID token comes straight from Google's token endpoint over TLS, so the claims are read
    /// for display only — no signature check is needed for a local-only identity.
    private static func user(fromIDToken token: String) throws -> AuthenticatedUser {
        let segments = token.split(separator: ".")
        guard segments.count == 3, let payload = base64URLDecoded(String(segments[1])) else {
            throw GoogleSignInError.invalidResponse
        }

        struct Claims: Decodable {
            let sub: String
            let email: String?
            let name: String?
            let givenName: String?

            enum CodingKeys: String, CodingKey {
                case sub, email, name
                case givenName = "given_name"
            }
        }

        let claims = try JSONDecoder().decode(Claims.self, from: payload)
        let fallback = String(localized: "auth.googleUserFallback", defaultValue: "Google User", bundle: AppLanguage.currentBundle)
        let displayName = claims.name ?? claims.givenName ?? claims.email ?? fallback

        return AuthenticatedUser(
            id: .stable(for: "google:\(claims.sub)"),
            displayName: displayName,
            email: claims.email,
            provider: .google
        )
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URLEncoded(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

extension GoogleSignInService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
