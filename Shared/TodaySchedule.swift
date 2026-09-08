//
//  TodaySchedule.swift
//  Goals
//

import Foundation
import SwiftData

/// What a given day asks of you, rolled up in one place so the watch app and the watch
/// complications agree on the "3 / 7" the way the Today screen shows it. Pure read: fetches the
/// user's goals and habits, applies the same schedule + vacation rules `TodayView` uses, and
/// hands back plain values — never SwiftData models, since a timeline outlives the fetch.
///
/// The iOS `TodayView` predates this and still computes the same thing inline; the rules here are
/// a faithful copy of `TodayView.todaysGoals` / `todaysHabits` / `doneCount` / `bestStreak`.
///
/// `@MainActor` to match `WidgetGoals` / `HabitsProvider` in the existing widget — it leans on
/// `Recurrence` / `StreakCalculator`, which the app target treats as main-actor.
@MainActor
enum TodaySchedule {
    /// One goal or habit due on the day.
    struct Item: Identifiable, Hashable {
        let id: UUID
        let title: String
        let emoji: String?
        let colorHex: String
        let isHabit: Bool
        /// 0…1 progress for the day. Full once the day is done; otherwise the goal's own
        /// `progressFraction` or the habit's `progressFraction(on:)` (quota and avoid handled).
        let fraction: Double
        let isDone: Bool
        let streak: Int
    }

    struct Summary {
        var items: [Item] = []
        var done: Int = 0
        var total: Int = 0
        /// Longest run going right now across every active goal and habit — not just today's —
        /// since that's what a missed day costs.
        var bestStreak: Int = 0

        var isEmpty: Bool { total == 0 }
        /// The first item not yet done — what a "next up" complication points at.
        var nextUp: Item? { items.first { !$0.isDone } }
    }

    /// Fetches for `userId` and rolls the day up. `date` defaults to now; pass an earlier day to
    /// see what that day looked like.
    static func summary(
        userId: UUID,
        on date: Date = .now,
        context: ModelContext,
        calendar: Calendar = .current
    ) -> Summary {
        let goals = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId == userId }))) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId == userId }))) ?? []
        return summary(goals: goals, habits: habits, userId: userId, on: date, calendar: calendar)
    }

    /// The pure core, split out so callers that already hold the rows (or a test) can skip the fetch.
    static func summary(
        goals: [Goal],
        habits: [Habit],
        userId: UUID,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Summary {
        let vacation = Vacation.current(for: userId)

        let todaysGoals = goals
            .filter {
                $0.status == .active
                    && $0.isScheduledToday(calendar: calendar, date: date)
                    && !vacation.pauses($0.id, on: date, calendar: calendar)
            }
            .sorted { lhs, rhs in
                let lhsDone = lhs.hasCheckIn(on: date, calendar: calendar)
                let rhsDone = rhs.hasCheckIn(on: date, calendar: calendar)
                if lhsDone != rhsDone { return !lhsDone }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let todaysHabits = habits
            .filter {
                !$0.isArchived
                    && $0.isScheduledToday(calendar: calendar, date: date)
                    && !vacation.pauses($0.id, on: date, calendar: calendar)
            }
            .sorted { lhs, rhs in
                let lhsDone = lhs.isDone(on: date, calendar: calendar)
                let rhsDone = rhs.isDone(on: date, calendar: calendar)
                if lhsDone != rhsDone { return !lhsDone }
                return lhs.sortIndex < rhs.sortIndex
            }

        var items: [Item] = []
        items.reserveCapacity(todaysGoals.count + todaysHabits.count)

        for goal in todaysGoals {
            let done = goal.hasCheckIn(on: date, calendar: calendar)
            items.append(Item(
                id: goal.id,
                title: goal.title,
                emoji: goal.emoji,
                colorHex: goal.colorHex,
                isHabit: false,
                fraction: done ? 1 : goal.progressFraction,
                isDone: done,
                streak: StreakCalculator.currentStreak(for: goal, calendar: calendar, referenceDate: date)
            ))
        }
        for habit in todaysHabits {
            items.append(Item(
                id: habit.id,
                title: habit.title,
                emoji: habit.emoji,
                colorHex: habit.colorHex,
                isHabit: true,
                fraction: habit.progressFraction(on: date, calendar: calendar),
                isDone: habit.isDone(on: date, calendar: calendar),
                streak: StreakCalculator.currentStreak(for: habit, calendar: calendar, referenceDate: date)
            ))
        }

        let goalStreaks = goals
            .filter { $0.status == .active }
            .map { StreakCalculator.currentStreak(for: $0, calendar: calendar, referenceDate: date) }
        let habitStreaks = habits
            .filter { !$0.isArchived }
            .map { StreakCalculator.currentStreak(for: $0, calendar: calendar, referenceDate: date) }

        return Summary(
            items: items,
            done: items.count { $0.isDone },
            total: items.count,
            bestStreak: (goalStreaks + habitStreaks).max() ?? 0
        )
    }
}
