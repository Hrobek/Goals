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
    /// Set once at launch by the app target (never the widget extensions - HealthKit isn't
    /// available there, and this file has to stay importable by them). Fires after every change to
    /// a habit's logged amount for a `.write`-linked habit, with the net change for the day and the
    /// entry that change landed on, so the hook can mirror exactly that delta into Health and record
    /// which sample(s) it wrote on the entry itself.
    static var healthWriteHook: ((_ habit: Habit, _ entry: HabitEntry, _ delta: Double) -> Void)?

    private static func mirrorHealthDelta(_ habit: Habit, entry: HabitEntry, delta: Double) {
        guard delta != 0, habit.healthKitDirection == .write, habit.healthKitMetric != nil else { return }
        healthWriteHook?(habit, entry, delta)
    }

    /// One tap on a **checkbox** habit's control: toggles today's entry on or off.
    @discardableResult
    static func toggleToday(
        _ habit: Habit,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        // Health is the source of truth for a `.read`-linked habit - only `HealthKitSyncEngine`
        // (via `setAmount`) may change its logged amount, so every tap-driven surface is a no-op.
        guard habit.healthKitDirection != .read else { return habit.isDone(on: now, calendar: calendar) }
        if let existing = habit.entry(on: now, calendar: calendar) {
            mirrorHealthDelta(habit, entry: existing, delta: -existing.amount)
            context.delete(existing)
        } else {
            let entry = insert(amount: 1, for: habit, in: context, now: now)
            mirrorHealthDelta(habit, entry: entry, delta: 1)
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
        guard habit.healthKitDirection != .read else { return habit.isDone(on: now, calendar: calendar) }
        let existing = habit.entry(on: now, calendar: calendar)
        let current = existing?.amount ?? 0
        var updated = max(current + delta, 0)
        // A step bigger than what's left shouldn't be able to jump past the day's target in one
        // tap - +25 at 0/20 pages lands on exactly 20, not 25. Not for a quota habit: its day can
        // legitimately hold more than one contribution, so there's no per-day ceiling to clamp to.
        if delta > 0, !habit.isQuota {
            updated = min(updated, habit.effectiveTarget)
        }
        guard updated != current else { return habit.isDone(on: now, calendar: calendar) }
        let netDelta = updated - current

        if updated == 0 {
            if let existing {
                mirrorHealthDelta(habit, entry: existing, delta: netDelta)
                context.delete(existing)
            }
        } else if let existing {
            existing.amount = updated
            existing.date = now
            mirrorHealthDelta(habit, entry: existing, delta: netDelta)
        } else {
            let entry = insert(amount: updated, for: habit, in: context, now: now)
            mirrorHealthDelta(habit, entry: entry, delta: netDelta)
        }

        finish()
        return habit.isDone(on: now, calendar: calendar)
    }

    /// One quick-add step for a value habit — the amount configured on the habit (also what one
    /// widget tap adds). A no-op once the habit's already done, on any schedule: `isDone` already
    /// knows how to ask that for a quota habit (the period's tally) as much as a plain daily one,
    /// so this is the one place that keeps every tap-to-add surface — the Today row, the widget,
    /// the Lock Screen button — from running an already-finished habit past its target.
    @discardableResult
    static func addQuick(_ habit: Habit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !habit.isDone(on: now, calendar: calendar) else { return true }
        return adjust(habit, by: habit.widgetQuickAmount, in: context, now: now, calendar: calendar)
    }

    /// One tap on a times-counter habit's control ("stretch 3× a day"): steps the count up by one
    /// until the day's target is met, then the next tap steps it back down. Keeps an over-tap as
    /// easy to walk back as a checkbox, and stops the tally running past the target.
    ///
    /// A quota schedule ("5× a week") toggles this day's own contribution: taps it on if today
    /// hasn't logged yet, taps it back off if it has — so a mis-tap is always one tap away from
    /// undone, on whichever day it happened. Stays capped at the quota: once the period's already
    /// met from other days, a tap on a fresh day does nothing rather than running past it.
    @discardableResult
    static func cycle(
        _ habit: Habit,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !habit.isQuota else {
            if habit.entry(on: now, calendar: calendar) != nil {
                return adjust(habit, by: -1, in: context, now: now, calendar: calendar)
            }
            guard habit.periodCount(on: now, calendar: calendar) < habit.quotaTarget else {
                return habit.isDone(on: now, calendar: calendar)
            }
            return adjust(habit, by: 1, in: context, now: now, calendar: calendar)
        }
        let current = habit.amount(on: now, calendar: calendar)
        let delta: Double = current >= habit.effectiveTarget ? -1 : 1
        return adjust(habit, by: delta, in: context, now: now, calendar: calendar)
    }

    /// The "complete" tap. Finishes the current occurrence in one go — today for a day-based
    /// habit, the week/month tally for a quota schedule; tapping again when it's already done
    /// clears today's contribution, so a stray tap is easy to take back.
    static func completeOccurrence(
        _ habit: Habit,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard habit.healthKitDirection != .read else { return }
        if habit.isDone(on: now, calendar: calendar) {
            if let today = habit.entry(on: now, calendar: calendar) {
                context.delete(today)
                finish()
            }
            return
        }

        if habit.isQuota {
            let remaining = habit.quotaTarget - habit.periodCount(on: now, calendar: calendar)
            guard remaining > 0 else { return }
            adjust(habit, by: Double(remaining), in: context, now: now, calendar: calendar)
        } else {
            setAmount(habit, to: habit.effectiveTarget, in: context, now: now, calendar: calendar)
        }
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
            let netDelta = clamped - existing.amount
            if clamped == 0 {
                mirrorHealthDelta(habit, entry: existing, delta: netDelta)
                context.delete(existing)
            } else {
                existing.amount = clamped
                existing.date = now
                mirrorHealthDelta(habit, entry: existing, delta: netDelta)
            }
        } else if clamped > 0 {
            let entry = insert(amount: clamped, for: habit, in: context, now: now)
            mirrorHealthDelta(habit, entry: entry, delta: clamped)
        }
        finish()
    }

    // MARK: - Private

    @discardableResult
    private static func insert(amount: Double, for habit: Habit, in context: ModelContext, now: Date) -> HabitEntry {
        let entry = HabitEntry(ownerId: habit.ownerId, date: now, amount: amount, habit: habit)
        context.insert(entry)
        return entry
    }

    private static func finish() {
        Analytics.send(.habitCheckIn)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .checkInDidChange, object: nil)
    }
}
