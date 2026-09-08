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
        GoalTemplate(id: "runYear", emoji: "🥾", trackingMode: .value, startValue: 0, targetValue: 500,
                     isLowerBetter: false, unit: .km, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: "health"),
        GoalTemplate(id: "books", emoji: "📚", trackingMode: .value, startValue: 0, targetValue: 12,
                     isLowerBetter: false, unit: .books, recurrenceType: .daily, recurrenceCount: 3,
                     categoryDefaultKey: nil),
        GoalTemplate(id: "run10k", emoji: "🏅", trackingMode: .value, startValue: 0, targetValue: 10,
                     isLowerBetter: false, unit: .km, recurrenceType: .daily, recurrenceCount: 3,
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
        case "runYear": String(localized: "template.runYear.title", defaultValue: "Run 500 km this year", bundle: AppLanguage.currentBundle)
        case "books": String(localized: "template.books.title", defaultValue: "Read 12 books", bundle: AppLanguage.currentBundle)
        case "run10k": String(localized: "template.run10k.title", defaultValue: "Run 10 km non-stop", bundle: AppLanguage.currentBundle)
        case "weight": String(localized: "template.weight.title", defaultValue: "Lose 5 kg", bundle: AppLanguage.currentBundle)
        case "savings": String(localized: "template.savings.title", defaultValue: "Save 10,000", bundle: AppLanguage.currentBundle)
        case "noSpend": String(localized: "template.noSpend.title", defaultValue: "30 days without spending", bundle: AppLanguage.currentBundle)
        default: ""
        }
    }

    /// The card subtitle — the goal's finish line ("100 km", "12 books", "−5 kg"), which reads
    /// more usefully on a template card than the recurrence does.
    var targetSummary: String {
        let value = isLowerBetter ? startValue : targetValue
        let formatted = value.formatted(.number.precision(.fractionLength(0...1)))
        let withUnit = GoalUnit.valueWithUnit(value, formattedValue: formatted, unitKey: unit.rawValue, customUnitText: nil)
        return isLowerBetter ? "−\(withUnit)" : withUnit
    }
}
