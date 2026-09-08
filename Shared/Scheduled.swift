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
