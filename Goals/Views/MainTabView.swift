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
            // One gesture owns the whole bar - there's no per-tab `Button` underneath it
            // anymore. Two independent recognizers on the same touch (a `Button`'s own tap next
            // to this drag) was the actual cause of both older glitches: occasionally the button
            // just wouldn't register at all (SwiftUI doesn't reliably let a plain tap and a
            // simultaneous drag recognizer both claim the same touch), and when it did, its
            // separately-triggered animation could race the drag's, which is what "comes in from
            // the wrong side" was. One recognizer can't race itself, and `minimumDistance: 0`
            // means the very first touch sample already drives the pill - the earlier 12pt dead
            // zone before tracking kicked in was the "jerky on the first grab" feeling.
            //
            // It's still safe to let a plain tap flow through here: `selection` itself only ever
            // changes in `onEnded`, so a tap's touch-down just previews the pill sliding over,
            // and lifting immediately commits it - never a mid-drag page flip.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard tabWidth > 0 else { return }
                        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.86, blendDuration: 0.05)) {
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

    /// Plain content, not `Button` - `tabBarRow`'s own drag gesture is the only thing that reacts
    /// to touch here (see the comment on that gesture for why two recognizers on the same touch
    /// was actively buggy). VoiceOver still gets a proper button: the traits plus an explicit
    /// accessibility action stand in for the tap a `Button` would otherwise have supplied.
    private var tabBarButtons: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isSelected = selection == tab
                // `Theme.textFaint` is a fixed mid-gray in both appearances, chosen to be quiet
                // against the old *opaque* bar - against real glass showing through, "quiet" can
                // tip into "not actually visible" depending on what's behind it. `.primary` is
                // the adaptive, always-legible label color (near-white in dark mode, near-black
                // in light) instead of a hardcoded white that would vanish in light mode.
                let restingColor = Color.primary
                VStack(spacing: 3) {
                    // Goals keeps the app's own mark rather than a symbol — it's the tab the
                    // whole app is named after. Habits sits right next to it as an equal.
                    if tab == .goals {
                        GoalsMark(
                            size: 21,
                            tone: .mono,
                            color: isSelected ? Theme.accentBright : restingColor
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
                .foregroundStyle(isSelected ? Theme.accentBright : restingColor)
                // Real glass refracts whatever's scrolling behind the bar, so a fixed icon
                // color that read fine against the old opaque backdrop can wash out over a
                // bright patch. A soft halo in the theme's own ground color - dark in dark
                // mode, light in light mode - keeps the glyph legible without tying it to a
                // hardcoded color that would fight light mode.
                .shadow(color: Theme.ground.opacity(0.9), radius: 3)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .contentShape(.rect)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction {
                    withAnimation(.smooth(duration: 0.3)) { selection = tab }
                }
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
