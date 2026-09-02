//
//  GoalTemplate.swift
//  Goals
//

import Foundation

/// A ready-made starting point for a goal, offered to a new user so their first goal is a couple
/// of taps instead of a blank form. Picking one opens the normal Add Goal sheet with these values
/// filled in — everything stays editable, nothing is created until the user hits Save.
struct GoalTemplate: Identifiable, Hashable {
    /// Stable identifier: the analytics tag and the localization-key suffix (`template.<id>.title`).
    let id: String
    let emoji: String
    let trackingMode: GoalTrackingMode
    let startValue: Double
    let targetValue: Double
    let isLowerBetter: Bool
    let unit: GoalUnit
    let recurrenceType: RecurrenceType
    /// Only meaningful for the quota recurrence types; ignored for `.daily`.
    let recurrenceCount: Int
    /// One of the four seeded category keys ("health" / "career" / "finance" / "relationships"),
    /// or nil to leave the goal uncategorised. Resolved to the user's own `Category` at pick time.
    let categoryDefaultKey: String?

    /// The catalogue, in display order. Kept short on purpose — a wall of templates is its own
    /// kind of blank page.
    static let all: [GoalTemplate] = [
        GoalTemplate(id: "run", emoji: "🏃", trackingMode: .value, startValue: 0, targetValue: 100,
                     isLowerBetter: false, unit: .km, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "steps", emoji: "👟", trackingMode: .value, startValue: 0, targetValue: 10000,
                     isLowerBetter: false, unit: .steps, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "read", emoji: "📚", trackingMode: .value, startValue: 0, targetValue: 20,
                     isLowerBetter: false, unit: .pages, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: nil),
        GoalTemplate(id: "meditate", emoji: "🧘", trackingMode: .value, startValue: 0, targetValue: 10,
                     isLowerBetter: false, unit: .minutes, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "water", emoji: "💧", trackingMode: .value, startValue: 0, targetValue: 8,
                     isLowerBetter: false, unit: .glasses, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "workout", emoji: "🏋️", trackingMode: .value, startValue: 0, targetValue: 36,
                     isLowerBetter: false, unit: .times, recurrenceType: .timesPerWeek, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "weight", emoji: "⚖️", trackingMode: .value, startValue: 5, targetValue: 0,
                     isLowerBetter: true, unit: .kg, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "savings", emoji: "💰", trackingMode: .value, startValue: 0, targetValue: 10000,
                     isLowerBetter: false, unit: .czk, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "finance"),
        GoalTemplate(id: "noSpend", emoji: "🚫", trackingMode: .value, startValue: 0, targetValue: 30,
                     isLowerBetter: false, unit: .days, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "finance"),
    ]

    /// The goal title this template seeds, in the app's current language. A literal key per case,
    /// so each carries a real English fallback the way the rest of the app's enums do.
    var localizedTitle: String {
        switch id {
        case "run": String(localized: "template.run.title", defaultValue: "Run 100 km", bundle: AppLanguage.currentBundle)
        case "steps": String(localized: "template.steps.title", defaultValue: "Walk 10,000 steps a day", bundle: AppLanguage.currentBundle)
        case "read": String(localized: "template.read.title", defaultValue: "Read 20 pages a day", bundle: AppLanguage.currentBundle)
        case "meditate": String(localized: "template.meditate.title", defaultValue: "Meditate 10 minutes a day", bundle: AppLanguage.currentBundle)
        case "water": String(localized: "template.water.title", defaultValue: "Drink 8 glasses of water", bundle: AppLanguage.currentBundle)
        case "workout": String(localized: "template.workout.title", defaultValue: "Work out 3× a week", bundle: AppLanguage.currentBundle)
        case "weight": String(localized: "template.weight.title", defaultValue: "Lose 5 kg", bundle: AppLanguage.currentBundle)
        case "savings": String(localized: "template.savings.title", defaultValue: "Save 10,000", bundle: AppLanguage.currentBundle)
        case "noSpend": String(localized: "template.noSpend.title", defaultValue: "30 days without spending", bundle: AppLanguage.currentBundle)
        default: ""
        }
    }

    /// A one-line schedule descriptor for the picker card — "Every day" or "3×/week".
    var scheduleSummary: String {
        switch recurrenceType {
        case .timesPerWeek:
            return String(localized: "recurrence.summary.timesPerWeek \(recurrenceCount)", bundle: AppLanguage.currentBundle)
        case .timesPerMonth:
            return String(localized: "recurrence.summary.timesPerMonth \(recurrenceCount)", bundle: AppLanguage.currentBundle)
        default:
            return RecurrenceType.daily.localizedName
        }
    }
}
