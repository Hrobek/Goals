//
//  ProgressLogger.swift
//  Goals
//

import Foundation
import SwiftData
import WidgetKit

/// Single entry point for "I made progress today", shared by the quick-add buttons and the
/// log sheet. Keeps at most one check-in per day so streaks count days, not taps.
enum ProgressLogger {
    /// Set once at launch by the app target (never the widget extensions - HealthKit isn't
    /// available there, and this file has to stay importable by them). Fires after `currentValue`
    /// changes on a `.write`-linked goal, with the net change and the check-in that change landed
    /// on, so the hook can mirror exactly that delta into Health.
    static var healthWriteHook: ((_ goal: Goal, _ checkIn: CheckIn, _ delta: Double) -> Void)?
    /// Same wiring as `healthWriteHook`. Fires with the samples a deleted check-in wrote, so they
    /// leave Health with it.
    static var healthDiscardHook: ((_ goal: Goal, _ sampleIDs: [String]) -> Void)?

    /// The goal's one-tap action, as configured on the goal. Shared by the widget button and any
    /// in-app shortcut so both leave the same trace.
    @discardableResult
    static func performQuickAction(
        on goal: Goal,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        // Health is the source of truth for a `.read`-linked goal - only `HealthKitSyncEngine`
        // (via `record`) may change its value, so every tap-driven surface is a no-op.
        guard goal.healthKitDirection != .read else { return false }
        if goal.widgetAction == .complete {
            guard !goal.isCompleted else { return false }
            markCompleted(goal)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .checkInDidChange, object: nil)
            return true
        }

        switch goal.trackingMode {
        case .value:
            let delta = goal.isLowerBetter ? -goal.widgetQuickAmount : goal.widgetQuickAmount
            record(value: max(goal.currentValue + delta, 0), for: goal, in: context, now: now, calendar: calendar)
            return true
        case .milestones:
            guard let milestone = goal.nextMilestone else { return false }
            toggleMilestone(milestone, on: goal, in: context, now: now, calendar: calendar)
            return true
        }
    }

    /// Reverses a logged amount — by default the goal's one-tap action (the exact inverse of
    /// `performQuickAction`, for correcting a stray tap on the Today row or widget button), or a
    /// specific `delta` a caller knows it needs to back out instead — a bigger quick-add chip
    /// tapped by mistake in the detail view, say, rather than the widget's own configured step.
    /// Unlike a normal log, this never establishes a fresh streak day on its own: if undoing
    /// brings today's value back down to (or below) whatever it stood at before today, today's
    /// check-in is retracted too, so an add-then-undo within the same day leaves no streak credit
    /// behind.
    @discardableResult
    static func undoQuickAction(
        on goal: Goal,
        delta: Double? = nil,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard goal.trackingMode == .value, goal.healthKitDirection != .read else { return false }

        let delta = delta ?? (goal.isLowerBetter ? goal.widgetQuickAmount : -goal.widgetQuickAmount)
        let newValue = max(goal.currentValue + delta, 0)
        guard newValue != goal.currentValue else { return false }
        let actualDelta = newValue - goal.currentValue

        goal.currentValue = newValue
        if goal.isCompleted, !goal.isTargetReached {
            goal.isCompleted = false
        }

        let priorValue = goal.checkIns
            .filter { !calendar.isDate($0.date, inSameDayAs: now) }
            .max { $0.date < $1.date }?
            .valueSnapshot ?? 0

        if let today = goal.checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            mirrorHealthDelta(goal, checkIn: today, delta: actualDelta)
            if newValue > priorValue {
                today.date = now
                today.valueSnapshot = newValue
            } else {
                context.delete(today)
            }
        }
        // No check-in for today yet: undoing shouldn't create one — there's nothing to retract.

        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .checkInDidChange, object: nil)
        return true
    }

    /// Ticks or unticks one milestone, keeping the goal's completion and today's check-in in sync
    /// — the same bookkeeping `performQuickAction` does, but for any milestone (not just the next
    /// one) and reversible, so a card can offer plain checkboxes.
    @discardableResult
    static func toggleMilestone(
        _ milestone: Milestone,
        on goal: Goal,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard goal.healthKitDirection != .read else { return milestone.isCompleted }
        milestone.isCompleted.toggle()
        if milestone.isCompleted {
            if goal.isTargetReached {
                markCompleted(goal)
            }
            // No value to snapshot, but the day still counts towards the streak.
            record(value: nil, for: goal, in: context, now: now, calendar: calendar)
        } else if goal.isCompleted, !goal.isTargetReached {
            // Unticking after every milestone was done reopens the goal.
            goal.isCompleted = false
        }
        return milestone.isCompleted
    }

    static func record(
        value newValue: Double?,
        note: String? = nil,
        for goal: Goal,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let priorValue = goal.currentValue
        if let newValue {
            goal.currentValue = newValue
            if goal.isTargetReached {
                markCompleted(goal)
            }
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        let checkIn: CheckIn
        if let today = goal.checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            today.date = now
            if newValue != nil {
                today.valueSnapshot = goal.currentValue
            }
            if let resolvedNote {
                today.note = resolvedNote
            }
            checkIn = today
        } else {
            let inserted = CheckIn(
                ownerId: goal.ownerId,
                date: now,
                note: resolvedNote,
                valueSnapshot: newValue == nil ? nil : goal.currentValue,
                goal: goal
            )
            context.insert(inserted)
            checkIn = inserted
        }

        if let newValue, newValue != priorValue {
            mirrorHealthDelta(goal, checkIn: checkIn, delta: newValue - priorValue)
        }

        Analytics.send(.checkInLogged, [.trackingMode: goal.trackingMode.rawValue])
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .checkInDidChange, object: nil)
    }

    // MARK: - History

    // A check-in's `valueSnapshot` is where the goal stood after that day, not what the day added.
    // So changing a past day of a running total also moves every later snapshot, and the goal's
    // value, by the same amount. A lower-is-better goal's snapshots are readings of their own, so
    // only the goal's value follows, and only when the newest reading changes.

    /// What a check-in's day logged, in the terms the user logs in: the amount added that day for a
    /// running total, the reading itself for a lower-is-better goal. Nil for a milestone day.
    static func loggedValue(of checkIn: CheckIn, on goal: Goal) -> Double? {
        guard goal.trackingMode == .value, let snapshot = checkIn.valueSnapshot else { return nil }
        if goal.isLowerBetter { return snapshot }
        return snapshot - (snapshotValue(before: checkIn.date, on: goal, excluding: checkIn) ?? goal.startValue)
    }

    /// Logs a day after the fact, or adds to a day that already has a check-in. `value` is in
    /// `loggedValue` terms. A backfill is a correction, not progress made just now, so callers
    /// don't celebrate it.
    static func log(
        value: Double?,
        note: String?,
        on day: Date,
        for goal: Goal,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard goal.healthKitDirection != .read else { return }

        if let existing = goal.checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            var dayValue = value
            if let value, !goal.isLowerBetter {
                dayValue = (loggedValue(of: existing, on: goal) ?? 0) + value
            }
            let resolvedNote = resolved(note) ?? existing.note
            edit(existing, on: goal, value: dayValue, note: resolvedNote, in: context)
            return
        }

        // Today keeps the moment it was logged, like a normal check-in. A past day sits at noon,
        // clear of either midnight whatever the time zone does next.
        let date = calendar.isDate(day, inSameDayAs: now)
            ? now
            : calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day

        var snapshot: Double?
        if goal.trackingMode == .value, let value {
            if goal.isLowerBetter {
                snapshot = value
                if !hasSnapshot(after: date, on: goal) {
                    goal.currentValue = value
                }
            } else {
                snapshot = (snapshotValue(before: date, on: goal, excluding: nil) ?? goal.startValue) + value
                shiftSnapshots(after: date, on: goal, by: value)
                goal.currentValue = max(goal.currentValue + value, 0)
            }
        }

        let checkIn = CheckIn(ownerId: goal.ownerId, date: date, note: resolved(note), valueSnapshot: snapshot, goal: goal)
        context.insert(checkIn)
        if snapshot != nil {
            mirrorHealthDelta(goal, checkIn: checkIn, delta: snapshot ?? 0)
        }
        settleCompletion(goal)

        Analytics.send(.checkInLogged, [.trackingMode: goal.trackingMode.rawValue])
        didChange()
    }

    /// Rewrites one past check-in's value (in `loggedValue` terms) and note. A nil `value` leaves
    /// the value alone, as it does for a milestone day.
    static func edit(
        _ checkIn: CheckIn,
        on goal: Goal,
        value: Double?,
        note: String?,
        in context: ModelContext
    ) {
        guard goal.healthKitDirection != .read else { return }
        checkIn.note = resolved(note)

        let old = loggedValue(of: checkIn, on: goal)
        if goal.trackingMode == .value, let value, value != old {
            // A day without a snapshot (one logged while the goal still tracked milestones) has
            // added nothing so far.
            let delta = value - (old ?? 0)
            if goal.isLowerBetter {
                checkIn.valueSnapshot = value
                if !hasSnapshot(after: checkIn.date, on: goal) {
                    goal.currentValue = value
                }
            } else {
                checkIn.valueSnapshot = (snapshotValue(before: checkIn.date, on: goal, excluding: checkIn) ?? goal.startValue) + value
                shiftSnapshots(after: checkIn.date, on: goal, by: delta)
                goal.currentValue = max(goal.currentValue + delta, 0)
            }
            mirrorHealthDelta(goal, checkIn: checkIn, delta: delta)
            settleCompletion(goal)
        }

        didChange()
    }

    /// Removes a check-in and what it logged, taking its Health samples along.
    static func delete(_ checkIn: CheckIn, from goal: Goal, in context: ModelContext) {
        guard goal.healthKitDirection != .read else { return }

        if goal.trackingMode == .value, let logged = loggedValue(of: checkIn, on: goal) {
            if goal.isLowerBetter {
                if !hasSnapshot(after: checkIn.date, on: goal) {
                    goal.currentValue = snapshotValue(before: checkIn.date, on: goal, excluding: checkIn) ?? goal.startValue
                }
            } else {
                shiftSnapshots(after: checkIn.date, on: goal, by: -logged)
                goal.currentValue = max(goal.currentValue - logged, 0)
            }
        }

        if !checkIn.healthKitSampleIDs.isEmpty {
            healthDiscardHook?(goal, checkIn.healthKitSampleIDs)
        }
        context.delete(checkIn)
        settleCompletion(goal)
        didChange()
    }

    /// The newest snapshot from before `date`.
    private static func snapshotValue(before date: Date, on goal: Goal, excluding checkIn: CheckIn?) -> Double? {
        goal.checkIns
            .filter { $0 !== checkIn && $0.date < date && $0.valueSnapshot != nil }
            .max { $0.date < $1.date }?
            .valueSnapshot
    }

    private static func hasSnapshot(after date: Date, on goal: Goal) -> Bool {
        goal.checkIns.contains { $0.date > date && $0.valueSnapshot != nil }
    }

    private static func shiftSnapshots(after date: Date, on goal: Goal, by delta: Double) {
        for later in goal.checkIns where later.date > date {
            if let value = later.valueSnapshot {
                later.valueSnapshot = value + delta
            }
        }
    }

    /// A changed value can finish the goal or take it back below its target. Milestone goals
    /// finish by their milestones, which history doesn't touch.
    private static func settleCompletion(_ goal: Goal) {
        guard goal.trackingMode == .value else { return }
        if goal.isTargetReached {
            markCompleted(goal)
        } else if goal.isCompleted {
            goal.isCompleted = false
        }
    }

    private static func resolved(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private static func didChange() {
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .checkInDidChange, object: nil)
    }

    private static func mirrorHealthDelta(_ goal: Goal, checkIn: CheckIn, delta: Double) {
        guard delta != 0, goal.healthKitDirection == .write, goal.healthKitMetric != nil else { return }
        guard let healthWriteHook else {
            // Running in the widget extension, which has no HealthKit access - flag the check-in
            // so the app target catches it up next time it's foregrounded.
            checkIn.needsHealthKitWriteSync = true
            return
        }
        healthWriteHook(goal, checkIn, delta)
    }

    /// Guarded, so a goal that's already done doesn't report finishing again — a later check-in on
    /// a completed goal would otherwise count as a second completion.
    private static func markCompleted(_ goal: Goal) {
        guard !goal.isCompleted else { return }
        goal.isCompleted = true
        Analytics.send(.goalCompleted, [.trackingMode: goal.trackingMode.rawValue])
    }
}
