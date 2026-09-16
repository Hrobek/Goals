//
//  MainTabView.swift
//  Goals
//

import SwiftUI
import SwiftData

enum MainTab: String, Hashable, CaseIterable {
    case today, goals, habits, stats, settings

    var title: LocalizedStringKey {
        switch self {
        case .today: "tab.today"
        case .goals: "tab.goals"
        case .habits: "tab.habits"
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
        case .habits: "repeat"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .goals: "target"
        case .habits: "repeat.circle.fill"
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
    /// Owned by `RootView` too, so a habit-widget tap can push a habit's detail onto this stack.
    @Binding var habitsPath: [UUID]
    /// Owned by `RootView`, flipped to drop a brand-new user straight into Add Goal.
    @Binding var addGoalTrigger: Bool

    /// The four screens stay alive behind one another rather than being rebuilt on every switch,
    /// so scroll position and navigation state survive a trip to Settings and back.
    @State private var isTabBarHidden = false
    /// The finger's live x while pressed on the bar, in the row's own coordinate space; `nil`
    /// whenever nothing is being dragged. Drives the glass pill 1:1 with the touch instead of
    /// only hopping between tab centers, and doubles as "is a drag in progress" for whether the
    /// pill's move should animate (a tap's settle) or track instantly (an active drag).
    @State private var pillDragX: CGFloat?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ground.ignoresSafeArea()

            ZStack {
                screen(.today) { TodayView(userId: userId, path: $todayPath) }
                screen(.goals) { GoalsListView(userId: userId, addGoalTrigger: $addGoalTrigger) }
                screen(.habits) { HabitsView(userId: userId, path: $habitsPath) }
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
        tabBarBackground
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
            .sensoryFeedback(.selection, trigger: selection)
    }

    /// Real Liquid Glass on 26+; the hand-rolled `.ultraThinMaterial` stand-in - a solid tint
    /// layered under the material for legibility over busy scrolling content - everywhere older.
    /// `GlassEffectContainer` is one shape here today, but it's the wrapper Apple's own glass
    /// elements expect and is what a future per-tab highlight would need to morph inside.
    @ViewBuilder
    private var tabBarBackground: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                tabBarRow
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        } else {
            tabBarRow
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
        }
    }

    private var tabBarRow: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let tabWidth = width / CGFloat(MainTab.allCases.count)
            let settledIndex = CGFloat(MainTab.allCases.firstIndex(of: selection) ?? 0)
            // Centered under the finger while dragging, clamped so it never pokes past the
            // bar's own ends; otherwise parked under whichever tab is selected.
            let liveOffset = pillDragX.map { min(max($0 - tabWidth / 2, 0), width - tabWidth) }
            let pillOffset = liveOffset ?? settledIndex * tabWidth

            ZStack(alignment: .leading) {
                selectionPill
                    .frame(width: max(0, tabWidth - 12), height: 46)
                    .offset(x: pillOffset + 6)
                tabBarButtons
            }
            // `.simultaneousGesture`, not `.gesture`: VoiceOver and a plain tap still go through
            // each button's own action untouched: this only adds the press-and-slide on top, for
            // a pointer or touch drag. The pill is free to roam the whole bar as the finger
            // moves - only on release does wherever it's sitting actually become the selection,
            // so a drag can be walked back and forth without the page flipping through every tab
            // it passes on the way.
            //
            // `minimumDistance: 12` on purpose, not 0: a plain tap should never touch `pillDragX`
            // at all. With 0 it did - the tap's touch-down snapped the pill there instantly
            // (dragging never animates), and then the button's own action *also* fired and could
            // kick off a second, competing animated glide from wherever the pill still visually
            // was, which is exactly the "comes in from the wrong side" glitch. Past that small
            // threshold it's a deliberate drag, so 1:1 tracking is the whole point.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard tabWidth > 0 else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            pillDragX = min(max(value.location.x, 0), width)
                        }
                    }
                    .onEnded { value in
                        guard tabWidth > 0 else {
                            withAnimation(.smooth(duration: 0.3)) { pillDragX = nil }
                            return
                        }
                        let x = min(max(value.location.x, 0), width)
                        let index = Int(x / tabWidth)
                        let clamped = min(max(index, 0), MainTab.allCases.count - 1)
                        withAnimation(.smooth(duration: 0.3)) {
                            selection = MainTab.allCases[clamped]
                            pillDragX = nil
                        }
                    }
            )
        }
        .frame(height: 60)
    }

    private var tabBarButtons: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.smooth(duration: 0.3)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        // Goals keeps the app's own mark rather than a symbol — it's the tab the
                        // whole app is named after. Habits sits right next to it as an equal.
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
    }

    /// The current tab's glass highlight - one persistent shape moved by `tabBarRow`'s offset
    /// rather than a per-tab shape swapped in and out, so it can track a drag continuously
    /// instead of only hopping between tab centers. Left untinted on purpose: the color lives on
    /// the selected icon, not the glass, so the pill itself stays a plain, transparent highlight.
    /// No pill at all pre-26 - the icon's own color/weight change is still the only selected cue
    /// there, same as before this existed.
    @ViewBuilder
    private var selectionPill: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

#Preview {
    MainTabView(userId: UUID(), selection: .constant(.today), todayPath: .constant(NavigationPath()), habitsPath: .constant([]), addGoalTrigger: .constant(false))
        .environment(Profile())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
