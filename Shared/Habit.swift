//
//  Habit.swift
//  Goals
//

import Foundation
import SwiftData

/// A recurring thing you do rather than a target you reach — the daily side of the app. Shares
/// the recurrence + streak machinery with `Goal` through `Scheduled`, but keeps its own model.
///
/// Two shapes, decided by `unitKey`:
/// - **checkbox** (`.times`): one tap marks the day done.
/// - **value** (any other unit): a daily target amount (4000 ml, 10 pages) reached with quick-add
///   steps, exactly like a value `Goal`.
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
    /// Legacy integer target — kept so an older row still opens. New code reads `targetAmount`.
    var dailyTarget: Int = 1
    /// The unit the habit is measured in — pages, ml, minutes… Mirrors `Goal`; `.times` means a
    /// plain checkbox with no quantity.
    var unitKey: String = GoalUnit.times.rawValue
    var customUnitText: String?

    var recurrenceType: RecurrenceType = RecurrenceType.daily
    var recurrenceWeekdays: [Int] = []
    var recurrenceDaysOfMonth: [Int] = []
    var recurrenceCount: Int = 3

    // Stored as optionals and read through the accessors below, the same pattern `Goal` uses for
    // properties added after the first rows were written — a nil from an older row must not crash
    // a non-optional cast, and it keeps the schema change a lightweight migration.
    private var storedIsArchived: Bool?
    private var storedIsReminderOn: Bool?
    private var reminderFrequencyRawValue: String?
    private var storedReminderTimes: [Int]?
    private var storedReminderWeekdays: [Int]?
    private var storedTargetAmount: Double?
    private var storedWidgetQuickAmount: Double?

    @Relationship(deleteRule: .cascade, inverse: \HabitEntry.habit)
    var entries: [HabitEntry] = []

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        title: String,
        emoji: String? = nil,
        colorHex: String = ColorPalette.defaultHex,
        sortIndex: Int = 0,
        targetAmount: Double = 1,
        widgetQuickAmount: Double? = nil,
        unitKey: String = GoalUnit.times.rawValue,
        customUnitText: String? = nil,
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
        self.storedTargetAmount = max(1, targetAmount)
        self.dailyTarget = Int(max(1, targetAmount).rounded())
        self.storedWidgetQuickAmount = widgetQuickAmount
        self.unitKey = unitKey
        self.customUnitText = customUnitText
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

    /// How much counts as a full day. 1 for a checkbox habit; a real quantity for a value habit.
    var targetAmount: Double {
        get { max(1, storedTargetAmount ?? Double(dailyTarget)) }
        set {
            let clamped = max(1, newValue)
            storedTargetAmount = clamped
            dailyTarget = Int(clamped.rounded())
        }
    }

    /// What one quick-add step (and one widget tap) adds, for a value habit. Falls back to the
    /// unit's own smallest step, same as `Goal.widgetQuickAmount`.
    var widgetQuickAmount: Double {
        get { storedWidgetQuickAmount ?? GoalUnit(rawValue: unitKey)?.quickAddSteps.first ?? 1 }
        set { storedWidgetQuickAmount = newValue }
    }

    // MARK: - Derived

    var status: GoalStatus {
        isArchived ? .archived : .active
    }

    /// Whether this habit is measured in a real unit (pages, ml…) rather than a bare "times".
    var hasUnit: Bool {
        GoalUnit(rawValue: unitKey) != .times || (customUnitText?.isEmpty == false)
    }

    /// A one-tap habit: no unit and a target of one. "Times" with a target above one is a small
    /// counter instead ("stretch 3× a day"); a real unit is a value tracker.
    var isCheckbox: Bool { !hasUnit && targetAmount <= 1 }

    /// How much marks the day done. Rounded to a whole number for a "times" habit.
    var effectiveTarget: Double {
        hasUnit ? targetAmount : max(1, targetAmount.rounded())
    }

    func isScheduledToday(calendar: Calendar = .current, date: Date = .now) -> Bool {
        Recurrence.isDayScheduled(date, for: self, calendar: calendar)
    }

    /// Today's entry, if there is one.
    func entry(on date: Date, calendar: Calendar = .current) -> HabitEntry? {
        entries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The value logged for `date` (0 if nothing).
    func amount(on date: Date, calendar: Calendar = .current) -> Double {
        entry(on: date, calendar: calendar)?.amount ?? 0
    }

    /// 0…1 fraction of the day's target reached.
    func progressFraction(on date: Date = .now, calendar: Calendar = .current) -> Double {
        min(max(amount(on: date, calendar: calendar) / effectiveTarget, 0), 1)
    }

    /// Whether `date` has reached the target.
    func isDone(on date: Date, calendar: Calendar = .current) -> Bool {
        amount(on: date, calendar: calendar) >= effectiveTarget
    }

    var currentStreak: Int {
        StreakCalculator.currentStreak(for: self)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The target written out — "4,000 ml", "10 pages", or just "5" for a plain times counter.
    var targetText: String {
        guard hasUnit else { return format(effectiveTarget) }
        return GoalUnit.valueWithUnit(targetAmount, formattedValue: format(targetAmount), unitKey: unitKey, customUnitText: customUnitText)
    }

    /// "3,000/4,000 ml" for a value habit, "3/5" for a times counter; "" for a plain checkbox.
    func progressText(on date: Date = .now, calendar: Calendar = .current) -> String {
        guard !isCheckbox else { return "" }
        return "\(format(amount(on: date, calendar: calendar)))/\(targetText)"
    }

    /// A quick-add amount rendered with its unit — "250 ml", or just "1" for a times habit.
    func quickAddLabel(_ value: Double) -> String {
        guard hasUnit else { return format(value) }
        return GoalUnit.valueWithUnit(value, formattedValue: format(value), unitKey: unitKey, customUnitText: customUnitText)
    }
}

extension Habit: Scheduled {
    /// A habit counts a day as done once that day's logged amount reaches the target.
    var scheduleDates: [Date] {
        let target = effectiveTarget
        return entries.filter { $0.amount >= target }.map(\.date)
    }
}
