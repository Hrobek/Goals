//
//  TodayView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// Home screen: only the goals that are actually due today. A Mondays-only goal stays out of
/// the way for the rest of the week.
struct TodayView: View {
    @Binding var path: NavigationPath

    @Query private var goals: [Goal]

    init(userId: UUID, path: Binding<NavigationPath>) {
        self._path = path
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
    }

    private var todaysGoals: [Goal] {
        goals
            .filter { $0.status == .active && $0.isScheduledToday() }
            .sorted { lhs, rhs in
                let lhsDone = lhs.hasCheckIn(on: .now)
                let rhsDone = rhs.hasCheckIn(on: .now)
                if lhsDone != rhsDone { return !lhsDone }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var doneCount: Int {
        todaysGoals.filter { $0.hasCheckIn(on: .now) }.count
    }

    /// The longest run going right now across everything still active — the one number worth
    /// carrying in the header, since it's what a missed day costs.
    private var bestStreak: Int {
        goals
            .filter { $0.status == .active }
            .map { StreakCalculator.currentStreak(for: $0) }
            .max() ?? 0
    }

    private var todayText: String {
        Date.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.current.locale)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if todaysGoals.isEmpty {
                        EmptyStateView(
                            systemImage: "moon.stars",
                            title: "today.empty.title",
                            message: "today.empty.description"
                        )
                        .padding(.top, 90)
                    } else {
                        summary
                        goalList
                    }
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

    private var header: some View {
        ScreenTitle("today.title", subtitle: todayText) {
            if bestStreak > 0 {
                streakPill
            }
        }
    }

    private var streakPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill").font(.system(size: 13))
            Text("\(bestStreak)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Theme.accentWell, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.accentWellBorder, lineWidth: 1) }
        .foregroundStyle(Theme.accentWellText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.currentStreak"))
        .accessibilityValue(Text("\(bestStreak)"))
    }

    /// How much of today is behind you: the count, then one segment per goal due.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(doneCount)")
                    .font(.system(size: 40, weight: .medium))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(verbatim: "/ \(todaysGoals.count)")
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textFaint)
            }

            HStack(spacing: 6) {
                ForEach(0..<todaysGoals.count, id: \.self) { index in
                    Capsule()
                        .fill(index < doneCount ? Theme.accent : Theme.track)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("today.progress \(doneCount) \(todaysGoals.count)"))
    }

    private var goalList: some View {
        LazyVStack(spacing: Theme.Space.card) {
            ForEach(todaysGoals) { goal in
                NavigationLink(value: goal.id) {
                    GoalRow(goal: goal, showsTodayState: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 24)
    }
}

#Preview {
    TodayView(userId: UUID(), path: .constant(NavigationPath()))
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
