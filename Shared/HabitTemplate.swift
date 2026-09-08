//
//  HabitTemplate.swift
//  Goals
//

import Foundation

/// A ready-made starting point for a habit, offered on first run and from the Habits tab's add
/// flow. Picking one opens the normal Add Habit sheet with these values filled in - nothing is
/// created until the user hits Save. The `HabitTemplate` counterpart of `GoalTemplate`.
struct HabitTemplate: Identifiable, Hashable {
    /// Stable id: analytics tag and the localization-key suffix (`habitTemplate.<id>.title`).
    let id: String
    let emoji: String
    /// `.times` for a plain checkbox habit; a real unit for a value habit.
    let unit: GoalUnit
    /// Full-day target - 1 for a checkbox, a real quantity for a value habit.
    let targetAmount: Double
    /// A habit framed as something to quit ("no sugar", "quit smoking").
    let isAvoid: Bool
    let recurrenceType: RecurrenceType
    /// Only meaningful for the quota recurrence types.
    let recurrenceCount: Int

    static let all: [HabitTemplate] = [
        HabitTemplate(id: "water", emoji: "💧", unit: .milliliters, targetAmount: 2000,
                      isAvoid: false, recurrenceType: .daily, recurrenceCount: 3),
        HabitTemplate(id: "meditate", emoji: "🧘", unit: .times, targetAmount: 1,
                      isAvoid: false, recurrenceType: .daily, recurrenceCount: 3),
        HabitTemplate(id: "read", emoji: "📖", unit: .pages, targetAmount: 20,
                      isAvoid: false, recurrenceType: .daily, recurrenceCount: 3),
        HabitTemplate(id: "gym", emoji: "🏋️", unit: .times, targetAmount: 1,
                      isAvoid: false, recurrenceType: .timesPerWeek, recurrenceCount: 3),
        HabitTemplate(id: "noPhoneBed", emoji: "📵", unit: .times, targetAmount: 1,
                      isAvoid: true, recurrenceType: .daily, recurrenceCount: 3),
        HabitTemplate(id: "noSugar", emoji: "🍬", unit: .times, targetAmount: 1,
                      isAvoid: true, recurrenceType: .daily, recurrenceCount: 3),
        HabitTemplate(id: "quitSmoking", emoji: "🚭", unit: .times, targetAmount: 1,
                      isAvoid: true, recurrenceType: .daily, recurrenceCount: 3),
    ]

    var hasUnit: Bool { unit != .times }

    /// The seeded habit title, in the app's current language.
    var localizedTitle: String {
        switch id {
        case "water": String(localized: "habitTemplate.water.title", defaultValue: "Drink 2 L of water", bundle: AppLanguage.currentBundle)
        case "meditate": String(localized: "habitTemplate.meditate.title", defaultValue: "Meditate", bundle: AppLanguage.currentBundle)
        case "read": String(localized: "habitTemplate.read.title", defaultValue: "Read 20 pages a day", bundle: AppLanguage.currentBundle)
        case "gym": String(localized: "habitTemplate.gym.title", defaultValue: "Work out 3× a week", bundle: AppLanguage.currentBundle)
        case "noPhoneBed": String(localized: "habitTemplate.noPhoneBed.title", defaultValue: "No phone in bed", bundle: AppLanguage.currentBundle)
        case "noSugar": String(localized: "habitTemplate.noSugar.title", defaultValue: "No sugar", bundle: AppLanguage.currentBundle)
        case "quitSmoking": String(localized: "habitTemplate.quitSmoking.title", defaultValue: "Quit smoking", bundle: AppLanguage.currentBundle)
        default: ""
        }
    }

    /// The card subtitle: for a "quit" habit the frame ("Break a habit"), for a value habit the
    /// daily target ("2 L", "20 pages"), otherwise the schedule.
    var summary: String {
        if isAvoid {
            return String(localized: "habit.polarity.quit", bundle: AppLanguage.currentBundle)
        }
        if hasUnit {
            let formatted = targetAmount.formatted(.number.precision(.fractionLength(0...1)))
            return GoalUnit.valueWithUnit(targetAmount, formattedValue: formatted, unitKey: unit.rawValue, customUnitText: nil)
        }
        switch recurrenceType {
        case .timesPerWeek:
            return String(localized: "recurrence.summary.timesPerWeek \(recurrenceCount)", bundle: AppLanguage.currentBundle)
        case .timesPerMonth:
            return String(localized: "recurrence.summary.timesPerMonth \(recurrenceCount)", bundle: AppLanguage.currentBundle)
        default:
            return RecurrenceType.daily.localizedName
        }
    }

    /// The quick-add step to seed for a value habit.
    var quickAddAmount: Double { unit.quickAddSteps.first ?? 1 }
}
