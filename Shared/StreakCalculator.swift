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
        // A day rescued by a streak freeze counts exactly like a done day. Avoid habits are never
        // frozen — a slip is a slip — so don't even look.
        let frozenDays = schedule.isAvoid ? [] : FreezeLedger.frozenDays(for: schedule.id)
        let startFloor = calendar.startOfDay(for: schedule.startDate)
        var cursor = calendar.startOfDay(for: referenceDate)

        func counts(_ day: Date) -> Bool {
            Recurrence.isDayScheduled(day, for: schedule, calendar: calendar)
                && !vacation.pauses(schedule.id, on: day, calendar: calendar)
        }
        func isMet(_ day: Date) -> Bool { doneDays.contains(day) || frozenDays.contains(day) }

        // Grace: if today is scheduled but not done yet, don't let that break the streak —
        // start counting from yesterday instead. An avoid habit gets no grace: a slip logged
        // today breaks the run today, it isn't "not done yet".
        if !schedule.isAvoid, counts(cursor), !isMet(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        var iterations = 0
        let maxIterations = 3650

        while iterations < maxIterations {
            iterations += 1
            if cursor < startFloor { break }
            if counts(cursor) {
                if isMet(cursor) {
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

    /// How recent a missed day can be and still be rescued by a manual freeze — and, mirrored, how
    /// long an applied freeze stays offered for undo.
    static let freezeWindowDays = 14

    /// The one missed day a streak freeze would rescue: the most recent unmet scheduled day that
    /// is sitting between two met scheduled days (a done day further back to reconnect to, and at
    /// least one done day — or nothing but non-scheduled days — between it and today). Bridging it
    /// splices a broken run back together.
    ///
    /// `nil` when: there is no such gap, the lapse is two or more scheduled days in a row (one
    /// freeze only covers one), the gap is older than `freezeWindowDays`, there's no earlier run
    /// to reconnect to, or the schedule is an avoid habit / not day-based.
    static func repairableGap(
        for schedule: some Scheduled,
        calendar: Calendar = .current,
        referenceDate: Date = .now
    ) -> Date? {
        guard !schedule.isAvoid else { return nil }
        switch schedule.recurrenceType {
        case .daily, .specificWeekdays, .specificDaysOfMonth:
            break
        case .timesPerWeek, .timesPerMonth:
            return nil
        }

        let vacation = Vacation.current()
        let doneDays = Set(schedule.scheduleDates.map { calendar.startOfDay(for: $0) })
        let frozenDays = FreezeLedger.frozenDays(for: schedule.id)
        let startFloor = calendar.startOfDay(for: schedule.startDate)
        let today = calendar.startOfDay(for: referenceDate)
        let windowFloor = calendar.date(byAdding: .day, value: -freezeWindowDays, to: today) ?? startFloor

        func counts(_ day: Date) -> Bool {
            Recurrence.isDayScheduled(day, for: schedule, calendar: calendar)
                && !vacation.pauses(schedule.id, on: day, calendar: calendar)
        }
        func isMet(_ day: Date) -> Bool { doneDays.contains(day) || frozenDays.contains(day) }
        func stepBack(_ day: Date) -> Date? { calendar.date(byAdding: .day, value: -1, to: day) }

        // Walk back from today over met (and unscheduled) days; stop at the first scheduled day
        // that wasn't done. An unmet *today* is skipped — same grace the count uses, it isn't a
        // missed day yet.
        var cursor = today
        var iterations = 0
        while true {
            iterations += 1
            if iterations > 800 { return nil }
            if cursor < startFloor || cursor < windowFloor { return nil }
            if counts(cursor) {
                if cursor == today, !isMet(cursor) {
                    // today not done yet — keep looking further back
                } else if isMet(cursor) {
                    // a met scheduled day — keep walking back
                } else {
                    break
                }
            }
            guard let previous = stepBack(cursor) else { return nil }
            cursor = previous
        }
        let gapDay = cursor

        // The scheduled day just before the gap has to be met, or the lapse is longer than one
        // day and no single freeze brings the run back.
        var previous = gapDay
        repeat {
            guard let earlier = stepBack(previous) else { return nil }
            previous = earlier
            if previous < startFloor { return nil }
        } while !counts(previous)
        return isMet(previous) ? gapDay : nil
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
        let startFloor = calendar.startOfDay(for: schedule.startDate)
        var streak = 0
        var isCurrentPeriod = true
        var iterations = 0

        while iterations < maxIterations {
            iterations += 1
            // A period that ended before the schedule began can't extend the streak.
            if interval.end <= startFloor { break }
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
