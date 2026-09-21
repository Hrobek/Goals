//
//  TodayWidget.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Entry

/// One page with today's goals and today's habits together, so there's no picking between the
/// two single-purpose widgets. Sized down to fit `systemLarge`, and full-height on iOS 27's extra
/// large portrait family - the first widget size with room to show both lists at once.
struct TodayEntry: TimelineEntry {
    let date: Date
    let goals: [GoalSnapshot]
    let habits: [HabitSnapshot]
    let goalsDoneToday: Int
    let goalsTotalToday: Int
    let habitsDoneToday: Int
    let habitsTotalToday: Int
    var isSignedIn = true
}

// MARK: - Provider

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        Self.sampleEntry(for: context.family)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? Self.sampleEntry(for: context.family) : Self.entry(for: context.family))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // Same as the other widgets: nothing changes on its own until the day rolls over.
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [Self.entry(for: context.family)], policy: .after(midnight)))
    }

    /// The extra-large portrait page has room for a full page's worth of both lists; `systemLarge`
    /// splits a much smaller page between them, so it gets a tighter cap on each.
    private static func goalsLimit(for family: WidgetFamily) -> Int {
        family == .systemLarge ? 3 : 5
    }

    /// Two rows worth for either size - see `habitColumnCount` on the entry view.
    private static func habitsLimit(for family: WidgetFamily) -> Int {
        family == .systemLarge ? 6 : 12
    }

    @MainActor
    private static func entry(for family: WidgetFamily) -> TodayEntry {
        guard WidgetGoals.isSignedIn else {
            return TodayEntry(
                date: .now, goals: [], habits: [],
                goalsDoneToday: 0, goalsTotalToday: 0,
                habitsDoneToday: 0, habitsTotalToday: 0,
                isSignedIn: false
            )
        }

        let goals = GoalsProvider.todaysGoals()
        let habits = HabitsProvider.todaysHabits()

        return TodayEntry(
            date: .now,
            goals: goals.prefix(goalsLimit(for: family)).map(GoalSnapshot.init(goal:)),
            habits: habits.prefix(habitsLimit(for: family)).map(HabitSnapshot.init(habit:)),
            goalsDoneToday: goals.filter { $0.hasCheckIn(on: .now) }.count,
            goalsTotalToday: goals.count,
            habitsDoneToday: habits.filter { $0.isDone(on: .now) }.count,
            habitsTotalToday: habits.count
        )
    }

    private static func sampleEntry(for family: WidgetFamily) -> TodayEntry {
        let goals = [
            GoalSnapshot(id: UUID(), title: "Uběhnout 100 km", emoji: "🏃", colorHex: "#54A0FF",
                         progress: 0.4, detail: "40/100 km", actionLabel: "+5", isDoneToday: false),
            GoalSnapshot(id: UUID(), title: "Přečíst knihu", emoji: "📚", colorHex: "#1DD1A1",
                         progress: 1, detail: "1/1", actionLabel: nil, isDoneToday: true),
            GoalSnapshot(id: UUID(), title: "Ušetřit", emoji: "💰", colorHex: "#FECA57",
                         progress: 0.62, detail: "6 200/10 000 Kč", actionLabel: "+200", isDoneToday: false),
        ]
        func habit(_ title: String, _ emoji: String, _ hex: String, _ amount: Double, _ target: Double) -> HabitSnapshot {
            HabitSnapshot(id: UUID(), title: title, emoji: emoji, colorHex: hex, streak: 3,
                          isCheckbox: target == 1, quickAddLabel: "", amountToday: amount, target: target)
        }
        let habits = [
            habit("Voda", "💧", "#54A0FF", 1500, 3000),
            habit("Číst", "📖", "#1DD1A1", 1, 1),
            habit("Meditace", "🧘", "#FECA57", 0, 1),
            habit("Kroky", "🚶", "#FF9F43", 7000, 10000),
            habit("Vitamíny", "💊", "#EE5A9E", 1, 1),
        ]
        return TodayEntry(
            date: .now,
            goals: Array(goals.prefix(goalsLimit(for: family))),
            habits: Array(habits.prefix(habitsLimit(for: family))),
            goalsDoneToday: 1,
            goalsTotalToday: goals.count,
            habitsDoneToday: 2,
            habitsTotalToday: habits.count
        )
    }
}

// MARK: - View

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodayEntry

    /// 6 across the full-height extra-large portrait page, 5 across the narrower `systemLarge` -
    /// matching `HabitsWidget`'s own column counts for those widths.
    private var habitColumnCount: Int { family == .systemLarge ? 5 : 6 }
    private var ringGap: CGFloat { family == .systemLarge ? 10 : 12 }
    private var sectionSpacing: CGFloat { family == .systemLarge ? 14 : 22 }
    private var contentPadding: CGFloat { family == .systemLarge ? 16 : 20 }
    private var headerFontSize: CGFloat { family == .systemLarge ? 17 : 22 }
    /// Floor for the ring size, matching `HabitsWidget`'s own floor - a comfortable tap target
    /// even if a future, narrower size ever offered this family less width.
    private let minRingDiameter: CGFloat = 44

    var body: some View {
        if !entry.isSignedIn {
            WidgetMessageView(message: "widget.notSignedIn", systemImage: "person.crop.circle.badge.questionmark")
        } else if entry.goals.isEmpty && entry.habits.isEmpty {
            WidgetMessageView(message: "today.empty.title", systemImage: "checkmark.circle")
        } else {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                header
                if !entry.goals.isEmpty {
                    goalsSection
                }
                if !entry.habits.isEmpty {
                    habitsSection
                }
                Spacer(minLength: 0)
            }
            .padding(contentPadding)
        }
    }

    private var header: some View {
        Text("tab.today")
            .font(.system(size: headerFontSize, weight: .bold))
            .foregroundStyle(Theme.text)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("goals.title", count: "\(entry.goalsDoneToday)/\(entry.goalsTotalToday)")
            VStack(spacing: 8) {
                ForEach(entry.goals) { goal in
                    GoalRowView(goal: goal)
                    if goal.id != entry.goals.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("habits.title", count: "\(entry.habitsDoneToday)/\(entry.habitsTotalToday)")
            // Sized off the actual width this page gets rather than a guessed constant, the same
            // way `HabitsWidget` does it. The reader is free to claim more height than the grid
            // needs (it's the last thing before the trailing `Spacer`), which is harmless here
            // since the ring size is set from the width, not the height.
            GeometryReader { geo in
                let columns = CGFloat(habitColumnCount)
                let diameter = max(minRingDiameter, (geo.size.width - ringGap * (columns - 1)) / columns)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(diameter), spacing: ringGap), count: habitColumnCount),
                    alignment: .leading,
                    spacing: ringGap
                ) {
                    ForEach(entry.habits) { habit in
                        HabitRingButton(habit: habit, diameter: diameter)
                    }
                }
                .frame(width: geo.size.width, alignment: .topLeading)
            }
        }
    }

    private func sectionHeader(_ titleKey: LocalizedStringKey, count: String) -> some View {
        HStack {
            Text(titleKey)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Theme.textFaint)
            Spacer(minLength: 4)
            Text(count)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .monospacedDigit()
        }
    }
}

// MARK: - Widget

struct TodayWidget: Widget {
    let kind = "GoalsTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetContainerBackground() }
                .environment(\.locale, AppLanguage.current.locale)
        }
        .configurationDisplayName("widget.today.displayName")
        .description("widget.today.description")
        .supportedFamilies(supportedFamilies)
        .contentMarginsDisabled()
    }

    /// `systemLarge` back to iOS 17, plus iOS 27's full-page extra-large portrait size where it
    /// exists - a combined Today widget only makes full sense once that size can hold both lists
    /// without the `systemLarge` squeeze.
    private var supportedFamilies: [WidgetFamily] {
        if #available(iOS 27.0, *) {
            [.systemLarge, .systemExtraLargePortrait]
        } else {
            [.systemLarge]
        }
    }
}
