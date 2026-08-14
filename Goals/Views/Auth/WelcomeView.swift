//
//  WelcomeView.swift
//  Goals
//

import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    @State private var isShowingEmailForm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("app.name")
                    .font(.largeTitle.bold())
                Text("welcome.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                // Black on light, white on dark — Apple's own guideline, and the black button
                // disappears into a dark background. The `id` forces the wrapped UIKit button to
                // be rebuilt: it keeps the style it was created with and otherwise stays black
                // after switching appearance in Settings.
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .id(colorScheme)
                .frame(height: 48)

                GoogleSignInButton {
                    Task { await signInWithGoogle() }
                }

                Button {
                    isShowingEmailForm = true
                } label: {
                    Label("auth.continueWithEmail", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $isShowingEmailForm) {
            EmailAuthFormView()
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            do {
                try session.completeAppleSignIn(with: authorization)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain, nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() async {
        errorMessage = nil
        do {
            try await session.signInWithGoogle()
        } catch GoogleSignInError.cancelled {
            // Closing the sheet isn't a failure — the Apple button treats it the same way.
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AuthSession())
}
