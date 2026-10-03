//
//  HabitEntry.swift
//  Goals
//

import Foundation
import SwiftData

/// One day's worth of doing a habit. At most one per (habit, day) — `HabitLogger` keeps it that
/// way. `amount` is the value logged for the day: 1 for a plain checkbox habit, or a real quantity
/// (3000 ml, 8 pages) for a habit that tracks a unit.
@Model
final class HabitEntry {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var date: Date = Date.now
    /// Kept only so an older row still opens; new writes go through `storedAmount`.
    var count: Int = 1
    private var storedAmount: Double?
    /// UUIDs (as strings - SwiftData/CloudKit arrays stick to primitive scalars) of the HealthKit
    /// samples this entry wrote, for a `.write`-linked habit. Lets a later undo or edit delete
    /// exactly the samples this entry is responsible for, instead of guessing at Health's own data.
    private var storedHealthKitSampleIDs: [String]?
    /// Set when a `.write`-linked habit changes this entry outside the app target (the widget or
    /// the watch app), where `HabitLogger.healthWriteHook` is never wired up. Lets
    /// `HealthKitWriteSync.reconcilePending` catch this entry up into Health next time the app
    /// itself comes to the foreground, instead of the write silently never happening.
    var needsHealthKitWriteSync: Bool = false
    var habit: Habit?

    init(id: UUID = UUID(), ownerId: UUID, date: Date = .now, amount: Double = 1, habit: Habit? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.date = date
        self.count = Int(amount.rounded())
        self.storedAmount = amount
        self.habit = habit
    }

    /// The value logged for this day. Falls back to the legacy integer `count` for rows written
    /// before the habit unit rework.
    var amount: Double {
        get { storedAmount ?? Double(count) }
        set {
            storedAmount = newValue
            count = Int(newValue.rounded())
        }
    }

    /// Which of two entries for the same day counts. Normally a day has just one, but a day
    /// logged on the phone and the watch before either had synced the other's row ends up with
    /// two. The higher amount wins; the later write and then the id break ties, so every device
    /// picks the same one and they never disagree about the day.
    static func ranksAbove(_ lhs: HabitEntry, _ rhs: HabitEntry) -> Bool {
        if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    var healthKitSampleIDs: [String] {
        get { storedHealthKitSampleIDs ?? [] }
        set { storedHealthKitSampleIDs = newValue.isEmpty ? nil : newValue }
    }
}
