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
            milestone.isCompleted = true
            if goal.isTargetReached {
                goal.isCompleted = true
            }
            // No value to snapshot, but the day still counts towards the streak.
            record(value: nil, for: goal, in: context, now: now, calendar: calendar)
            return true
        }
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
                goal.isCompleted = true
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

        WidgetCenter.shared.reloadAllTimelines()
    }
}
