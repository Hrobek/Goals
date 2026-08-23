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
    @Environment(PurchaseManager.self) private var purchaseManager
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
    /// doesn't explain what they were showing — and by the occasional promo.
    @State private var isShowingPaywall = false
    /// Which of the two put it up, so the funnel can tell them apart.
    @State private var paywallSource: PaywallSource = .widget

    /// Shown once, after the first sign-in on this device. Per device rather than per account on
    /// purpose: nothing syncs, so signing in here is a fresh start however old the account is.
    @AppStorage("Goals.hasSeenFirstRunWelcome") private var hasSeenFirstRunWelcome = false
    @State private var isShowingFirstRunWelcome = false
    /// Set when the welcome sheet's primary button is tapped, consumed once that sheet has fully
    /// dismissed — presenting Add Goal only then avoids stacking it on the outgoing sheet.
    @State private var wantsAddGoalAfterWelcome = false
    /// Drives `GoalsListView` straight into its Add Goal sheet for a new user's first goal.
    @State private var addGoalTrigger = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .deviceDefault
    }

    var body: some View {
        Group {
            if let userId = session.currentUser?.id {
                MainTabView(userId: userId, selection: $selectedTab, todayPath: $todayPath, addGoalTrigger: $addGoalTrigger)
            } else {
                WelcomeView()
            }
        }
        .environment(\.locale, language.locale)
        .id(languageRaw)
        .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .default).colorScheme)
        // One tint for everything the app doesn't draw itself — switches, date pickers, the text
        // cursor, the menus. Set once here so no system control is left on the stock blue.
        .tint(Theme.accent)
        // …and the same choice again, one layer down: see `AppearanceMode.applyToWindows`.
        .onChange(of: appearanceModeRaw, initial: true) { _, raw in
            AppearanceMode.applyToWindows(AppearanceMode(rawValue: raw) ?? .default)
        }
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
        // or a language switch mid-sheet still gets its turn. Add Goal is also fired from here,
        // once this sheet is actually gone, rather than from the button action — presenting a new
        // sheet while this one is still animating out gets silently dropped.
        .sheet(isPresented: $isShowingFirstRunWelcome, onDismiss: {
            hasSeenFirstRunWelcome = true
            if wantsAddGoalAfterWelcome {
                wantsAddGoalAfterWelcome = false
                addGoalTrigger = true
            }
        }) {
            FirstRunWelcomeView {
                selectedTab = .goals
                wantsAddGoalAfterWelcome = true
            }
        }
        // Every visit rebuilds the schedule, which is also what pushes the "haven't seen you"
        // nudge further into the future.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                AppReviewPrompt.recordFirstLaunchIfNeeded()
                if let userId = session.currentUser?.id {
                    Task { await NotificationScheduler.syncAll(context: modelContext, userId: userId) }
                }
                // One after the other: whichever of the two goes first, the second one sees it on
                // screen and stands down rather than stacking a second sheet on top.
                Task {
                    await requestReviewIfEarned()
                    await showProPromoIfEarned()
                }
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
                paywallSource = .widget
                isShowingPaywall = true
            default:
                break
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(source: paywallSource)
        }
    }

    /// The promo waits for the same quiet moment the rating prompt does — nothing else on screen,
    /// the launch settled — and `ProPromoPrompt` decides whether this is one of the rare turns it
    /// gets at all.
    private func showProPromoIfEarned() async {
        guard session.isAuthenticated, !isShowingFirstRunWelcome, !isShowingPaywall else { return }

        guard let userId = session.currentUser?.id else { return }
        let checkInDescriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.ownerId == userId })
        let checkInCount = (try? modelContext.fetchCount(checkInDescriptor)) ?? 0
        guard ProPromoPrompt.shouldShow(isProUnlocked: purchaseManager.isProUnlocked, checkInCount: checkInCount) else { return }

        try? await Task.sleep(for: .seconds(2))
        guard scenePhase == .active, session.isAuthenticated, !isShowingFirstRunWelcome, !isShowingPaywall else { return }
        // Entitlements load asynchronously, so the check is worth repeating once they have.
        guard !purchaseManager.isProUnlocked else { return }

        ProPromoPrompt.recordShown()
        paywallSource = .promo
        isShowingPaywall = true
    }

    /// The rating prompt only makes sense on top of the app itself, so it waits out the welcome
    /// sheet and the paywall — and gives the launch a couple of seconds so it doesn't land while
    /// the first screen is still drawing.
    private func requestReviewIfEarned() async {
        guard session.isAuthenticated, !isShowingFirstRunWelcome, !isShowingPaywall else { return }

        guard let userId = session.currentUser?.id else { return }
        let checkInDescriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.ownerId == userId })
        let checkInCount = (try? modelContext.fetchCount(checkInDescriptor)) ?? 0
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
