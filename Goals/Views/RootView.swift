//
//  RootView.swift
//  Goals
//

import SwiftUI
import SwiftData
import WidgetKit

struct RootView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.deviceDefault.rawValue

    /// Lives above the `.id(languageRaw)` rebuild, so switching the language keeps the user
    /// on the tab they were on (Settings) instead of dropping them back on the goals list.
    @State private var selectedTab: MainTab = .today
    /// Owned here so a widget tap can push a goal onto the Today stack.
    @State private var todayPath = NavigationPath()

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
        .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme)
        // Every visit rebuilds the schedule, which is also what pushes the "haven't seen you"
        // nudge further into the future.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                Task { await NotificationScheduler.syncAll(context: modelContext) }
            case .background:
                // Whatever changed in the app, the home screen should show it.
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
        .onOpenURL { url in
            guard url.scheme == "goals", url.host == "goal",
                  let id = UUID(uuidString: url.lastPathComponent) else { return }
            selectedTab = .today
            todayPath = NavigationPath()
            todayPath.append(id)
        }
    }
}

#Preview {
    RootView()
        .environment(AuthSession())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
