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
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                GoalsMark(size: 60)
                Text("app.name")
                    .font(.system(size: 40, weight: .medium))
                    .tracking(-1.4)
                    .foregroundStyle(Theme.text)
                Text("welcome.subtitle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: 10) {
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
                .frame(height: 50)
                .clipShape(.rect(cornerRadius: 12))

                GoogleSignInButton {
                    Task { await signInWithGoogle() }
                }

                Button {
                    isShowingEmailForm = true
                } label: {
                    Label("auth.continueWithEmail", systemImage: "envelope")
                }
                .buttonStyle(AccentOutlineButtonStyle(height: 50))

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.accentText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A faint red bloom behind the mark, thinning into the ground.
        .background {
            ZStack {
                Theme.ground
                RadialGradient(
                    colors: [Theme.accentWell, .clear],
                    center: .init(x: 0.5, y: 0.08),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
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
