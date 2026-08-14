//
//  StreakCalculator.swift
//  Goals
//

import Foundation

enum StreakCalculator {
    /// Current streak for a goal, respecting its recurrence schedule:
    /// - day-based types (daily / specific weekdays / specific days of month) count consecutive
    ///   *scheduled* days with a check-in; unscheduled days are skipped without breaking the streak.
    /// - quota-based types (times per week / times per month) count consecutive periods where the
    ///   check-in count met the quota; the still-in-progress current period never breaks the streak.
    static func currentStreak(for goal: Goal, calendar: Calendar = .current, referenceDate: Date = .now) -> Int {
        switch goal.recurrenceType {
        case .daily, .specificWeekdays, .specificDaysOfMonth:
            return dayBasedStreak(for: goal, calendar: calendar, referenceDate: referenceDate)
        case .timesPerWeek:
            return periodBasedStreak(for: goal, component: .weekOfYear, maxIterations: 520, calendar: calendar, referenceDate: referenceDate)
        case .timesPerMonth:
            return periodBasedStreak(for: goal, component: .month, maxIterations: 240, calendar: calendar, referenceDate: referenceDate)
        }
    }

    private static func dayBasedStreak(for goal: Goal, calendar: Calendar, referenceDate: Date) -> Int {
        let checkInDays = Set(goal.checkIns.map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: referenceDate)

        // Grace: if today is scheduled but has no check-in yet, don't let that break the streak —
        // start counting from yesterday instead.
        if Recurrence.isDayScheduled(cursor, for: goal, calendar: calendar), !checkInDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        var iterations = 0
        let maxIterations = 3650

        while iterations < maxIterations {
            iterations += 1
            if Recurrence.isDayScheduled(cursor, for: goal, calendar: calendar) {
                if checkInDays.contains(cursor) {
                    streak += 1
                } else {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func periodBasedStreak(
        for goal: Goal,
        component: Calendar.Component,
        maxIterations: Int,
        calendar: Calendar,
        referenceDate: Date
    ) -> Int {
        guard goal.recurrenceCount > 0, var interval = calendar.dateInterval(of: component, for: referenceDate) else {
            return 0
        }

        var streak = 0
        var isCurrentPeriod = true
        var iterations = 0

        while iterations < maxIterations {
            iterations += 1
            let count = goal.checkIns.filter { interval.contains($0.date) }.count
            if count >= goal.recurrenceCount {
                streak += 1
            } else if !isCurrentPeriod {
                break
            }
            isCurrentPeriod = false

            guard let previousAnchor = calendar.date(byAdding: component, value: -1, to: interval.start),
                  let previousInterval = calendar.dateInterval(of: component, for: previousAnchor) else { break }
            interval = previousInterval
        }
        return streak
    }
}
