//
//  ReminderFrequency.swift
//  Goals
//

import Foundation

/// How often a goal's reminder fires. Kept separate from the goal's schedule on purpose — you
/// might track a goal three times a week but want to be nudged every morning.
enum ReminderFrequency: String, CaseIterable, Identifiable {
    case daily, weekly

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .daily: String(localized: "reminder.frequency.daily", defaultValue: "Daily", bundle: AppLanguage.currentBundle)
        case .weekly: String(localized: "reminder.frequency.weekly", defaultValue: "Weekly", bundle: AppLanguage.currentBundle)
        }
    }
}
