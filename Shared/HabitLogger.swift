//
//  HabitLogger.swift
//  Goals
//

import Foundation
import SwiftData
import WidgetKit

/// Single entry point for "I did this habit today", shared by the in-app row/detail and the
/// widget button. Keeps at most one `HabitEntry` per day.
enum HabitLogger {
    /// One tap on a **checkbox** habit's control: toggles today's entry on or off.
    @discardableResult
    static func toggleToday(
        _ habit: Habit,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        if let existing = habit.entry(on: now, calendar: calendar) {
            context.delete(existing)
        } else {
            insert(amount: 1, for: habit, in: context, now: now)
        }
        finish()
        return habit.isDone(on: now, calendar: calendar)
    }

    /// Adds `delta` (may be negative) to today's logged amount, for a **value** habit. Clamped at
    /// zero; the day's entry is removed once it lands back on nothing.
    @discardableResult
    static func adjust(
        _ habit: Habit,
        by delta: Double,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let existing = habit.entry(on: now, calendar: calendar)
        let current = existing?.amount ?? 0
        let updated = max(current + delta, 0)
        guard updated != current else { return habit.isDone(on: now, calendar: calendar) }

        if updated == 0 {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.amount = updated
            existing.date = now
        } else {
            insert(amount: updated, for: habit, in: context, now: now)
        }

        finish()
        return habit.isDone(on: now, calendar: calendar)
    }

    /// One quick-add step for a value habit — the amount configured on the habit (also what one
    /// widget tap adds).
    @discardableResult
    static func addQuick(_ habit: Habit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Bool {
        adjust(habit, by: habit.widgetQuickAmount, in: context, now: now, calendar: calendar)
    }

    /// Sets today's amount to an exact value (from the "log value" field).
    static func setAmount(
        _ habit: Habit,
        to value: Double,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let clamped = max(value, 0)
        if let existing = habit.entry(on: now, calendar: calendar) {
            if clamped == 0 {
                context.delete(existing)
            } else {
                existing.amount = clamped
                existing.date = now
            }
        } else if clamped > 0 {
            insert(amount: clamped, for: habit, in: context, now: now)
        }
        finish()
    }

    // MARK: - Private

    private static func insert(amount: Double, for habit: Habit, in context: ModelContext, now: Date) {
        context.insert(HabitEntry(ownerId: habit.ownerId, date: now, amount: amount, habit: habit))
    }

    private static func finish() {
        Analytics.send(.habitCheckIn)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
