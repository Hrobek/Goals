//
//  HabitLogger.swift
//  Goals
//

import Foundation
import SwiftData
import WidgetKit

/// Single entry point for "I did this habit today", shared by the in-app row and the widget
/// button. Keeps at most one `HabitEntry` per day; `count` carries habits that want several ticks
/// a day ("8 glasses of water").
enum HabitLogger {
    /// One tap on the habit's check-off control.
    /// - `dailyTarget == 1`: toggles today's entry on/off.
    /// - `dailyTarget > 1`: adds one tick, capped at the target; a fresh tap once the target is
    ///   reached clears the day (so the control can still undo a mistake).
    @discardableResult
    static func toggleToday(
        _ habit: Habit,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let existing = habit.entry(on: now, calendar: calendar)

        if habit.dailyTarget <= 1 {
            if let existing {
                context.delete(existing)
            } else {
                insert(count: 1, for: habit, in: context, now: now)
            }
        } else {
            let current = existing?.count ?? 0
            if current >= habit.dailyTarget {
                if let existing { context.delete(existing) }
            } else if let existing {
                existing.count = current + 1
                existing.date = now
            } else {
                insert(count: 1, for: habit, in: context, now: now)
            }
        }

        finish(habit)
        return habit.isDone(on: now, calendar: calendar)
    }

    /// Steps today's tick count by `delta` (clamped to 0…dailyTarget), for the stepper on
    /// multi-tick habits. Removes the entry when it lands back on zero.
    @discardableResult
    static func adjustToday(
        _ habit: Habit,
        by delta: Int,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let existing = habit.entry(on: now, calendar: calendar)
        let current = existing?.count ?? 0
        let updated = min(max(current + delta, 0), max(habit.dailyTarget, 1))
        guard updated != current else { return habit.isDone(on: now, calendar: calendar) }

        if updated == 0 {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.count = updated
            existing.date = now
        } else {
            insert(count: updated, for: habit, in: context, now: now)
        }

        finish(habit)
        return habit.isDone(on: now, calendar: calendar)
    }

    // MARK: - Private

    private static func insert(count: Int, for habit: Habit, in context: ModelContext, now: Date) {
        context.insert(HabitEntry(ownerId: habit.ownerId, date: now, count: count, habit: habit))
    }

    private static func finish(_ habit: Habit) {
        Analytics.send(.habitCheckIn)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
