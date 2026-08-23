//
//  GoalPaceInsight.swift
//  Goals
//

import Foundation

/// A plain-language read on pace: what daily rate would hit the deadline, or — without one —
/// what the pace so far projects to. Pro-only; the free tiers already show the raw numbers, this
/// is the "so what should I actually do" translation of them.
enum GoalPaceInsight {
    // Amounts arrive already written out ("4 km", "3 stránky") rather than as a number plus a unit
    // string: the noun has to agree with the number, which only works while the two are one phrase.
    case requiredPace(perDay: String)
    case requiredPaceInverted(everyDays: Int, unit: String)
    case projectedFinish(perDay: String, date: Date)
    case overdue(remaining: String)

    static func compute(for goal: Goal, calendar: Calendar = .current, now: Date = .now) -> GoalPaceInsight? {
        guard !goal.isCompleted, !goal.isTargetReached else { return nil }

        let remaining: Double
        // A function rather than a fixed string: each message below writes out a different number —
        // a daily rate, what's left — and the unit has to agree with that one.
        let amount: (Double) -> String
        /// The bare unit, for the one message that says "1× <unit>" and supplies its own number.
        let unitLabel: String
        switch goal.trackingMode {
        case .value:
            remaining = goal.isLowerBetter ? (goal.currentValue - goal.targetValue) : (goal.targetValue - goal.currentValue)
            amount = { goal.valueWithUnit($0, formattedValue: Self.formatted($0)) }
            unitLabel = goal.unitDisplayText
        case .milestones:
            remaining = Double(goal.milestones.count - goal.completedMilestoneCount)
            amount = { count in
                guard count == count.rounded() else {
                    return "\(Self.formatted(count)) " + String(localized: "milestone.unit", defaultValue: "subtasks", bundle: AppLanguage.currentBundle)
                }
                return String(localized: "milestone.unit.count \(Int(count))", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
            }
            unitLabel = String(localized: "milestone.unit", defaultValue: "subtasks", bundle: AppLanguage.currentBundle)
        }
        guard remaining > 0 else { return nil }

        if let deadline = goal.deadline {
            let today = calendar.startOfDay(for: now)
            let deadlineDay = calendar.startOfDay(for: deadline)
            let daysUntil = calendar.dateComponents([.day], from: today, to: deadlineDay).day ?? 0

            if daysUntil < 0 {
                return .overdue(remaining: amount(remaining))
            }
            // Clamped to 1: a deadline of "today" still gets a same-day pace instead of dividing by zero.
            let daysLeft = max(daysUntil, 1)
            let perDay = remaining / Double(daysLeft)
            if perDay >= 1 {
                return .requiredPace(perDay: amount(perDay))
            } else {
                let everyDays = max(Int((1 / perDay).rounded()), 1)
                return .requiredPaceInverted(everyDays: everyDays, unit: unitLabel)
            }
        }

        // No deadline to work backward from — project a finish date from the average pace since
        // the goal started instead.
        guard !goal.checkIns.isEmpty else { return nil }
        let daysSinceStart = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: goal.createdAt), to: calendar.startOfDay(for: now)
        ).day ?? 0
        guard daysSinceStart >= 1 else { return nil }

        let progressSoFar: Double
        switch goal.trackingMode {
        case .value:
            progressSoFar = goal.isLowerBetter ? (goal.startValue - goal.currentValue) : (goal.currentValue - goal.startValue)
        case .milestones:
            progressSoFar = Double(goal.completedMilestoneCount)
        }
        guard progressSoFar > 0 else { return nil }

        let perDay = progressSoFar / Double(daysSinceStart)
        let daysNeeded = (remaining / perDay).rounded(.up)
        guard let projectedDate = calendar.date(byAdding: .day, value: Int(daysNeeded), to: now) else { return nil }
        return .projectedFinish(perDay: amount(perDay), date: projectedDate)
    }

    /// Rendered in the app's current language — built here rather than as a `Text` interpolation
    /// because it's assembled from a `switch`, not a single call site.
    var message: String {
        switch self {
        case .requiredPace(let perDay):
            String(localized: "pace.requiredPace \(perDay)", bundle: AppLanguage.currentBundle)
        case .requiredPaceInverted(let everyDays, let unit):
            String(localized: "pace.requiredPaceInverted \(unit) \(Self.daysPhrase(everyDays))", bundle: AppLanguage.currentBundle)
        case .projectedFinish(let perDay, let date):
            String(localized: "pace.projectedFinish \(perDay) \(date.formatted(date: .abbreviated, time: .omitted))", bundle: AppLanguage.currentBundle)
        case .overdue(let remaining):
            String(localized: "pace.overdue \(remaining)", bundle: AppLanguage.currentBundle)
        }
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Plural forms come from the String Catalog rather than a hand-rolled switch: that was
    /// tolerable for two languages, but Czech alone needs three forms (1 den / 2–4 dny / 5+ dní)
    /// and every language added multiplies the cases.
    private static func daysPhrase(_ n: Int) -> String {
        String(localized: "pace.days \(n)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
    }
}
