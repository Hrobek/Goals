//
//  Recurrence.swift
//  Goals
//

import Foundation

enum RecurrenceType: String, Codable, CaseIterable, Identifiable {
    case daily, specificWeekdays, timesPerWeek, specificDaysOfMonth, timesPerMonth

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .daily: String(localized: "recurrence.type.daily", defaultValue: "Every day", bundle: AppLanguage.currentBundle)
        case .specificWeekdays: String(localized: "recurrence.type.specificWeekdays", defaultValue: "Specific days of the week", bundle: AppLanguage.currentBundle)
        case .timesPerWeek: String(localized: "recurrence.type.timesPerWeek", defaultValue: "Times per week", bundle: AppLanguage.currentBundle)
        case .specificDaysOfMonth: String(localized: "recurrence.type.specificDaysOfMonth", defaultValue: "Specific days of the month", bundle: AppLanguage.currentBundle)
        case .timesPerMonth: String(localized: "recurrence.type.timesPerMonth", defaultValue: "Times per month", bundle: AppLanguage.currentBundle)
        }
    }
}

enum Recurrence {
    /// Weekday abbreviation for Calendar's 1(Sunday)...7(Saturday) convention, localized through
    /// the String Catalog (not `Calendar.shortWeekdaySymbols`, so it respects the in-app language
    /// override rather than only the system locale).
    static func weekdayAbbreviation(_ weekday: Int) -> String {
        switch weekday {
        case 1: String(localized: "recurrence.weekday.sun", defaultValue: "Sun", bundle: AppLanguage.currentBundle)
        case 2: String(localized: "recurrence.weekday.mon", defaultValue: "Mon", bundle: AppLanguage.currentBundle)
        case 3: String(localized: "recurrence.weekday.tue", defaultValue: "Tue", bundle: AppLanguage.currentBundle)
        case 4: String(localized: "recurrence.weekday.wed", defaultValue: "Wed", bundle: AppLanguage.currentBundle)
        case 5: String(localized: "recurrence.weekday.thu", defaultValue: "Thu", bundle: AppLanguage.currentBundle)
        case 6: String(localized: "recurrence.weekday.fri", defaultValue: "Fri", bundle: AppLanguage.currentBundle)
        case 7: String(localized: "recurrence.weekday.sat", defaultValue: "Sat", bundle: AppLanguage.currentBundle)
        default: ""
        }
    }

    /// Human-readable schedule summary, e.g. "Every day", "Mon, Wed, Fri", "3×/week", "5, 20", "2×/month".
    static func localizedSummary(for schedule: some Scheduled) -> String {
        switch schedule.recurrenceType {
        case .daily:
            return RecurrenceType.daily.localizedName
        case .specificWeekdays:
            let names = schedule.recurrenceWeekdays.sorted().map(weekdayAbbreviation)
            return names.isEmpty
                ? String(localized: "recurrence.summary.noneSelected", defaultValue: "No days selected", bundle: AppLanguage.currentBundle)
                : names.joined(separator: ", ")
        case .timesPerWeek:
            return String(localized: "recurrence.summary.timesPerWeek \(schedule.recurrenceCount)", bundle: AppLanguage.currentBundle)
        case .specificDaysOfMonth:
            let days = schedule.recurrenceDaysOfMonth.sorted()
            return days.isEmpty
                ? String(localized: "recurrence.summary.noneSelected", defaultValue: "No days selected", bundle: AppLanguage.currentBundle)
                : days.map(String.init).joined(separator: ", ")
        case .timesPerMonth:
            return String(localized: "recurrence.summary.timesPerMonth \(schedule.recurrenceCount)", bundle: AppLanguage.currentBundle)
        }
    }

    /// Whether `date` is a scheduled day for day-based recurrence types (daily / specific weekdays / specific days of month).
    /// Not meaningful for the quota-based types (timesPerWeek / timesPerMonth) — those are evaluated per-period instead.
    static func isDayScheduled(_ date: Date, for schedule: some Scheduled, calendar: Calendar) -> Bool {
        // Before the start date the goal or habit didn't exist — nothing is due.
        if calendar.startOfDay(for: date) < calendar.startOfDay(for: schedule.startDate) {
            return false
        }
        switch schedule.recurrenceType {
        case .daily:
            return true
        case .specificWeekdays:
            return schedule.recurrenceWeekdays.contains(calendar.component(.weekday, from: date))
        case .specificDaysOfMonth:
            return schedule.recurrenceDaysOfMonth.contains(calendar.component(.day, from: date))
        case .timesPerWeek, .timesPerMonth:
            return true
        }
    }
}
