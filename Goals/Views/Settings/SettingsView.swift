//
//  SettingsView.swift
//  Goals
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthSession.self) private var session
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.openURL) private var openURL
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.default.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.deviceDefault.rawValue

    @State private var isShowingPaywall = false
    // Not `@AppStorage`: the flag lives in the App Group so the widget honours it too, and
    // `Analytics` stays the only place that knows the key.
    @State private var isAnalyticsEnabled = Analytics.isEnabled

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .default },
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
                Section {
                    if purchaseManager.isProUnlocked {
                        Label("settings.pro.unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            isShowingPaywall = true
                        } label: {
                            Label("settings.pro.upgrade", systemImage: "infinity.circle.fill")
                        }
                        Button {
                            Task { await purchaseManager.restorePurchases() }
                        } label: {
                            Text("paywall.restore")
                        }
                    }
                }

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

                Section {
                    Toggle("settings.privacy.analytics", isOn: $isAnalyticsEnabled)
                } header: {
                    Text("settings.privacy")
                } footer: {
                    Text("settings.privacy.analytics.footer")
                }

                Section("settings.support") {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Label("settings.support.feedback", systemImage: "exclamationmark.bubble")
                    }

                    // Straight to the App Store's own review sheet rather than the in-app
                    // StoreKit prompt: that one is rate-limited and may show nothing at all,
                    // which would make the button look broken.
                    if let url = AppReviewPrompt.writeReviewURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("settings.support.rate", systemImage: "star")
                        }
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
            .onChange(of: isAnalyticsEnabled) { _, isEnabled in
                Analytics.isEnabled = isEnabled
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView(source: .settings)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthSession())
        .environment(PurchaseManager())
}
