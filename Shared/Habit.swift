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
    /// Optional "keep this up until" date — a habit you mean to run for a season, not forever.
    var deadline: Date?
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
    private var widgetActionRawValue: String?
    /// A habit you're trying to *not* do. Nil (→ false) for every habit written before this shipped.
    private var storedIsAvoid: Bool?

    // Stored optional for CloudKit; read through the non-optional accessor below.
    @Relationship(deleteRule: .cascade, originalName: "entries", inverse: \HabitEntry.habit)
    private var storedEntries: [HabitEntry]?

    var entries: [HabitEntry] {
        get { storedEntries ?? [] }
        set { storedEntries = newValue }
    }

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        title: String,
        emoji: String? = nil,
        colorHex: String = ColorPalette.defaultHex,
        deadline: Date? = nil,
        sortIndex: Int = 0,
        targetAmount: Double = 1,
        widgetQuickAmount: Double? = nil,
        widgetAction: HabitWidgetAction = .checkOff,
        unitKey: String = GoalUnit.times.rawValue,
        customUnitText: String? = nil,
        recurrenceType: RecurrenceType = .daily,
        recurrenceWeekdays: [Int] = [],
        recurrenceDaysOfMonth: [Int] = [],
        recurrenceCount: Int = 3,
        isArchived: Bool = false,
        isAvoid: Bool = false,
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
        self.deadline = deadline
        self.sortIndex = sortIndex
        self.storedTargetAmount = max(1, targetAmount)
        self.dailyTarget = Int(max(1, targetAmount).rounded())
        self.storedWidgetQuickAmount = widgetQuickAmount
        self.widgetActionRawValue = widgetAction.rawValue
        self.unitKey = unitKey
        self.customUnitText = customUnitText
        self.recurrenceType = recurrenceType
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceDaysOfMonth = recurrenceDaysOfMonth
        self.recurrenceCount = recurrenceCount
        self.createdAt = createdAt
        self.storedIsArchived = isArchived
        self.storedIsAvoid = isAvoid
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

    /// A habit framed as something to quit: "no smoking", "no doomscrolling". A day is a success
    /// unless you log a slip on it, so a `HabitEntry` here means a slip, not a check-in. The
    /// streak counts consecutive clean scheduled days.
    var isAvoid: Bool {
        get { storedIsAvoid ?? false }
        set { storedIsAvoid = newValue }
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

    /// What a tap does — a normal check-off, or finishing the whole occurrence at once.
    var widgetAction: HabitWidgetAction {
        get { widgetActionRawValue.flatMap(HabitWidgetAction.init(rawValue:)) ?? .checkOff }
        set { widgetActionRawValue = newValue.rawValue }
    }

    // MARK: - Derived

    var status: GoalStatus {
        isArchived ? .archived : .active
    }

    /// Whether this habit is measured in a real unit (pages, ml…) rather than a bare "times".
    var hasUnit: Bool {
        GoalUnit(rawValue: unitKey) != .times || (customUnitText?.isEmpty == false)
    }

    /// On a "times per week / month" schedule the target isn't a daily amount — it's a running
    /// tally of check-ins across the period (5×/week met however you like, twice in one day counts
    /// twice).
    var isQuota: Bool {
        recurrenceType == .timesPerWeek || recurrenceType == .timesPerMonth
    }

    /// A one-tap habit: no unit and a target of one. "Times" with a target above one is a small
    /// counter instead ("stretch 3× a day"); a real unit is a value tracker; a quota schedule is a
    /// per-period counter.
    var isCheckbox: Bool { !hasUnit && targetAmount <= 1 && !isQuota }

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

    // MARK: Quota period

    /// The week or month that `date` falls in — the window a quota schedule is measured over.
    func quotaInterval(containing date: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let component: Calendar.Component = recurrenceType == .timesPerMonth ? .month : .weekOfYear
        return calendar.dateInterval(of: component, for: date)
    }

    /// How many check-ins are logged in the quota period `date` sits in (each day's entry can hold
    /// more than one). Only meaningful when `isQuota`.
    func periodCount(on date: Date = .now, calendar: Calendar = .current) -> Int {
        guard let interval = quotaInterval(containing: date, calendar: calendar) else { return 0 }
        return entries
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + max(0, Int($1.amount.rounded())) }
    }

    /// The quota itself — the "5" in "5× per week".
    var quotaTarget: Int { max(1, recurrenceCount) }

    /// 0…1 fraction of the target reached — the day's target normally, the period's quota for a
    /// quota schedule. Binary for an avoid habit: full unless the day carries a slip.
    func progressFraction(on date: Date = .now, calendar: Calendar = .current) -> Double {
        if isAvoid {
            return entry(on: date, calendar: calendar) == nil ? 1 : 0
        }
        if isQuota {
            return min(max(Double(periodCount(on: date, calendar: calendar)) / Double(quotaTarget), 0), 1)
        }
        return min(max(amount(on: date, calendar: calendar) / effectiveTarget, 0), 1)
    }

    /// Whether the day counts as a success: target met normally, the quota met for a quota
    /// schedule, or — for an avoid habit — no slip logged that day.
    func isDone(on date: Date, calendar: Calendar = .current) -> Bool {
        if isAvoid {
            return entry(on: date, calendar: calendar) == nil
        }
        if isQuota {
            return periodCount(on: date, calendar: calendar) >= quotaTarget
        }
        return amount(on: date, calendar: calendar) >= effectiveTarget
    }

    /// Avoid habit only: whether a slip is already on the books for today.
    func slipped(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        isAvoid && entry(on: date, calendar: calendar) != nil
    }

    /// The most recent slip, if any — for the "clean since …" line on an avoid habit's detail.
    var lastSlipDate: Date? {
        guard isAvoid else { return nil }
        return entries.map(\.date).max()
    }

    var currentStreak: Int {
        StreakCalculator.currentStreak(for: self)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Just the number, no unit — for the "+" quick-add chips, which read cleaner bare.
    func numberOnly(_ value: Double) -> String { format(value) }

    /// The target written out — "4,000 ml", "10 pages", or just "5" for a plain times counter.
    var targetText: String {
        guard hasUnit else { return format(effectiveTarget) }
        return GoalUnit.valueWithUnit(targetAmount, formattedValue: format(targetAmount), unitKey: unitKey, customUnitText: customUnitText)
    }

    /// "3,000/4,000 ml" for a value habit, "3/5" for a times counter, "2/5" for a weekly quota;
    /// "" for a plain checkbox.
    func progressText(on date: Date = .now, calendar: Calendar = .current) -> String {
        guard !isCheckbox, !isAvoid else { return "" }
        if isQuota {
            return "\(periodCount(on: date, calendar: calendar))/\(quotaTarget)"
        }
        return "\(format(amount(on: date, calendar: calendar)))/\(targetText)"
    }

    /// A quick-add amount rendered with its unit — "250 ml", or just "1" for a times habit.
    func quickAddLabel(_ value: Double) -> String {
        guard hasUnit else { return format(value) }
        return GoalUnit.valueWithUnit(value, formattedValue: format(value), unitKey: unitKey, customUnitText: customUnitText)
    }
}

extension Habit: Scheduled {
    /// The dates that feed the streak and the activity heatmap.
    ///
    /// - Avoid habit: every scheduled day from creation through today that carries no slip — the
    ///   "clean" days. Inverting it here means `StreakCalculator` and the heatmap need no special
    ///   case.
    /// - Day-based habit: one date per day whose logged amount reached the target.
    /// - Quota habit: each day's date repeated once per check-in, so a period's total (which is
    ///   what the quota is measured against) is just a count of these — and the heatmap, which
    ///   maps them to distinct days, still lights each day once.
    var scheduleDates: [Date] {
        if isAvoid {
            return cleanDayDates()
        }
        if isQuota {
            return entries.flatMap { entry in
                Array(repeating: entry.date, count: max(0, Int(entry.amount.rounded())))
            }
        }
        let target = effectiveTarget
        return entries.filter { $0.amount >= target }.map(\.date)
    }

    /// Avoid habit only: the scheduled days between creation and today with no slip on them.
    private func cleanDayDates(calendar: Calendar = .current, now: Date = .now) -> [Date] {
        let start = calendar.startOfDay(for: createdAt)
        let today = calendar.startOfDay(for: now)
        guard start <= today else { return [] }

        let slipDays = Set(entries.map { calendar.startOfDay(for: $0.date) })
        var result: [Date] = []
        var cursor = start
        var iterations = 0
        while cursor <= today, iterations < 4000 {
            iterations += 1
            if Recurrence.isDayScheduled(cursor, for: self, calendar: calendar), !slipDays.contains(cursor) {
                result.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
