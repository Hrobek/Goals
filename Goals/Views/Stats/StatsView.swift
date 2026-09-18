//
//  StatsView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query private var goals: [Goal]
    @Query private var habits: [Habit]
    @Query private var allCheckIns: [CheckIn]

    private let userId: UUID

    init(userId: UUID) {
        self.userId = userId
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId }, sort: [SortDescriptor(\Habit.sortIndex)])
        _allCheckIns = Query(filter: #Predicate<CheckIn> { $0.ownerId == userId }, sort: \CheckIn.date)
    }

    private var trackedHabits: [Habit] {
        habits.filter { !$0.isArchived && !$0.isUpcoming() }
    }

    /// Every active habit with its streak, longest first.
    private var habitStreaks: [(habit: Habit, streak: Int)] {
        trackedHabits
            .map { ($0, $0.currentStreak) }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1
                    ? lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                    : lhs.1 > rhs.1
            }
    }

    /// Archived goals are off the board — they'd only pad the stats with frozen streaks. A goal
    /// that hasn't reached its start date isn't running yet, so it stays out too.
    private var trackedGoals: [Goal] {
        goals.filter { !$0.isArchived && !$0.isUpcoming() }
    }

    private var trackedCheckIns: [CheckIn] {
        allCheckIns.filter { !($0.goal?.isArchived ?? false) }
    }

    private var completedCount: Int {
        trackedGoals.filter(\.isCompleted).count
    }

    /// Only active goals get a row — completed ones are already summed up in the tile above, and
    /// a finished goal's frozen streak doesn't need to keep taking up space in the list.
    private var activeGoals: [Goal] {
        trackedGoals.filter { $0.status == .active }
    }

    /// Every active goal with its streak, longest first — computed once so the list and the tile agree.
    private var streaks: [(goal: Goal, streak: Int)] {
        activeGoals
            .map { ($0, StreakCalculator.currentStreak(for: $0)) }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1
                    ? lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                    : lhs.1 > rhs.1
            }
    }

    /// The longest run going right now across both goals and habits — a missed day on either
    /// costs it, so the tile should reflect both.
    private var currentStreak: Int {
        max(streaks.first?.streak ?? 0, habitStreaks.first?.streak ?? 0)
    }

    /// Every day a habit was done, for the weekly summary.
    private var habitDoneDates: [Date] {
        trackedHabits.flatMap(\.scheduleDates)
    }

    /// Every check-in and habit-done date across the board - the raw material for the Pro cards
    /// that look at the whole picture instead of one goal at a time.
    private var allDoneDates: [Date] {
        trackedCheckIns.map(\.date) + habitDoneDates
    }

    /// The longest run any goal or habit has ever had, not just the one still going. Completed
    /// goals are included here (unlike `activeGoals`) - a finished goal's frozen streak can still
    /// be the record.
    private var longestStreakEver: Int {
        let goalBest = trackedGoals.map { StreakCalculator.longestStreak(for: $0) }.max() ?? 0
        let habitBest = trackedHabits.map { StreakCalculator.longestStreak(for: $0) }.max() ?? 0
        return max(goalBest, habitBest)
    }

    /// The most check-ins and habit entries that ever landed in a single calendar week.
    private var bestWeekCount: Int {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for date in allDoneDates {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            counts[weekStart, default: 0] += 1
        }
        return counts.values.max() ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    ScreenTitle("stats.title")

                    VStack(alignment: .leading, spacing: Theme.Space.section) {
                        tiles
                        weeklySummary

                        if !streaks.isEmpty {
                            streakSection
                        }

                        if !habitStreaks.isEmpty {
                            habitStreakSection
                        }

                        trendsSection
                    }
                    .padding(.horizontal, Theme.Space.screen)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .tabBarClearance()
            .screenGround()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let goal = goals.first(where: { $0.id == id }) {
                    GoalDetailView(goal: goal)
                }
            }
            .navigationDestination(for: HabitDestination.self) { destination in
                if let habit = habits.first(where: { $0.id == destination.id }) {
                    HabitDetailView(habit: habit)
                }
            }
        }
    }

    /// The three numbers worth a glance. The streak takes the accent — it's the one that's lost
    /// by doing nothing.
    private var tiles: some View {
        HStack(spacing: Theme.Space.card) {
            StatTile(value: "\(trackedGoals.count + trackedHabits.count)", label: "stats.tracking")
            StatTile(value: "\(completedCount)", label: "stats.completedGoals")
            StatTile(value: "\(currentStreak)", label: "stats.currentStreak", accent: true)
        }
    }

    private var weeklySummary: some View {
        NavigationLink {
            WeekReviewView(userId: userId)
        } label: {
            WeeklySummaryCard(checkInDates: trackedCheckIns.map(\.date) + habitDoneDates)
        }
        .buttonStyle(.plain)
    }

    private var streakSection: some View {
        LabeledSection("stats.streaks.goals") {
            CardGroup {
                ForEach(Array(streaks.enumerated()), id: \.element.goal.id) { index, entry in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: entry.goal.id) {
                        GoalStreakRow(goal: entry.goal, streak: entry.streak)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var habitStreakSection: some View {
        LabeledSection("stats.streaks.habits") {
            CardGroup {
                ForEach(Array(habitStreaks.enumerated()), id: \.element.habit.id) { index, entry in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: HabitDestination(id: entry.habit.id)) {
                        HabitStreakRow(habit: entry.habit, streak: entry.streak)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The "step back and see the whole picture" area: a year-long activity heatmap, the all-time
    /// records, the weekday pattern, and the week-over-week trend chart. One Pro pill covers the
    /// whole stack rather than repeating it on every card.
    @ViewBuilder
    private var trendsSection: some View {
        // "Pro" is the tier's name, not a word to translate.
        LabeledSection("stats.pro.title") {
            AccentPill(text: "Pro")
        } content: {
            if purchaseManager.isProUnlocked {
                VStack(spacing: Theme.Space.card) {
                    YearInPixelsCard(doneDates: allDoneDates)
                    PersonalRecordsCard(longestStreak: longestStreakEver, bestWeek: bestWeekCount, totalCheckIns: allDoneDates.count)
                    WeekdayPatternCard(doneDates: allDoneDates)
                    TrendsSection(checkIns: trackedCheckIns)
                }
            } else {
                ProLockedCard(
                    title: "stats.pro.title",
                    message: "stats.pro.locked")
            }
        }
    }

}

/// One line per habit — colour badge, name, schedule and streak. The habit counterpart of
/// `GoalStreakRow`; the coloured `repeat` badge is what tells the two lists apart at a glance.
private struct HabitStreakRow: View {
    let habit: Habit
    let streak: Int

    private var tint: Color { Color(hex: habit.colorHex) }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(tint.opacity(0.20))
                if let emoji = habit.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 14))
                } else {
                    Image(systemName: "repeat").font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Recurrence.localizedSummary(for: habit))
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 13))
                Text("\(streak)")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(streak > 0 ? tint : Theme.textFaint)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// One line per goal — icon, name, schedule and streak. The detailed calendar grid used to live
/// inline here, but stacking a full grid per goal is what made this screen feel sprawling; it now
/// lives on the goal's own detail screen, reachable by tapping the row.
private struct GoalStreakRow: View {
    let goal: Goal
    let streak: Int

    var body: some View {
        HStack(spacing: 11) {
            GoalBadge(emoji: goal.emoji, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                // The schedule is what the streak counts — days for daily goals, weeks for a quota.
                Text(Recurrence.localizedSummary(for: goal))
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 13))
                Text("\(streak)")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(streak > 0 ? Theme.accentBright : Theme.textFaint)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// Free, one-glance version of the Pro month-over-month row in `TrendsSection` — just the current
/// week against the one before it, so there's a reason to open Stats before the week is even over.
private struct WeeklySummaryCard: View {
    /// Every check-in / habit-done date; the card just counts how many land in each week.
    let checkInDates: [Date]

    private let calendar = Calendar.current

    private var thisWeekCount: Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return checkInDates.filter { interval.contains($0) }.count
    }

    /// Last week's count up through the *same point in the week* as right now - not the full
    /// week. Comparing a Monday's one day of check-ins against all seven of last week made the
    /// delta swing wildly negative every Monday; this way Monday compares to last Monday.
    private var lastWeekPaceCount: Int {
        guard let previousMoment = calendar.date(byAdding: .weekOfYear, value: -1, to: .now),
              let previousInterval = calendar.dateInterval(of: .weekOfYear, for: previousMoment) else { return 0 }
        return checkInDates.filter { $0 >= previousInterval.start && $0 < previousMoment }.count
    }

    private var delta: Int { thisWeekCount - lastWeekPaceCount }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("stats.weekly.title")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                Text("\(thisWeekCount)")
                    .font(Theme.Typo.statMedium)
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            if lastWeekPaceCount > 0 || thisWeekCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text(deltaText)
                        .monospacedDigit()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(delta >= 0 ? Theme.accentBright : Theme.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textGhost)
                .padding(.leading, 4)
                .accessibilityHidden(true)
        }
        .cardSurface(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.weekly.title"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var deltaText: String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }

    /// "12 check-ins, +3" — the plural count spoken properly, the delta read the same way the badge
    /// shows it (a signed number reads fine either way, and it's what `MonthComparisonRow` does too).
    private var accessibilityValue: String {
        let countPhrase = String(localized: "stats.weekly.checkIns \(thisWeekCount)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        guard lastWeekPaceCount > 0 || thisWeekCount > 0 else { return countPhrase }
        return "\(countPhrase), \(deltaText)"
    }
}

private struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Theme.Typo.statMedium)
                .foregroundStyle(accent ? Theme.accentWellText : Theme.text)
            Text(label)
                .font(Theme.Typo.footnote)
                .foregroundStyle(accent ? Theme.accentBright : Theme.textFaint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent ? Theme.accentWell : Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(accent ? Theme.accentWellBorder : Theme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StatsView(userId: UUID())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
