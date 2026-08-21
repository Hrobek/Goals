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
    /// The goal's one-tap action, as configured on the goal. Shared by the widget button and any
    /// in-app shortcut so both leave the same trace.
    @discardableResult
    static func performQuickAction(
        on goal: Goal,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
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
        if let newValue {
            goal.currentValue = newValue
            if goal.isTargetReached {
                markCompleted(goal)
            }
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        if let today = goal.checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            today.date = now
            if newValue != nil {
                today.valueSnapshot = goal.currentValue
            }
            if let resolvedNote {
                today.note = resolvedNote
            }
        } else {
            context.insert(CheckIn(
                date: now,
                note: resolvedNote,
                valueSnapshot: newValue == nil ? nil : goal.currentValue,
                goal: goal
            ))
        }

        Analytics.send(.checkInLogged, [.trackingMode: goal.trackingMode.rawValue])
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Guarded, so a goal that's already done doesn't report finishing again — a later check-in on
    /// a completed goal would otherwise count as a second completion.
    private static func markCompleted(_ goal: Goal) {
        guard !goal.isCompleted else { return }
        goal.isCompleted = true
        Analytics.send(.goalCompleted, [.trackingMode: goal.trackingMode.rawValue])
    }
}
