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
                    SecureField("auth.field.password", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                    if mode == .register {
                        SecureField("auth.field.confirmPassword", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                }

                if passwordsMismatch {
                    Text("auth.error.passwordMismatch")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
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
