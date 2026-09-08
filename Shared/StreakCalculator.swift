//
//  StreakCalculator.swift
//  Goals
//

import Foundation

enum StreakCalculator {
    /// Current streak for anything on a recurrence schedule (a goal or a habit), respecting that
    /// schedule:
    /// - day-based types (daily / specific weekdays / specific days of month) count consecutive
    ///   *scheduled* days that were done; unscheduled days are skipped without breaking the streak.
    /// - quota-based types (times per week / times per month) count consecutive periods where the
    ///   done count met the quota; the still-in-progress current period never breaks the streak.
    /// Days the item was ticked off on vacation still count — but a day the user marked as away
    /// (in the active `Vacation`) is skipped like an unscheduled day rather than breaking the run.
    static func currentStreak(for schedule: some Scheduled, calendar: Calendar = .current, referenceDate: Date = .now) -> Int {
        let vacation = Vacation.current()
        switch schedule.recurrenceType {
        case .daily, .specificWeekdays, .specificDaysOfMonth:
            return dayBasedStreak(for: schedule, vacation: vacation, calendar: calendar, referenceDate: referenceDate)
        case .timesPerWeek:
            return periodBasedStreak(for: schedule, vacation: vacation, component: .weekOfYear, maxIterations: 520, calendar: calendar, referenceDate: referenceDate)
        case .timesPerMonth:
            return periodBasedStreak(for: schedule, vacation: vacation, component: .month, maxIterations: 240, calendar: calendar, referenceDate: referenceDate)
        }
    }

    private static func dayBasedStreak(for schedule: some Scheduled, vacation: Vacation, calendar: Calendar, referenceDate: Date) -> Int {
        let doneDays = Set(schedule.scheduleDates.map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: referenceDate)

        func counts(_ day: Date) -> Bool {
            Recurrence.isDayScheduled(day, for: schedule, calendar: calendar)
                && !vacation.pauses(schedule.id, on: day, calendar: calendar)
        }

        // Grace: if today is scheduled but not done yet, don't let that break the streak —
        // start counting from yesterday instead. An avoid habit gets no grace: a slip logged
        // today breaks the run today, it isn't "not done yet".
        if !schedule.isAvoid, counts(cursor), !doneDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        var iterations = 0
        let maxIterations = 3650

        while iterations < maxIterations {
            iterations += 1
            if counts(cursor) {
                if doneDays.contains(cursor) {
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
        for schedule: some Scheduled,
        vacation: Vacation,
        component: Calendar.Component,
        maxIterations: Int,
        calendar: Calendar,
        referenceDate: Date
    ) -> Int {
        guard schedule.recurrenceCount > 0, var interval = calendar.dateInterval(of: component, for: referenceDate) else {
            return 0
        }

        let doneDates = schedule.scheduleDates
        var streak = 0
        var isCurrentPeriod = true
        var iterations = 0

        while iterations < maxIterations {
            iterations += 1
            let count = doneDates.filter { interval.contains($0) }.count
            if count >= schedule.recurrenceCount || vacation.pausesEntirePeriod(schedule.id, interval, calendar: calendar) {
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
