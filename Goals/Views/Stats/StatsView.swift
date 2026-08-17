//
//  StatsView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \CheckIn.date) private var allCheckIns: [CheckIn]

    /// Archived goals are off the board — they'd only pad the stats with frozen streaks.
    private var trackedGoals: [Goal] {
        goals.filter { !$0.isArchived }
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

    private var currentStreak: Int {
        streaks.first?.streak ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    ScreenTitle("stats.title")

                    VStack(alignment: .leading, spacing: Theme.Space.section) {
                        tiles

                        if !streaks.isEmpty {
                            streakSection
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
        }
    }

    /// The three numbers worth a glance. The streak takes the accent — it's the one that's lost
    /// by doing nothing.
    private var tiles: some View {
        HStack(spacing: Theme.Space.card) {
            StatTile(value: "\(trackedGoals.count)", label: "stats.totalGoals")
            StatTile(value: "\(completedCount)", label: "stats.completedGoals")
            StatTile(value: "\(currentStreak)", label: "stats.currentStreak", accent: true)
        }
    }

    private var streakSection: some View {
        LabeledSection("stats.streaks.title") {
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

    @ViewBuilder
    private var trendsSection: some View {
        if purchaseManager.isProUnlocked {
            // "Pro" is the tier's name, not a word to translate.
            LabeledSection("stats.trends.title") {
                AccentPill(text: "Pro")
            } content: {
                TrendsSection(checkIns: trackedCheckIns)
            }
        } else {
            LabeledSection("stats.trends.title") {
                ProLockedCard(
                    title: "stats.trends.title",
                    message: "stats.trends.locked")
            }
        }
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
    StatsView()
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
