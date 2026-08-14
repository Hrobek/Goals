//
//  SettingsView.swift
//  Goals
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthSession.self) private var session
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.deviceDefault.rawValue

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var language: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? .deviceDefault },
            set: { languageRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.appearance") {
                    Picker("settings.appearance", selection: appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("settings.language") {
                    Picker("settings.language", selection: language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.localizedName).tag(language)
                        }
                    }
                    .labelsHidden()
                }

                Section("settings.support") {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Label("settings.support.feedback", systemImage: "exclamationmark.bubble")
                    }
                }

                Section("settings.account") {
                    if let user = session.currentUser {
                        LabeledContent("settings.account.name", value: user.displayName)
                        if let email = user.email {
                            LabeledContent("settings.account.email", value: email)
                        }
                    }
                    Button("settings.account.signOut", role: .destructive) {
                        session.signOut()
                    }
                }
            }
            .navigationTitle("settings.title")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthSession())
}
