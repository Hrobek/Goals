//
//  RootView.swift
//  Goals
//

import SwiftUI
import SwiftData
import WidgetKit

struct RootView: View {
    @Environment(Profile.self) private var profile
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.default.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.deviceDefault.rawValue

    /// Lives above the `.id(languageRaw)` rebuild, so switching the language keeps the user
    /// on the tab they were on (Settings) instead of dropping them back on the goals list.
    @State private var selectedTab: MainTab = .today
    /// Owned here so a widget tap can push a goal onto the Today stack.
    @State private var todayPath = NavigationPath()
    /// Same, for the Habits tab — a habit widget tap pushes that habit's detail.
    @State private var habitsPath: [UUID] = []
    /// Raised by the locked Pro widgets, which link here rather than dropping you on a screen that
    /// doesn't explain what they were showing — and by the occasional promo.
    @State private var isShowingPaywall = false
    /// Which of the two put it up, so the funnel can tell them apart.
    @State private var paywallSource: PaywallSource = .widget

    @State private var isShowingOnboarding = false
    /// What the onboarding picker chose, applied once the onboarding cover has fully dismissed so
    /// the Add sheet isn't stacked on the outgoing one.
    @State private var pendingOnboardingAdd: OnboardingAdd?
    /// Drives the seeded Add Goal / Add Habit sheet after onboarding.
    @State private var onboardingAdd: OnboardingAdd?
    /// Kept only to satisfy `MainTabView`'s binding; no longer driven from here.
    @State private var addGoalTrigger = false

    enum OnboardingAdd: Identifiable {
        case goal(GoalTemplate?)
        case habit(HabitTemplate?)

        var id: String {
            switch self {
            case .goal(let template): "goal-\(template?.id ?? "custom")"
            case .habit(let template): "habit-\(template?.id ?? "custom")"
            }
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .deviceDefault
    }

    var body: some View {
        MainTabView(userId: profile.id, selection: $selectedTab, todayPath: $todayPath, habitsPath: $habitsPath, addGoalTrigger: $addGoalTrigger)
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
        .task {
            guard !FirstRunWelcomeStore.hasSeen(userId: profile.id) else { return }
            // A returning user - old account data adopted by `LocalProfile`, or an iCloud restore -
            // has already been onboarded; don't make them do it again.
            let goalCount = (try? modelContext.fetchCount(FetchDescriptor<Goal>())) ?? 0
            let habitCount = (try? modelContext.fetchCount(FetchDescriptor<Habit>())) ?? 0
            if goalCount > 0 || habitCount > 0 {
                FirstRunWelcomeStore.markSeen(userId: profile.id)
                return
            }
            isShowingOnboarding = true
        }
        // The seeded Add sheet is presented from `onDismiss`, once the cover is actually gone -
        // stacking it straight onto the outgoing cover gets silently dropped.
        .fullScreenCover(isPresented: $isShowingOnboarding, onDismiss: {
            guard let pending = pendingOnboardingAdd else { return }
            pendingOnboardingAdd = nil
            onboardingAdd = pending
            // They've committed to tracking something - now is the moment to ask for the nudge.
            Task {
                if await NotificationScheduler.requestAuthorization() {
                    await NotificationScheduler.scheduleWelcomeNudge()
                }
            }
        }) {
            OnboardingFlow { selection in
                FirstRunWelcomeStore.markSeen(userId: profile.id)
                let add: OnboardingAdd?
                switch selection {
                case .goal(let template): add = .goal(template)
                case .habit(let template): add = .habit(template)
                case .customGoal: add = .goal(nil)
                case .customHabit: add = .habit(nil)
                case nil: add = nil
                }
                pendingOnboardingAdd = add
                switch add {
                case .habit: selectedTab = .habits
                case .goal: selectedTab = .goals
                case nil: break
                }
                isShowingOnboarding = false
            }
        }
        .sheet(item: $onboardingAdd) { add in
            switch add {
            case .goal(let template):
                AddEditGoalView(goal: nil, userId: profile.id, template: template)
            case .habit(let template):
                AddEditHabitView(habit: nil, userId: profile.id, template: template)
            }
        }
        // Every visit rebuilds the schedule, which is also what pushes the "haven't seen you"
        // nudge further into the future.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                Analytics.beginSession()
                AppReviewPrompt.recordFirstLaunchIfNeeded()
                pushIdentityToWatch()
                reconcileStreakFreezes()
                Task { await NotificationScheduler.syncAll(context: modelContext, userId: profile.id) }
                // The rating prompt itself no longer lives here — it fires from the moment a goal
                // is finished (see `GoalDetailView.requestReviewIfEarned`), right after the
                // celebration overlay, rather than on any old app launch.
                Task {
                    await showProPromoIfEarned()
                }
            case .background:
                Analytics.endSession()
                // Whatever changed in the app, the home screen should show it.
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkInDidChange)) { _ in
            reconcileStreakFreezes()
        }
        .onOpenURL { url in
            guard url.scheme == "goals" else { return }
            switch url.host {
            case "goal":
                guard let id = UUID(uuidString: url.lastPathComponent) else { return }
                selectedTab = .today
                todayPath = NavigationPath()
                todayPath.append(id)
            case "habit":
                selectedTab = .habits
                // One assignment, not clear-then-append: two mutations in a tick make SwiftUI
                // complain that navigation updated "multiple times per frame".
                habitsPath = UUID(uuidString: url.lastPathComponent).map { [$0] } ?? []
            case "habits":
                selectedTab = .habits
                habitsPath = []
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

    /// Earns any freezes the streaks have built up and — for Pro — auto-spends one on a streak
    /// a single missed day from breaking. Runs on every scene-active and after each in-app
    /// check-in; it's a no-op unless something actually changed.
    private func reconcileStreakFreezes() {
        StreakFreezeEngine.reconcile(
            context: modelContext,
            userId: profile.id,
            isPro: purchaseManager.isProUnlocked
        )
    }

    /// Hands the watch app the local profile id, nickname and cloud-sync flag it can't mint for
    /// itself. Cheap and idempotent — WatchConnectivity only delivers the newest context.
    private func pushIdentityToWatch() {
        WatchConnectivityBridge.shared.pushIdentity(
            profileID: profile.id,
            nickname: profile.nickname,
            cloudSyncEnabled: SharedStore.isCloudSyncEnabled,
            language: language.rawValue,
            vacation: Vacation.current(for: profile.id)
        )
    }

    /// The promo waits for the same quiet moment the rating prompt does — nothing else on screen,
    /// the launch settled — and `ProPromoPrompt` decides whether this is one of the rare turns it
    /// gets at all.
    private func showProPromoIfEarned() async {
        guard !isShowingOnboarding, !isShowingPaywall else { return }

        let userId = profile.id
        let checkInDescriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.ownerId == userId })
        let checkInCount = (try? modelContext.fetchCount(checkInDescriptor)) ?? 0
        guard ProPromoPrompt.shouldShow(isProUnlocked: purchaseManager.isProUnlocked, checkInCount: checkInCount) else { return }

        try? await Task.sleep(for: .seconds(2))
        guard scenePhase == .active, !isShowingOnboarding, !isShowingPaywall else { return }
        // Entitlements load asynchronously, so the check is worth repeating once they have.
        guard !purchaseManager.isProUnlocked else { return }

        ProPromoPrompt.recordShown()
        paywallSource = .promo
        isShowingPaywall = true
    }
}

/// Remembers whether this device has seen the first-run welcome sheet. Keyed by the local
/// profile id, which is stable for the life of the install.
private enum FirstRunWelcomeStore {
    private static func key(for userId: UUID) -> String { "Goals.hasSeenFirstRunWelcome.\(userId.uuidString)" }

    static func hasSeen(userId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: userId))
    }

    static func markSeen(userId: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: userId))
    }
}

#Preview {
    RootView()
        .environment(Profile())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
