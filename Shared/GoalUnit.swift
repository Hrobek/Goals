//
//  GoalUnit.swift
//  Goals
//

import Foundation

/// Groups the preset units in the picker (Weight, Currency, …).
enum GoalUnitCategory: String, CaseIterable, Identifiable {
    case general, distance, weight, volume, time, energy, currency

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .general: String(localized: "unit.category.general", defaultValue: "General", bundle: AppLanguage.currentBundle)
        case .distance: String(localized: "unit.category.distance", defaultValue: "Distance", bundle: AppLanguage.currentBundle)
        case .weight: String(localized: "unit.category.weight", defaultValue: "Weight", bundle: AppLanguage.currentBundle)
        case .volume: String(localized: "unit.category.volume", defaultValue: "Volume", bundle: AppLanguage.currentBundle)
        case .time: String(localized: "unit.category.time", defaultValue: "Time", bundle: AppLanguage.currentBundle)
        case .energy: String(localized: "unit.category.energy", defaultValue: "Energy", bundle: AppLanguage.currentBundle)
        case .currency: String(localized: "unit.category.currency", defaultValue: "Currency", bundle: AppLanguage.currentBundle)
        }
    }

    var units: [GoalUnit] {
        GoalUnit.allCases.filter { $0.category == self }
    }
}

enum GoalUnit: String, Codable, CaseIterable, Identifiable {
    case times, steps, reps, pages, books
    case km, meters, miles
    case kg, grams, pounds
    case liters, milliliters, glasses
    case minutes, hours, days
    case kcal
    case czk, eur, usd
    /// Marker for units the user defined themselves; the text lives in `Goal.customUnitText`.
    case custom

    var id: String { rawValue }

    /// `nil` for `.custom`, which is listed from the user's own units rather than a preset group.
    var category: GoalUnitCategory? {
        switch self {
        case .times, .steps, .reps, .pages, .books: .general
        case .km, .meters, .miles: .distance
        case .kg, .grams, .pounds: .weight
        case .liters, .milliliters, .glasses: .volume
        case .minutes, .hours, .days: .time
        case .kcal: .energy
        case .czk, .eur, .usd: .currency
        case .custom: nil
        }
    }

    var localizedName: String {
        switch self {
        case .times: String(localized: "unit.times", defaultValue: "times", bundle: AppLanguage.currentBundle)
        case .steps: String(localized: "unit.steps", defaultValue: "steps", bundle: AppLanguage.currentBundle)
        case .reps: String(localized: "unit.reps", defaultValue: "reps", bundle: AppLanguage.currentBundle)
        case .pages: String(localized: "unit.pages", defaultValue: "pages", bundle: AppLanguage.currentBundle)
        case .books: String(localized: "unit.books", defaultValue: "books", bundle: AppLanguage.currentBundle)
        case .km: String(localized: "unit.km", defaultValue: "km", bundle: AppLanguage.currentBundle)
        case .meters: String(localized: "unit.meters", defaultValue: "m", bundle: AppLanguage.currentBundle)
        case .miles: String(localized: "unit.miles", defaultValue: "miles", bundle: AppLanguage.currentBundle)
        case .kg: String(localized: "unit.kg", defaultValue: "kg", bundle: AppLanguage.currentBundle)
        case .grams: String(localized: "unit.grams", defaultValue: "g", bundle: AppLanguage.currentBundle)
        case .pounds: String(localized: "unit.pounds", defaultValue: "lb", bundle: AppLanguage.currentBundle)
        case .liters: String(localized: "unit.liters", defaultValue: "liters", bundle: AppLanguage.currentBundle)
        case .milliliters: String(localized: "unit.milliliters", defaultValue: "ml", bundle: AppLanguage.currentBundle)
        case .glasses: String(localized: "unit.glasses", defaultValue: "glasses", bundle: AppLanguage.currentBundle)
        case .minutes: String(localized: "unit.minutes", defaultValue: "minutes", bundle: AppLanguage.currentBundle)
        case .hours: String(localized: "unit.hours", defaultValue: "hours", bundle: AppLanguage.currentBundle)
        case .days: String(localized: "unit.days", defaultValue: "days", bundle: AppLanguage.currentBundle)
        case .kcal: String(localized: "unit.kcal", defaultValue: "kcal", bundle: AppLanguage.currentBundle)
        case .czk: String(localized: "unit.czk", defaultValue: "CZK", bundle: AppLanguage.currentBundle)
        case .eur: String(localized: "unit.eur", defaultValue: "EUR", bundle: AppLanguage.currentBundle)
        case .usd: String(localized: "unit.usd", defaultValue: "USD", bundle: AppLanguage.currentBundle)
        case .custom: String(localized: "unit.category.custom", defaultValue: "Custom", bundle: AppLanguage.currentBundle)
        }
    }

    /// Increments offered as one-tap buttons on the goal detail, sized to how the unit is normally
    /// logged — nobody counts steps one at a time.
    var quickAddSteps: [Double] {
        switch self {
        case .times, .reps, .books, .glasses, .days: [1, 2, 3, 5]
        case .pages: [5, 10, 25, 50]
        case .steps: [500, 1000, 2500, 5000]
        case .km, .miles, .pounds: [1, 2, 5, 10]
        case .meters: [100, 250, 500, 1000]
        case .kg: [0.5, 1, 2, 5]
        case .grams: [50, 100, 250, 500]
        case .liters: [0.25, 0.5, 1, 2]
        case .milliliters, .kcal: [100, 250, 500, 1000]
        case .minutes: [5, 10, 15, 30]
        case .hours: [0.5, 1, 2, 4]
        case .czk: [50, 100, 500, 1000]
        case .eur, .usd: [5, 10, 25, 50]
        case .custom: [1, 2, 5, 10]
        }
    }

    /// The count and the unit as one phrase — "1 den", "3 dny", "30 dní" — because the noun has to
    /// agree with the number, and a String Catalog can only decline it while the two are together.
    /// `nil` for units written as symbols (km, kg, kcal, currencies), which read the same at any
    /// count and are better off with the caller's own number formatting.
    func countPhrase(_ count: Int) -> String? {
        switch self {
        case .times: String(localized: "unit.times.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .steps: String(localized: "unit.steps.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .reps: String(localized: "unit.reps.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .pages: String(localized: "unit.pages.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .books: String(localized: "unit.books.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .miles: String(localized: "unit.miles.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .glasses: String(localized: "unit.glasses.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .minutes: String(localized: "unit.minutes.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .hours: String(localized: "unit.hours.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .days: String(localized: "unit.days.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .liters: String(localized: "unit.liters.count \(count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        case .km, .meters, .kg, .grams, .pounds, .milliliters, .kcal, .czk, .eur, .usd, .custom: nil
        }
    }

    /// Resolves the display unit text for a goal: the preset's localized name, or its custom text.
    static func displayText(unitKey: String, customUnitText: String?) -> String {
        guard let unit = GoalUnit(rawValue: unitKey), unit != .custom else {
            return customUnitText ?? ""
        }
        return unit.localizedName
    }

    /// A value with its unit — "100 dní", "2,5 km". Whole numbers go through the declined phrase;
    /// anything fractional keeps the caller's formatting (a plural rule is defined over integers,
    /// and rounding 2.5 to "2 stránky" would quietly lose half a page).
    static func valueWithUnit(_ value: Double, formattedValue: String, unitKey: String, customUnitText: String?) -> String {
        let standalone = "\(formattedValue) \(displayText(unitKey: unitKey, customUnitText: customUnitText))"
        guard value == value.rounded(), abs(value) < Double(Int.max),
              let unit = GoalUnit(rawValue: unitKey),
              let phrase = unit.countPhrase(Int(value)) else { return standalone }
        return phrase
    }
}

/// What the unit picker hands back — either a preset or one of the user's own units.
enum UnitSelection: Equatable {
    case preset(GoalUnit)
    case custom(String)

    init(unitKey: String, customUnitText: String?) {
        if let unit = GoalUnit(rawValue: unitKey), unit != .custom {
            self = .preset(unit)
        } else if let text = customUnitText, !text.isEmpty {
            self = .custom(text)
        } else {
            self = .preset(.times)
        }
    }

    var displayText: String {
        switch self {
        case .preset(let unit): unit.localizedName
        case .custom(let text): text
        }
    }

    var unitKey: String {
        switch self {
        case .preset(let unit): unit.rawValue
        case .custom: GoalUnit.custom.rawValue
        }
    }

    var customUnitText: String? {
        switch self {
        case .preset: nil
        case .custom(let text): text
        }
    }
}
