//
//  Goal.swift
//  Goals
//

import Foundation
import SwiftData

enum GoalPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low, medium, high

    var id: String { rawValue }

    private var sortOrder: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: GoalPriority, rhs: GoalPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var localizedName: String {
        switch self {
        case .low: String(localized: "priority.low", defaultValue: "Low", bundle: AppLanguage.currentBundle)
        case .medium: String(localized: "priority.medium", defaultValue: "Medium", bundle: AppLanguage.currentBundle)
        case .high: String(localized: "priority.high", defaultValue: "High", bundle: AppLanguage.currentBundle)
        }
    }
}

/// Which shelf a goal sits on in the overview. Archiving is the way to retire a goal without
/// losing it — deleting stays available but throws the history away.
enum GoalStatus: String, CaseIterable, Identifiable {
    case active, completed, archived

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .active: String(localized: "goals.filter.active", defaultValue: "Active", bundle: AppLanguage.currentBundle)
        case .completed: String(localized: "goals.filter.completed", defaultValue: "Completed", bundle: AppLanguage.currentBundle)
        case .archived: String(localized: "goals.filter.archived", defaultValue: "Archived", bundle: AppLanguage.currentBundle)
        }
    }
}

/// How a goal measures progress: by counting a value in some unit, or by ticking off milestones.
enum GoalTrackingMode: String, Codable, CaseIterable, Identifiable {
    case value, milestones

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .value: String(localized: "tracking.value", defaultValue: "Units", bundle: AppLanguage.currentBundle)
        case .milestones: String(localized: "tracking.milestones", defaultValue: "Subtasks", bundle: AppLanguage.currentBundle)
        }
    }
}

@Model
final class Goal {
    /// Reserved for rows written before per-user data isolation existed; a one-time migration
    /// claims every row still carrying this value for whichever account signs in first.
    static let unownedId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var title: String = ""
    var deadline: Date?
    var priority: GoalPriority = GoalPriority.medium
    var isCompleted: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify)
    var category: Category?

    var targetValue: Double = 1
    var currentValue: Double = 0
    var unitKey: String = GoalUnit.times.rawValue
    var customUnitText: String?

    // Properties added after the first goals were saved. They are stored as optionals and read
    // through the accessors below: a row written before the property existed comes back as nil,
    // and SwiftData would otherwise crash trying to cast that nil into a non-optional value.
    private var trackingModeRawValue: String?
    private var storedStartValue: Double?
    private var storedIsLowerBetter: Bool?
    private var storedIsArchived: Bool?
    private var storedIsReminderOn: Bool?
    private var reminderFrequencyRawValue: String?
    private var storedReminderHour: Int?
    private var storedReminderMinute: Int?
    private var storedReminderWeekdays: [Int]?
    private var widgetActionRawValue: String?
    private var storedWidgetQuickAmount: Double?

    var trackingMode: GoalTrackingMode {
        get { trackingModeRawValue.flatMap(GoalTrackingMode.init(rawValue:)) ?? .value }
        set { trackingModeRawValue = newValue.rawValue }
    }

    var startValue: Double {
        get { storedStartValue ?? 0 }
        set { storedStartValue = newValue }
    }

    /// Set for goals where progress means going down (losing weight, cutting spending).
    var isLowerBetter: Bool {
        get { storedIsLowerBetter ?? false }
        set { storedIsLowerBetter = newValue }
    }

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

    var reminderHour: Int {
        get { storedReminderHour ?? 9 }
        set { storedReminderHour = newValue }
    }

    var reminderMinute: Int {
        get { storedReminderMinute ?? 0 }
        set { storedReminderMinute = newValue }
    }

    /// Calendar weekday numbers (1 = Sunday), used when the frequency is weekly.
    var reminderWeekdays: [Int] {
        get { storedReminderWeekdays ?? [] }
        set { storedReminderWeekdays = newValue.sorted() }
    }

    var widgetAction: WidgetAction {
        get { widgetActionRawValue.flatMap(WidgetAction.init(rawValue:)) ?? .quickAction }
        set { widgetActionRawValue = newValue.rawValue }
    }

    /// Magnitude the widget's quick action adds; the direction comes from `isLowerBetter`.
    /// Falls back to the unit's smallest one-tap step.
    var widgetQuickAmount: Double {
        get { storedWidgetQuickAmount ?? GoalUnit(rawValue: unitKey)?.quickAddSteps.first ?? 1 }
        set { storedWidgetQuickAmount = newValue }
    }

    var nextMilestone: Milestone? {
        sortedMilestones.first { !$0.isCompleted }
    }

    var colorHex: String = ColorPalette.defaultHex
    var emoji: String?

    var recurrenceType: RecurrenceType = RecurrenceType.daily
    var recurrenceWeekdays: [Int] = []
    var recurrenceDaysOfMonth: [Int] = []
    var recurrenceCount: Int = 3

    @Relationship(deleteRule: .cascade, inverse: \Milestone.goal)
    var milestones: [Milestone] = []

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.goal)
    var checkIns: [CheckIn] = []

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        title: String,
        category: Category? = nil,
        deadline: Date? = nil,
        priority: GoalPriority = .medium,
        trackingMode: GoalTrackingMode = .value,
        startValue: Double = 0,
        targetValue: Double = 1,
        currentValue: Double = 0,
        isLowerBetter: Bool = false,
        unitKey: String = GoalUnit.times.rawValue,
        customUnitText: String? = nil,
        colorHex: String = ColorPalette.defaultHex,
        emoji: String? = nil,
        recurrenceType: RecurrenceType = .daily,
        recurrenceWeekdays: [Int] = [],
        recurrenceDaysOfMonth: [Int] = [],
        recurrenceCount: Int = 3,
        isCompleted: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.category = category
        self.deadline = deadline
        self.priority = priority
        self.trackingModeRawValue = trackingMode.rawValue
        self.storedStartValue = startValue
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.storedIsLowerBetter = isLowerBetter
        self.unitKey = unitKey
        self.customUnitText = customUnitText
        self.colorHex = colorHex
        self.emoji = emoji
        self.recurrenceType = recurrenceType
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceDaysOfMonth = recurrenceDaysOfMonth
        self.recurrenceCount = recurrenceCount
        self.isCompleted = isCompleted
        self.storedIsArchived = isArchived
        self.createdAt = createdAt
    }

    var status: GoalStatus {
        if isArchived { .archived }
        else if isCompleted { .completed }
        else { .active }
    }

    /// Whether the goal wants attention today, per its schedule. Quota schedules ("3× a week")
    /// don't name days, so they count as scheduled every day.
    func isScheduledToday(calendar: Calendar = .current, date: Date = .now) -> Bool {
        Recurrence.isDayScheduled(date, for: self, calendar: calendar)
    }

    func hasCheckIn(on date: Date, calendar: Calendar = .current) -> Bool {
        checkIns.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// 0...1 fraction, from ticked-off milestones or the distance travelled between the starting
    /// value and the target — which works in either direction.
    var progressFraction: Double {
        switch trackingMode {
        case .value:
            let span = isLowerBetter ? startValue - targetValue : targetValue - startValue
            guard span > 0 else { return isTargetReached ? 1 : 0 }
            let travelled = isLowerBetter ? startValue - currentValue : currentValue - startValue
            return min(max(travelled / span, 0), 1)
        case .milestones:
            guard !milestones.isEmpty else { return 0 }
            return Double(completedMilestoneCount) / Double(milestones.count)
        }
    }

    var isTargetReached: Bool {
        switch trackingMode {
        case .value:
            isLowerBetter ? currentValue <= targetValue : currentValue >= targetValue
        case .milestones:
            !milestones.isEmpty && completedMilestoneCount == milestones.count
        }
    }

    var completedMilestoneCount: Int {
        milestones.filter(\.isCompleted).count
    }

    var sortedMilestones: [Milestone] {
        milestones.sorted { $0.order < $1.order }
    }

    var unitDisplayText: String {
        GoalUnit.displayText(unitKey: unitKey, customUnitText: customUnitText)
    }

    /// A value written out with this goal's unit — "100 dní", "2,5 km" — with the noun agreeing
    /// with the number. `formattedValue` is the caller's own rendering of the same value, used for
    /// fractions, which have no plural form to pick.
    func valueWithUnit(_ value: Double, formattedValue: String) -> String {
        GoalUnit.valueWithUnit(value, formattedValue: formattedValue, unitKey: unitKey, customUnitText: customUnitText)
    }
}
