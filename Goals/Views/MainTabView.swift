//
//  MainTabView.swift
//  Goals
//

import SwiftUI
import SwiftData

enum MainTab: String, Hashable {
    case today, goals, stats, settings
}

struct MainTabView: View {
    /// Owned by `RootView` so the tab survives the rebuild that applies a language change.
    @Binding var selection: MainTab
    @Binding var todayPath: NavigationPath

    var body: some View {
        TabView(selection: $selection) {
            TodayView(path: $todayPath)
                .tabItem {
                    Label("tab.today", systemImage: "sun.max.fill")
                }
                .tag(MainTab.today)

            GoalsListView()
                .tabItem {
                    Label("tab.goals", systemImage: "target")
                }
                .tag(MainTab.goals)

            StatsView()
                .tabItem {
                    Label("tab.stats", systemImage: "chart.bar.fill")
                }
                .tag(MainTab.stats)

            SettingsView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape.fill")
                }
                .tag(MainTab.settings)
        }
    }
}

#Preview {
    MainTabView(selection: .constant(.today), todayPath: .constant(NavigationPath()))
        .environment(AuthSession())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
