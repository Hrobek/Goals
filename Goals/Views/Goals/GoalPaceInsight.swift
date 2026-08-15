//
//  GoalPaceInsight.swift
//  Goals
//

import Foundation

/// A plain-language read on pace: what daily rate would hit the deadline, or — without one —
/// what the pace so far projects to. Pro-only; the free tiers already show the raw numbers, this
/// is the "so what should I actually do" translation of them.
enum GoalPaceInsight {
    case requiredPace(perDay: Double, unit: String)
    case requiredPaceInverted(everyDays: Int, unit: String)
    case projectedFinish(perDay: Double, unit: String, date: Date)
    case overdue(remaining: Double, unit: String)

    static func compute(for goal: Goal, calendar: Calendar = .current, now: Date = .now) -> GoalPaceInsight? {
        guard !goal.isCompleted, !goal.isTargetReached else { return nil }

        let remaining: Double
        let unit: String
        switch goal.trackingMode {
        case .value:
            remaining = goal.isLowerBetter ? (goal.currentValue - goal.targetValue) : (goal.targetValue - goal.currentValue)
            unit = goal.unitDisplayText
        case .milestones:
            remaining = Double(goal.milestones.count - goal.completedMilestoneCount)
            unit = String(localized: "milestone.unit", defaultValue: "milestones", bundle: AppLanguage.currentBundle)
        }
        guard remaining > 0 else { return nil }

        if let deadline = goal.deadline {
            let today = calendar.startOfDay(for: now)
            let deadlineDay = calendar.startOfDay(for: deadline)
            let daysUntil = calendar.dateComponents([.day], from: today, to: deadlineDay).day ?? 0

            if daysUntil < 0 {
                return .overdue(remaining: remaining, unit: unit)
            }
            // Clamped to 1: a deadline of "today" still gets a same-day pace instead of dividing by zero.
            let daysLeft = max(daysUntil, 1)
            let perDay = remaining / Double(daysLeft)
            if perDay >= 1 {
                return .requiredPace(perDay: perDay, unit: unit)
            } else {
                let everyDays = max(Int((1 / perDay).rounded()), 1)
                return .requiredPaceInverted(everyDays: everyDays, unit: unit)
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
        return .projectedFinish(perDay: perDay, unit: unit, date: projectedDate)
    }

    /// Rendered in the app's current language — built here rather than as a `Text` interpolation
    /// because it's assembled from a `switch`, not a single call site.
    var message: String {
        switch self {
        case .requiredPace(let perDay, let unit):
            String(localized: "pace.requiredPace \(Self.formatted(perDay)) \(unit)", bundle: AppLanguage.currentBundle)
        case .requiredPaceInverted(let everyDays, let unit):
            String(localized: "pace.requiredPaceInverted \(unit) \(Self.daysPhrase(everyDays))", bundle: AppLanguage.currentBundle)
        case .projectedFinish(let perDay, let unit, let date):
            String(localized: "pace.projectedFinish \(Self.formatted(perDay)) \(unit) \(date.formatted(date: .abbreviated, time: .omitted))", bundle: AppLanguage.currentBundle)
        case .overdue(let remaining, let unit):
            String(localized: "pace.overdue \(Self.formatted(remaining)) \(unit)", bundle: AppLanguage.currentBundle)
        }
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "day(s)" is app vocabulary, not user text, so it gets a small hand-rolled plural instead of
    /// a String Catalog plural variant — simple enough for the app's two languages.
    private static func daysPhrase(_ n: Int) -> String {
        switch AppLanguage.current {
        case .cs:
            let word = switch n {
            case 1: "den"
            case 2...4: "dny"
            default: "dní"
            }
            return "\(n) \(word)"
        case .en:
            return n == 1 ? "1 day" : "\(n) days"
        }
    }
}
