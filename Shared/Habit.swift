//
//  Habit.swift
//  Goals
//

import Foundation
import SwiftData

/// A recurring thing you do rather than a target you reach — the daily side of the app. Shares
/// the recurrence + streak machinery with `Goal` through `Scheduled`, but keeps its own model:
/// no target value, no milestones, just "did it today" and how long the run is.
@Model
final class Habit {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var title: String = ""
    var emoji: String?
    var colorHex: String = ColorPalette.defaultHex
    var createdAt: Date = Date.now
    /// Manual order in the list, lowest first. New habits go to the end.
    var sortIndex: Int = 0
    /// How many ticks in a day count the day as done — 1 for a plain habit, more for "8 glasses".
    var dailyTarget: Int = 1

    var recurrenceType: RecurrenceType = RecurrenceType.daily
    var recurrenceWeekdays: [Int] = []
    var recurrenceDaysOfMonth: [Int] = []
    var recurrenceCount: Int = 3

    // Stored as optionals and read through the accessors below, the same pattern `Goal` uses for
    // properties added after the first rows were written — a nil from an older row must not crash
    // a non-optional cast. (Habit ships with these from the start, but the pattern keeps a later
    // CloudKit migration cheap and matches the rest of the schema.)
    private var storedIsArchived: Bool?
    private var storedIsReminderOn: Bool?
    private var reminderFrequencyRawValue: String?
    private var storedReminderTimes: [Int]?
    private var storedReminderWeekdays: [Int]?

    @Relationship(deleteRule: .cascade, inverse: \HabitEntry.habit)
    var entries: [HabitEntry] = []

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        title: String,
        emoji: String? = nil,
        colorHex: String = ColorPalette.defaultHex,
        sortIndex: Int = 0,
        dailyTarget: Int = 1,
        recurrenceType: RecurrenceType = .daily,
        recurrenceWeekdays: [Int] = [],
        recurrenceDaysOfMonth: [Int] = [],
        recurrenceCount: Int = 3,
        isArchived: Bool = false,
        isReminderOn: Bool = false,
        reminderFrequency: ReminderFrequency = .daily,
        reminderTimes: [Int] = [9 * 60],
        reminderWeekdays: [Int] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.emoji = emoji
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.dailyTarget = max(1, dailyTarget)
        self.recurrenceType = recurrenceType
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceDaysOfMonth = recurrenceDaysOfMonth
        self.recurrenceCount = recurrenceCount
        self.createdAt = createdAt
        self.storedIsArchived = isArchived
        self.storedIsReminderOn = isReminderOn
        self.reminderFrequencyRawValue = reminderFrequency.rawValue
        self.storedReminderTimes = reminderTimes
        self.storedReminderWeekdays = reminderWeekdays
    }

    // MARK: - Accessors

    var isArchived: Bool {
        get { storedIsArchived ?? false }
        set { storedIsArchived = newValue }
    }

    var isReminderOn: Bool {
        get { storedIsReminderOn ?? false }
        set { storedIsReminderOn = newValue }
    }

    var reminderFrequency: ReminderFrequency {
        get { reminderFrequencyRawValue.flatMap(ReminderFrequency.init(rawValue:)) ?? .daily }
        set { reminderFrequencyRawValue = newValue.rawValue }
    }

    /// Every time of day the reminder fires, as minutes since midnight, sorted and de-duplicated.
    /// Always has at least one entry (falls back to 9:00).
    var reminderTimes: [Int] {
        get {
            let stored = (storedReminderTimes ?? []).filter { (0..<24 * 60).contains($0) }
            return stored.isEmpty ? [9 * 60] : Array(Set(stored)).sorted()
        }
        set {
            let cleaned = Array(Set(newValue.filter { (0..<24 * 60).contains($0) })).sorted()
            storedReminderTimes = cleaned.isEmpty ? [9 * 60] : cleaned
        }
    }

    /// Calendar weekday numbers (1 = Sunday), used when the reminder frequency is weekly.
    var reminderWeekdays: [Int] {
        get { storedReminderWeekdays ?? [] }
        set { storedReminderWeekdays = newValue.sorted() }
    }

    // MARK: - Derived

    var status: GoalStatus {
        isArchived ? .archived : .active
    }

    func isScheduledToday(calendar: Calendar = .current, date: Date = .now) -> Bool {
        Recurrence.isDayScheduled(date, for: self, calendar: calendar)
    }

    /// Today's entry, if there is one.
    func entry(on date: Date, calendar: Calendar = .current) -> HabitEntry? {
        entries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// How many ticks are logged for `date` (0 if none).
    func count(on date: Date, calendar: Calendar = .current) -> Int {
        entry(on: date, calendar: calendar)?.count ?? 0
    }

    /// Whether `date`'s ticks have reached `dailyTarget`.
    func isDone(on date: Date, calendar: Calendar = .current) -> Bool {
        count(on: date, calendar: calendar) >= dailyTarget
    }

    var currentStreak: Int {
        StreakCalculator.currentStreak(for: self)
    }
}

extension Habit: Scheduled {
    /// A habit counts a day as done once its ticks for that day reach `dailyTarget`.
    var scheduleDates: [Date] {
        entries.filter { $0.count >= dailyTarget }.map(\.date)
    }
}
