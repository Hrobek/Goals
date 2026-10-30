//
//  Scheduled.swift
//  Goals
//

import Foundation

/// Anything that repeats on a recurrence schedule and records the days it was done: a `Goal`
/// (through its check-ins) or a `Habit` (through its entries). Lets `Recurrence` and
/// `StreakCalculator` — and the activity heatmap — work off either without knowing which.
protocol Scheduled {
    /// The item's own id — lets streak / activity code look it up in the current `Vacation`.
    var id: UUID { get }
    var recurrenceType: RecurrenceType { get }
    var recurrenceWeekdays: [Int] { get }
    var recurrenceDaysOfMonth: [Int] { get }
    var recurrenceCount: Int { get }
    /// The day this thing begins. Days before it are never scheduled — the goal or habit didn't
    /// exist yet. Defaults to the row's creation date.
    var startDate: Date { get }
    /// Every day this thing counts as done — a check-in date for a goal, a met-target entry date
    /// for a habit. Not de-duplicated or start-of-day'd; callers do that as they need.
    var scheduleDates: [Date] { get }
    /// An "avoid" habit — success is a day with no entry, so `scheduleDates` already lists the
    /// clean days. The streak counter uses this to drop the "not done yet today" grace: a slip is
    /// a slip the moment it's logged. Always `false` for a goal.
    var isAvoid: Bool { get }
}

extension Scheduled {
    var isAvoid: Bool { false }
}

/// A plain copy of a schedule, taken once before a day-by-day walk. Every property read on a
/// `Goal` or `Habit` goes through SwiftData's backing store, and `scheduleDates` itself is real
/// work (a habit dedupes its entries, an avoid habit walks every day since it started) - so the
/// streak walks, which read these on every day they step over, read them from here instead.
struct ScheduleSnapshot: Scheduled {
    let id: UUID
    let recurrenceType: RecurrenceType
    let recurrenceWeekdays: [Int]
    let recurrenceDaysOfMonth: [Int]
    let recurrenceCount: Int
    let startDate: Date
    let scheduleDates: [Date]
    let isAvoid: Bool

    init(_ schedule: some Scheduled) {
        if let snapshot = schedule as? ScheduleSnapshot {
            self = snapshot
            return
        }
        id = schedule.id
        recurrenceType = schedule.recurrenceType
        recurrenceWeekdays = schedule.recurrenceWeekdays
        recurrenceDaysOfMonth = schedule.recurrenceDaysOfMonth
        recurrenceCount = schedule.recurrenceCount
        startDate = schedule.startDate
        scheduleDates = schedule.scheduleDates
        isAvoid = schedule.isAvoid
    }
}
