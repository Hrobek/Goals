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
            Form {
                Section {
                    HStack {
                        StatTile(value: "\(trackedGoals.count)", label: String(localized: "stats.totalGoals", bundle: AppLanguage.currentBundle))
                        Divider()
                        StatTile(value: "\(completedCount)", label: String(localized: "stats.completedGoals", bundle: AppLanguage.currentBundle))
                        Divider()
                        StatTile(value: "\(currentStreak)", label: String(localized: "stats.currentStreak", bundle: AppLanguage.currentBundle))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                if !streaks.isEmpty {
                    Section("stats.streaks.title") {
                        ForEach(streaks, id: \.goal.id) { entry in
                            NavigationLink {
                                GoalDetailView(goal: entry.goal)
                            } label: {
                                GoalStreakRow(goal: entry.goal, streak: entry.streak)
                            }
                        }
                    }
                }

                if purchaseManager.isProUnlocked {
                    TrendsSection(checkIns: trackedCheckIns)
                } else {
                    Section {
                        ProLockedCard(
                            title: "stats.trends.title",
                            message: "stats.trends.locked",
                            systemImage: "chart.xyaxis.line"
                        )
                    }
                }
            }
            .navigationTitle("stats.title")
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: goal.colorHex).opacity(0.2))
                    .frame(width: 32, height: 32)
                if let emoji = goal.emoji {
                    Text(emoji).font(.footnote)
                } else {
                    Image(systemName: "target")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: goal.colorHex))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline)
                    .lineLimit(1)
                // The schedule is what the streak counts — days for daily goals, weeks for a quota.
                Text(Recurrence.localizedSummary(for: goal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(streak)")
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatsView()
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
