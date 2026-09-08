//
//  StreakFreeze.swift
//  Goals
//

import Foundation
import SwiftData

/// One day rescued from breaking a streak. A `StreakFreeze` row means "treat this scheduled day
/// as done even though it wasn't" — `StreakCalculator` reads it exactly like a real check-in.
///
/// Rows are the synced source of truth: a freeze spent on the phone reaches the iPad and the
/// watch through CloudKit, so every device counts the streak the same way. The freeze *bank*
/// (how many are left to spend, whether the feature is on) is device-local — see `FreezeBank` —
/// the same split `Vacation` uses.
///
/// Only day-based schedules (daily / specific weekdays / specific days of month) can be frozen;
/// a "times per week/month" quota already carries its own slack. Avoid habits can't be frozen
/// either — a slip is a slip the moment it's logged.
@Model
final class StreakFreeze {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    /// The habit or goal this freeze protects.
    var itemID: UUID = UUID()
    /// Which model `itemID` points at, so a reconcile / undo can look it up without probing both.
    var isHabit: Bool = false
    /// The rescued day, normalised to start-of-day.
    var day: Date = Date.now
    /// When the freeze was applied — used to keep "Streak freeze used" / undo scoped to a recent,
    /// still-relevant save rather than one from months ago.
    var appliedAt: Date = Date.now
    /// `true` when the Pro auto-reconcile spent it, `false` when the user tapped "Protect streak".
    /// Only an automatic freeze offers an undo.
    var wasAutomatic: Bool = false

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        itemID: UUID,
        isHabit: Bool,
        day: Date,
        appliedAt: Date = .now,
        wasAutomatic: Bool
    ) {
        self.id = id
        self.ownerId = ownerId
        self.itemID = itemID
        self.isHabit = isHabit
        self.day = Calendar.current.startOfDay(for: day)
        self.appliedAt = appliedAt
        self.wasAutomatic = wasAutomatic
    }
}
