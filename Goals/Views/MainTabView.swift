//
//  MainTabView.swift
//  Goals
//

import SwiftUI
import SwiftData

enum MainTab: String, Hashable, CaseIterable {
    case today, goals, stats, settings

    var title: LocalizedStringKey {
        switch self {
        case .today: "tab.today"
        case .goals: "tab.goals"
        case .stats: "tab.stats"
        case .settings: "tab.settings"
        }
    }

    /// Outline when resting, filled when current — the pair the design leans on to mark the tab
    /// you're on, since the accent alone is easy to miss at 10pt.
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .goals: "target"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .goals: "target"
        case .stats: "chart.bar.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// A pushed screen asks for the floating bar to step aside — a goal's detail is a place you went
/// to, not one of the four places you switch between.
struct TabBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func hidesTabBar() -> some View {
        preference(key: TabBarHiddenKey.self, value: true)
    }
}

struct MainTabView: View {
    let userId: UUID
    /// Owned by `RootView` so the tab survives the rebuild that applies a language change.
    @Binding var selection: MainTab
    @Binding var todayPath: NavigationPath
    /// Owned by `RootView`, flipped to drop a brand-new user straight into Add Goal.
    @Binding var addGoalTrigger: Bool

    /// The four screens stay alive behind one another rather than being rebuilt on every switch,
    /// so scroll position and navigation state survive a trip to Settings and back.
    @State private var isTabBarHidden = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ground.ignoresSafeArea()

            ZStack {
                screen(.today) { TodayView(userId: userId, path: $todayPath) }
                screen(.goals) { GoalsListView(userId: userId, addGoalTrigger: $addGoalTrigger) }
                screen(.stats) { StatsView(userId: userId) }
                screen(.settings) { SettingsView() }
            }
            .onPreferenceChange(TabBarHiddenKey.self) { isHidden in
                isTabBarHidden = isHidden
            }

            if !isTabBarHidden {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: isTabBarHidden)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func screen<Content: View>(_ tab: MainTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            // A hidden tab that still answers taps would swallow them through the visible one.
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        // Goals gets the app's own mark rather than a symbol — it's the tab the
                        // whole app is named after.
                        if tab == .goals {
                            GoalsMark(
                                size: 21,
                                tone: .mono,
                                color: isSelected ? Theme.accentBright : Theme.textFaint
                            )
                            .frame(height: 22)
                        } else {
                            Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                                .frame(height: 22)
                        }
                        Text(tab.title)
                            .font(Theme.Typo.tab)
                    }
                    .foregroundStyle(isSelected ? Theme.accentBright : Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.surface.opacity(0.82))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview {
    MainTabView(userId: UUID(), selection: .constant(.today), todayPath: .constant(NavigationPath()), addGoalTrigger: .constant(false))
        .environment(AuthSession())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
