//
//  WeekReview.swift
//  Goals
//

import Foundation

/// A week's activity across every tracked goal and habit, rolled up for the review screen and the
/// shareable card. A pure value type — no SwiftData, no SwiftUI — so it's cheap to compute, easy
/// to test, and safe to hand to an `ImageRenderer`.
struct WeekReview {
    /// One goal or habit's week.
    struct Line: Identifiable {
        let id: UUID
        let title: String
        let emoji: String?
        let colorHex: String
        let isHabit: Bool
        /// Scheduled occurrences that fell in the week — capped at today for the current week, so a
        /// Friday goal isn't counted as "missed" on Wednesday.
        let planned: Int
        /// How many of them were done.
        let done: Int
        /// The item's current streak, in its own schedule's unit (days, or weeks/months for a quota).
        let streak: Int

        var moved: Bool { done > 0 }
        var stalled: Bool { planned > 0 && done == 0 }
        /// 0…1, clamped — `done` can run past `planned` on a day a value goal is logged twice.
        var fraction: Double {
            guard planned > 0 else { return done > 0 ? 1 : 0 }
            return min(Double(done) / Double(planned), 1)
        }
    }

    /// The streak thresholds worth calling out when one is crossed during the week.
    static let milestoneThresholds = [365, 100, 30, 7]

    let interval: DateInterval
    /// 0 = the current week, negative = weeks back.
    let weekOffset: Int
    let lines: [Line]
    /// Check-ins and habit entries per day of the week, in the calendar's own weekday order
    /// (index 0 is the first day of the week).
    let dailyCounts: [Int]
    /// Streaks that crossed a threshold this week: the item's title and the threshold it reached.
    let milestones: [(title: String, days: Int)]

    var planned: Int { lines.reduce(0) { $0 + $1.planned } }
    var done: Int { lines.reduce(0) { $0 + $1.done } }
    /// Share of planned check-ins that got done, 0…1.
    var adherence: Double {
        guard planned > 0 else { return 0 }
        return min(Double(done) / Double(planned), 1)
    }

    var moved: [Line] { lines.filter(\.moved).sorted { $0.done > $1.done } }
    var stalled: [Line] { lines.filter(\.stalled).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
    var longestStreak: Line? { lines.max { $0.streak < $1.streak } }
    var isCurrentWeek: Bool { weekOffset == 0 }
    var hasActivity: Bool { !lines.isEmpty }

    // MARK: - Building

    static func make(
        goals: [Goal],
        habits: [Habit],
        weekOffset: Int = 0,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeekReview {
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: now) ?? now
        let interval = calendar.dateInterval(of: .weekOfYear, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 7 * 86_400)

        // A goal or habit whose start date is still in the future hasn't begun — it shouldn't
        // show up as "stalled" in a week it was never meant to run.
        let activeGoals = goals.filter { $0.status == .active && !$0.isUpcoming(asOf: now, calendar: calendar) }
        let activeHabits = habits.filter { !$0.isArchived && !$0.isUpcoming(asOf: now, calendar: calendar) }
        let vacation = Vacation.current()

        var lines: [Line] = []
        lines.reserveCapacity(activeGoals.count + activeHabits.count)

        for goal in activeGoals {
            lines.append(Line(
                id: goal.id,
                title: goal.title,
                emoji: goal.emoji,
                colorHex: goal.colorHex,
                isHabit: false,
                planned: plannedCount(for: goal, start: goal.startDate, in: interval, now: now, vacation: vacation, calendar: calendar),
                done: doneCount(for: goal, in: interval),
                streak: StreakCalculator.currentStreak(for: goal, calendar: calendar, referenceDate: now)
            ))
        }
        for habit in activeHabits {
            lines.append(Line(
                id: habit.id,
                title: habit.title,
                emoji: habit.emoji,
                colorHex: habit.colorHex,
                isHabit: true,
                planned: plannedCount(for: habit, start: habit.startDate, in: interval, now: now, vacation: vacation, calendar: calendar),
                done: doneCount(for: habit, in: interval),
                streak: StreakCalculator.currentStreak(for: habit, calendar: calendar, referenceDate: now)
            ))
        }

        let allDates = activeGoals.flatMap(\.scheduleDates) + activeHabits.flatMap(\.scheduleDates)
        var daily = [Int](repeating: 0, count: 7)
        for date in allDates where interval.contains(date) {
            let dayIndex = calendar.dateComponents(
                [.day],
                from: interval.start,
                to: calendar.startOfDay(for: date)
            ).day ?? 0
            if (0..<7).contains(dayIndex) { daily[dayIndex] += 1 }
        }

        // A streak crossed a threshold this week if it's at or past it now, but was short of it
        // before this week's check-ins landed.
        var milestones: [(title: String, days: Int)] = []
        for line in lines {
            if let reached = milestoneThresholds.first(where: {
                line.streak >= $0 && line.streak - line.done < $0
            }) {
                milestones.append((line.title, reached))
            }
        }
        milestones.sort { $0.days > $1.days }

        return WeekReview(
            interval: interval,
            weekOffset: weekOffset,
            lines: lines,
            dailyCounts: daily,
            milestones: milestones
        )
    }

    /// How many times `schedule` was due in `interval`. Day-based types count their scheduled days
    /// in the window; a weekly quota is one target for the week, a monthly quota is prorated to a
    /// week. The window starts no earlier than the item's start date and, for the current week,
    /// ends at the end of today.
    static func plannedCount(
        for schedule: some Scheduled,
        start: Date,
        in interval: DateInterval,
        now: Date,
        vacation: Vacation = .current(),
        calendar: Calendar
    ) -> Int {
        let lower = max(interval.start, calendar.startOfDay(for: start))
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? interval.end
        let upper = min(interval.end, endOfToday)
        guard lower < upper else { return 0 }

        switch schedule.recurrenceType {
        case .timesPerWeek:
            // A week the user was entirely away for doesn't ask anything of them.
            return vacation.pausesEntirePeriod(schedule.id, interval, calendar: calendar) ? 0 : max(0, schedule.recurrenceCount)
        case .timesPerMonth:
            // ~4.345 weeks to a month; at least one so a monthly habit still shows up.
            return max(1, Int((Double(max(0, schedule.recurrenceCount)) / 4.345).rounded()))
        case .daily, .specificWeekdays, .specificDaysOfMonth:
            var count = 0
            var cursor = lower
            while cursor < upper {
                if Recurrence.isDayScheduled(cursor, for: schedule, calendar: calendar),
                   !vacation.pauses(schedule.id, on: cursor, calendar: calendar) {
                    count += 1
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return count
        }
    }

    /// How many check-ins / met-target days landed in `interval`. `scheduleDates` already means the
    /// right thing for each kind: check-in dates for a goal, met-target days for a habit, and one
    /// entry per check-in for a quota.
    static func doneCount(for schedule: some Scheduled, in interval: DateInterval) -> Int {
        schedule.scheduleDates.count { interval.contains($0) }
    }
}
