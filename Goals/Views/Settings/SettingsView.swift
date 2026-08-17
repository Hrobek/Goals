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
    @State private var isShowingLanguagePicker = false
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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    ScreenTitle("settings.title")

                    VStack(alignment: .leading, spacing: Theme.Space.section) {
                        proSection
                        appearanceSection
                        generalSection
                        supportSection
                        accountSection
                    }
                    .padding(.horizontal, Theme.Space.screen)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .tabBarClearance()
            .screenGround()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: isAnalyticsEnabled) { _, isEnabled in
                Analytics.isEnabled = isEnabled
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView(source: .settings)
            }
            .sheet(isPresented: $isShowingLanguagePicker) {
                LanguagePickerSheet(selection: language)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var proSection: some View {
        if purchaseManager.isProUnlocked {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accentWellText)
                Text("settings.pro.unlocked")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(15)
            .background(Theme.accentWell, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.accentWellBorder, lineWidth: 1)
            }
        } else {
            VStack(spacing: 10) {
                Button { isShowingPaywall = true } label: {
                    Label("settings.pro.upgrade", systemImage: "infinity")
                }
                .buttonStyle(AccentButtonStyle())

                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    Text("paywall.restore")
                        .font(Theme.Typo.captionEmphasis)
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appearanceSection: some View {
        LabeledSection("settings.appearance") {
            SegmentStrip(
                options: AppearanceMode.allCases,
                selection: appearanceMode,
                title: { $0.localizedName },
                icon: { mode in
                    switch mode {
                    case .system: "iphone"
                    case .light: "sun.max"
                    case .dark: "moon"
                    }
                }
            )
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup {
                DisclosureRow(
                    label: "settings.language",
                    icon: "character.bubble",
                    value: language.wrappedValue.localizedName
                ) {
                    isShowingLanguagePicker = true
                }
                RowDivider()
                SwitchRow(label: "settings.privacy.analytics", icon: "chart.pie", isOn: $isAnalyticsEnabled)
            }
            Text("settings.privacy.analytics.footer")
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textGhost)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var supportSection: some View {
        LabeledSection("settings.support") {
            CardGroup {
                NavigationLink {
                    FeedbackView()
                } label: {
                    linkRow(label: "settings.support.feedback", icon: "exclamationmark.bubble")
                }
                .buttonStyle(.plain)

                // Straight to the App Store's own review sheet rather than the in-app
                // StoreKit prompt: that one is rate-limited and may show nothing at all,
                // which would make the button look broken.
                if let url = AppReviewPrompt.writeReviewURL {
                    RowDivider()
                    Button {
                        openURL(url)
                    } label: {
                        linkRow(label: "settings.support.rate", icon: "star")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func linkRow(label: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 10)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textGhost)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
    }

    private var accountSection: some View {
        LabeledSection("settings.account") {
            CardGroup {
                if let user = session.currentUser {
                    ValueRow("settings.account.name", value: user.displayName)
                    RowDivider()
                    if let email = user.email {
                        ValueRow("settings.account.email", value: email)
                        RowDivider()
                    }
                }
                Button {
                    session.signOut()
                } label: {
                    Text("settings.account.signOut")
                        .font(Theme.Typo.rowEmphasis)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 13)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The language list, lifted out of the inline picker so the row can read like every other
/// disclosure row on the screen.
private struct LanguagePickerSheet: View {
    @Binding var selection: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                CardGroup {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, option in
                        if index > 0 { RowDivider() }
                        Button {
                            selection = option
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.localizedName)
                                    .font(Theme.Typo.row)
                                    .foregroundStyle(Theme.text)
                                Spacer(minLength: 10)
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.accentText)
                                }
                            }
                            .padding(.vertical, 13)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == selection ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(Theme.Space.screen)
            }
            .screenGround()
            .navigationTitle("settings.language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthSession())
        .environment(PurchaseManager())
}
