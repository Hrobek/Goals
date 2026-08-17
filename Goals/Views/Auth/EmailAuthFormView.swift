//
//  EmailAuthFormView.swift
//  Goals
//

import SwiftUI

struct EmailAuthFormView: View {
    private enum Mode: String, CaseIterable {
        case signIn, register

        var localizedName: String {
            switch self {
            case .signIn: String(localized: "auth.mode.signIn", defaultValue: "Sign In", bundle: AppLanguage.currentBundle)
            case .register: String(localized: "auth.mode.register", defaultValue: "Register", bundle: AppLanguage.currentBundle)
            }
        }
    }

    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    private var passwordsMismatch: Bool {
        mode == .register && !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword
    }

    private var isValid: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        guard mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard mode == .signIn || password == confirmPassword else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("auth.mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                Section {
                    if mode == .register {
                        TextField("auth.field.name", text: $displayName)
                            .textContentType(.name)
                    }
                    TextField("auth.field.email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    // Not SwiftUI's `SecureField` — see `ThemedSecureField` for the two things it
                    // gets wrong here (the white last bullet, and the confirmation row showing the
                    // password in the clear).
                    ThemedSecureField(
                        placeholder: String(localized: "auth.field.password", defaultValue: "Password", bundle: AppLanguage.currentBundle),
                        text: $password,
                        textContentType: mode == .register ? .newPassword : .password,
                        onSubmit: { if isValid { submit() } }
                    )
                    if mode == .register {
                        ThemedSecureField(
                            placeholder: String(localized: "auth.field.confirmPassword", defaultValue: "Confirm Password", bundle: AppLanguage.currentBundle),
                            text: $confirmPassword,
                            textContentType: nil,
                            onSubmit: { if isValid { submit() } }
                        )
                    }
                }
                // Switching mode adds and removes rows, and SwiftUI happily recycles the text field
                // underneath a row that stayed put — which is how the confirmation field ends up
                // reusing a plain one and showing the password in the clear. A per-mode identity
                // rebuilds the section instead of rearranging it.
                .id(mode)

                if passwordsMismatch {
                    Text("auth.error.passwordMismatch")
                        .foregroundStyle(Theme.accentText)
                        .font(Theme.Typo.footnote)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.accentText)
                        .font(Theme.Typo.footnote)
                }
            }
            .themedList()
            // Signing in and registering are two different forms that happen to share a screen —
            // switching between them starts the other one empty rather than carrying half-typed
            // credentials (and a stale error) across.
            .onChange(of: mode) { _, _ in
                displayName = ""
                email = ""
                password = ""
                confirmPassword = ""
                errorMessage = nil
            }
            .navigationTitle(mode.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.continue") { submit() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func submit() {
        errorMessage = nil
        do {
            switch mode {
            case .signIn:
                try session.login(email: email, password: password)
            case .register:
                try session.register(email: email, password: password, displayName: displayName)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    EmailAuthFormView()
        .environment(AuthSession())
}
