//
//  RootView.swift
//  Goals
//

import SwiftUI
import SwiftData
import StoreKit
import WidgetKit

struct RootView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.default.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.deviceDefault.rawValue

    /// Lives above the `.id(languageRaw)` rebuild, so switching the language keeps the user
    /// on the tab they were on (Settings) instead of dropping them back on the goals list.
    @State private var selectedTab: MainTab = .today
    /// Owned here so a widget tap can push a goal onto the Today stack.
    @State private var todayPath = NavigationPath()
    /// Raised by the locked Pro widgets, which link here rather than dropping you on a screen that
    /// doesn't explain what they were showing.
    @State private var isShowingPaywall = false

    /// Shown once, after the first sign-in on this device. Per device rather than per account on
    /// purpose: nothing syncs, so signing in here is a fresh start however old the account is.
    @AppStorage("Goals.hasSeenFirstRunWelcome") private var hasSeenFirstRunWelcome = false
    @State private var isShowingFirstRunWelcome = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .deviceDefault
    }

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView(selection: $selectedTab, todayPath: $todayPath)
            } else {
                WelcomeView()
            }
        }
        .environment(\.locale, language.locale)
        .id(languageRaw)
        .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .default).colorScheme)
        // Widgets read the language from the App Group, so the choice has to be pushed across and
        // the home screen redrawn — otherwise the app switches to Czech and its widgets don't.
        .onChange(of: languageRaw, initial: true) { _, _ in
            if AppLanguage.syncSharedCopy() {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .onChange(of: session.isAuthenticated, initial: true) { _, isAuthenticated in
            guard isAuthenticated, !hasSeenFirstRunWelcome else { return }
            isShowingFirstRunWelcome = true
        }
        // Marked as seen on dismissal rather than on presentation, so a welcome killed by a crash
        // or a language switch mid-sheet still gets its turn.
        .sheet(isPresented: $isShowingFirstRunWelcome, onDismiss: { hasSeenFirstRunWelcome = true }) {
            FirstRunWelcomeView { selectedTab = .goals }
        }
        // Every visit rebuilds the schedule, which is also what pushes the "haven't seen you"
        // nudge further into the future.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                AppReviewPrompt.recordFirstLaunchIfNeeded()
                Task { await NotificationScheduler.syncAll(context: modelContext) }
                Task { await requestReviewIfEarned() }
            case .background:
                // Whatever changed in the app, the home screen should show it.
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
        .onOpenURL { url in
            guard url.scheme == "goals" else { return }
            switch url.host {
            case "goal":
                guard let id = UUID(uuidString: url.lastPathComponent) else { return }
                selectedTab = .today
                todayPath = NavigationPath()
                todayPath.append(id)
            case "pro":
                isShowingPaywall = true
            default:
                break
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(source: .widget)
        }
    }

    /// The rating prompt only makes sense on top of the app itself, so it waits out the welcome
    /// sheet and the paywall — and gives the launch a couple of seconds so it doesn't land while
    /// the first screen is still drawing.
    private func requestReviewIfEarned() async {
        guard session.isAuthenticated, !isShowingFirstRunWelcome, !isShowingPaywall else { return }

        let checkInCount = (try? modelContext.fetchCount(FetchDescriptor<CheckIn>())) ?? 0
        guard AppReviewPrompt.shouldRequest(checkInCount: checkInCount) else { return }

        try? await Task.sleep(for: .seconds(2))
        guard scenePhase == .active, !isShowingFirstRunWelcome, !isShowingPaywall else { return }

        AppReviewPrompt.recordRequest()
        requestReview()
    }
}

#Preview {
    RootView()
        .environment(AuthSession())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
