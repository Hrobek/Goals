//
//  StatsView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    @State private var range: StatsRange = .month

    /// Archived goals are off the board — they'd only pad the stats with frozen streaks.
    private var trackedGoals: [Goal] {
        goals.filter { !$0.isArchived }
    }

    private var completedCount: Int {
        trackedGoals.filter(\.isCompleted).count
    }

    /// Every goal with its streak, longest first — computed once so the list and the tile agree.
    private var streaks: [(goal: Goal, streak: Int)] {
        trackedGoals
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
                        Picker("stats.range", selection: $range) {
                            ForEach(StatsRange.allCases) { range in
                                Text(range.localizedName).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        ForEach(streaks, id: \.goal.id) { entry in
                            GoalStreakRow(goal: entry.goal, streak: entry.streak, range: range)
                        }
                    }
                }
            }
            .navigationTitle("stats.title")
        }
    }
}

private struct GoalStreakRow: View {
    let goal: Goal
    let streak: Int
    let range: StatsRange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            ScheduleActivityView(goal: goal, range: range)
        }
        .padding(.vertical, 6)
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
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
