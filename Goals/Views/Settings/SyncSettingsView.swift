//
//  SyncSettingsView.swift
//  Goals
//

import SwiftUI

/// The iCloud sync screen: the switch, whether it takes effect yet, the iCloud account state, and
/// when sync last ran. Pushed from the General section of Settings.
struct SyncSettingsView: View {
    @Environment(SyncMonitor.self) private var monitor
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isEnabled = SharedStore.isCloudSyncEnabled

    /// The value the store was built with this launch — the switch only bites on the next one.
    private let launchValue = SharedStore.isCloudSyncEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                CardGroup {
                    SwitchRow(label: "settings.icloudSync", icon: "icloud", isOn: $isEnabled)
                }

                if isEnabled != launchValue {
                    note("settings.sync.restartHint", icon: "arrow.clockwise")
                }

                if isEnabled {
                    statusCard
                }

                Text("settings.sync.explainer")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .screenGround()
        .navigationTitle("settings.sync.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .onChange(of: isEnabled) { _, value in
            SharedStore.isCloudSyncEnabled = value
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { monitor.refreshAccountState() }
        }
        .task { monitor.refreshAccountState() }
    }

    // MARK: - Status

    private var statusCard: some View {
        CardGroup {
            ValueRow(label: "settings.sync.account", icon: accountIcon) {
                Text(accountText)
                    .font(Theme.Typo.row)
                    .foregroundStyle(accountIsWarning ? Theme.accentText : Theme.text)
            }

            if accountState == .noAccount {
                RowDivider()
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("settings.sync.openSettings")
                        .font(Theme.Typo.rowEmphasis)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 13)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            RowDivider()

            ValueRow(label: "settings.sync.lastSynced", icon: "clock.arrow.circlepath") {
                Text(lastSyncedText)
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }

            if monitor.isRetrying && monitor.lastErrorMessage == nil {
                RowDivider()
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.textFaint)
                    Text("settings.sync.retrying")
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }

            if let error = monitor.lastErrorMessage {
                RowDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.sync.error")
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.textFaint)
                    Text(error)
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }
        }
    }

    private var accountState: SyncMonitor.AccountState { monitor.accountState }

    private var accountIsWarning: Bool {
        accountState == .noAccount || accountState == .restricted
    }

    private var accountIcon: String {
        switch accountState {
        case .available: "checkmark.icloud"
        case .noAccount, .restricted: "exclamationmark.icloud"
        case .unknown: "icloud"
        }
    }

    private var accountText: String {
        let key: String.LocalizationValue = switch accountState {
        case .available: "settings.sync.account.active"
        case .noAccount: "settings.sync.account.none"
        case .restricted: "settings.sync.account.restricted"
        case .unknown: "settings.sync.account.checking"
        }
        return String(localized: key, bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
    }

    private var lastSyncedText: String {
        if monitor.isSyncing {
            return String(localized: "settings.sync.syncing", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        }
        guard let date = monitor.lastSync else {
            return String(localized: "settings.sync.never", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        }
        return date.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale))
    }

    private func note(_ key: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textFaint)
            Text(key)
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.hairlineSoft, lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack {
        SyncSettingsView()
            .environment(SyncMonitor())
    }
}
