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
    case openGoal

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .quickAction: String(localized: "widget.action.quick", defaultValue: "Quick action", bundle: AppLanguage.currentBundle)
        case .openGoal: String(localized: "widget.action.open", defaultValue: "Open goal", bundle: AppLanguage.currentBundle)
        }
    }
}
