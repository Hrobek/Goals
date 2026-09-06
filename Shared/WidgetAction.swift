//
//  WidgetAction.swift
//  Goals
//

import Foundation

/// What tapping the goal on the home screen does. Set per goal, because a "log 2 km" button makes
/// sense for some goals and is a liability for others.
enum WidgetAction: String, CaseIterable, Identifiable {
    /// Adds the goal's quick amount, or ticks off its next unfinished milestone.
    case quickAction
    /// One tap marks the whole goal complete — the same as the "Mark completed" switch in the
    /// detail. Doesn't touch the logged value.
    case complete
    case openGoal

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .quickAction: String(localized: "widget.action.quick", defaultValue: "Quick action", bundle: AppLanguage.currentBundle)
        case .complete: String(localized: "widget.action.complete", defaultValue: "Complete", bundle: AppLanguage.currentBundle)
        case .openGoal: String(localized: "widget.action.open", defaultValue: "Open goal", bundle: AppLanguage.currentBundle)
        }
    }
}

/// What a tap on a habit does — from the widget ring and from the row/detail control.
enum HabitWidgetAction: String, CaseIterable, Identifiable {
    /// The default: +1 / toggle / one quick-add step.
    case checkOff
    /// One tap finishes the current occurrence outright — the day for a daily habit, the whole
    /// week/month tally for a quota schedule.
    case complete

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .checkOff: String(localized: "habit.action.checkOff", defaultValue: "Check off", bundle: AppLanguage.currentBundle)
        case .complete: String(localized: "habit.action.complete", defaultValue: "Complete", bundle: AppLanguage.currentBundle)
        }
    }
}
