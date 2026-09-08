//
//  WatchTodayView.swift
//  GoalsWatch
//

import SwiftUI
import SwiftData
import WatchKit

/// The whole watch app: what's due today, and one tap per row to check it off. No detail screen,
/// no editing — those stay on the phone.
struct WatchTodayView: View {
    let userId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @Query private var habits: [Habit]

    /// Bumped by the change notification so the rolled-up summary recomputes even in the rare case
    /// `@Query` doesn't (a poke that beats the CloudKit import).
    @State private var refreshToken = 0

    init(userId: UUID) {
        self.userId = userId
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId }, sort: [SortDescriptor(\Habit.sortIndex)])
    }

    private var summary: TodaySchedule.Summary {
        _ = refreshToken
        return TodaySchedule.summary(goals: goals, habits: habits, userId: userId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                if summary.isEmpty {
                    emptyState
                } else {
                    ForEach(summary.items) { item in
                        Button {
                            log(item)
                        } label: {
                            WatchTodayRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(WatchTheme.accent.opacity(0.12), for: .navigation)
        .navigationTitle("watch.today.title")
        .refreshable { WatchConnectivityBridge.shared.requestIdentity() }
        .onReceive(NotificationCenter.default.publisher(for: .watchDataDidChange)) { _ in
            refreshToken &+= 1
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(summary.done)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: "/ \(summary.total)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if summary.bestStreak > 0 {
                    Label("\(summary.bestStreak)", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.accent)
                        .labelStyle(.titleAndIcon)
                }
            }

            if summary.total > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<summary.total, id: \.self) { index in
                        Capsule()
                            .fill(index < summary.done ? WatchTheme.accent : WatchTheme.track)
                            .frame(height: 4)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("today.empty.title")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Actions

    private func log(_ item: TodaySchedule.Item) {
        let nowDone: Bool
        if item.isHabit, let habit = habits.first(where: { $0.id == item.id }) {
            if habit.isAvoid {
                WKInterfaceDevice.current().play(.failure)   // avoid habits aren't logged from the wrist
                return
            }
            nowDone = WatchLogAction.toggle(habit, in: modelContext)
        } else if let goal = goals.first(where: { $0.id == item.id }) {
            _ = WatchLogAction.quickAction(goal, in: modelContext)
            nowDone = goal.hasCheckIn(on: .now)
        } else {
            return
        }
        WKInterfaceDevice.current().play(nowDone ? .success : .click)
        refreshToken &+= 1
    }
}
