//
//  LogIntents.swift
//  Goals
//
//  "Log a habit" / "Log a goal" for Siri and Shortcuts. Each one lets the user pick what the run
//  does: finish the habit or goal outright, or add a specific amount to it.
//

import AppIntents
import SwiftData

/// What a log shortcut does to its habit or goal.
enum ShortcutLogMode: String, AppEnum {
    /// Finish it outright - today's target for a habit, the whole goal for a goal.
    case complete
    /// Add a chosen amount to it.
    case add

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Action" }

    static var caseDisplayRepresentations: [ShortcutLogMode: DisplayRepresentation] {
        [
            .complete: DisplayRepresentation(title: "Complete", image: .init(systemName: "checkmark.circle")),
            .add: DisplayRepresentation(title: "Add", image: .init(systemName: "plus.circle"))
        ]
    }
}

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case habitNotFound
    case goalNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .habitNotFound: "That habit no longer exists."
        case .goalNotFound: "That goal no longer exists."
        }
    }
}

// MARK: - Habit

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource { "Log habit" }
    static var description: IntentDescription {
        IntentDescription("Completes a habit for today, or adds an amount to it.", categoryName: "Habits")
    }

    @Parameter(title: "Habit")
    var habit: HabitEntity

    @Parameter(title: "Action", default: .complete)
    var mode: ShortcutLogMode

    @Parameter(title: "Amount")
    var amount: Double?

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, .add) {
            Summary("\(\.$mode) \(\.$amount) to \(\.$habit)")
        } otherwise: {
            Summary("\(\.$mode) \(\.$habit)")
        }
    }

    init() {}

    init(habit: HabitEntity, mode: ShortcutLogMode = .complete) {
        self.habit = habit
        self.mode = mode
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let habit = ShortcutData.habit(id: self.habit.id) else { throw ShortcutError.habitNotFound }
        let name = habit.title

        // Same rules as the widget: a slip on an avoid habit has to be logged deliberately in the
        // app, and a habit Health fills in can't be changed by hand anywhere.
        guard !habit.isAvoid else {
            return .result(dialog: "\(name) is a habit you avoid. Log a slip in the app.")
        }
        guard habit.healthKitDirection != .read else {
            return .result(dialog: "\(name) is filled in from Apple Health.")
        }

        switch mode {
        case .complete:
            // `completeOccurrence` toggles - on an already-done habit it would clear today. A
            // shortcut that says "complete" must never undo, so stop here instead.
            guard !habit.isDone(on: .now) else {
                return .result(dialog: "\(name) is already done.")
            }
            HabitLogger.completeOccurrence(habit, in: ShortcutData.context)
        case .add:
            guard let amount else {
                throw $amount.needsValueError("How much do you want to add?")
            }
            guard amount != 0 else { return .result(dialog: Self.status(of: habit)) }
            // `adjust` covers every shape: it caps a day-based habit at its target (so a checkbox
            // habit just gets ticked), lets a quota tally grow, and backs a negative amount out.
            HabitLogger.adjust(habit, by: amount, in: ShortcutData.context)
        }

        ShortcutData.save()
        return .result(dialog: Self.status(of: habit))
    }

    private static func status(of habit: Habit) -> IntentDialog {
        let name = habit.title
        if habit.isDone(on: .now) {
            return "\(name) is done."
        }
        let progress = habit.progressText()
        guard !progress.isEmpty else { return "\(name) isn't done yet." }
        return "\(name): \(progress)"
    }
}

// MARK: - Goal

struct LogGoalIntent: AppIntent {
    static var title: LocalizedStringResource { "Log goal progress" }
    static var description: IntentDescription {
        IntentDescription(
            "Completes a goal, or adds an amount to it. On a goal with subtasks, the amount is how many of the next subtasks to tick off.",
            categoryName: "Goals"
        )
    }

    @Parameter(title: "Goal")
    var goal: GoalEntity

    // Adding is the everyday case for a goal; finishing one outright is the rarer, bigger step.
    @Parameter(title: "Action", default: .add)
    var mode: ShortcutLogMode

    @Parameter(title: "Amount")
    var amount: Double?

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, .add) {
            Summary("\(\.$mode) \(\.$amount) to \(\.$goal)")
        } otherwise: {
            Summary("\(\.$mode) \(\.$goal)")
        }
    }

    init() {}

    init(goal: GoalEntity, mode: ShortcutLogMode = .add) {
        self.goal = goal
        self.mode = mode
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let goal = ShortcutData.goal(id: self.goal.id) else { throw ShortcutError.goalNotFound }
        let name = goal.title
        let context = ShortcutData.context

        guard goal.healthKitDirection != .read else {
            return .result(dialog: "\(name) is filled in from Apple Health.")
        }
        guard !goal.isCompleted else {
            return .result(dialog: "\(name) is already complete.")
        }

        switch mode {
        case .complete:
            switch goal.trackingMode {
            case .value:
                // Landing exactly on the target logs the day and marks the goal complete.
                ProgressLogger.record(value: goal.targetValue, for: goal, in: context)
            case .milestones:
                let open = goal.sortedMilestones.filter { !$0.isCompleted }
                if open.isEmpty {
                    goal.isCompleted = true
                } else {
                    // The last tick completes the goal on its own.
                    for milestone in open {
                        ProgressLogger.toggleMilestone(milestone, on: goal, in: context)
                    }
                }
            }
        case .add:
            guard let amount else {
                throw $amount.needsValueError("How much do you want to add?")
            }
            switch goal.trackingMode {
            case .value:
                guard amount != 0 else { return .result(dialog: Self.status(of: goal)) }
                // "Add" always means progress: on a lower-is-better goal (weight, debt) that's
                // a step down.
                let delta = goal.isLowerBetter ? -amount : amount
                ProgressLogger.record(value: max(goal.currentValue + delta, 0), for: goal, in: context)
            case .milestones:
                let count = Int(amount.rounded())
                guard count > 0 else { return .result(dialog: Self.status(of: goal)) }
                let next = goal.sortedMilestones.filter { !$0.isCompleted }.prefix(count)
                for milestone in next {
                    ProgressLogger.toggleMilestone(milestone, on: goal, in: context)
                }
            }
        }

        ShortcutData.save()
        return .result(dialog: Self.status(of: goal))
    }

    private static func status(of goal: Goal) -> IntentDialog {
        let name = goal.title
        if goal.isCompleted {
            return "\(name) is complete!"
        }
        switch goal.trackingMode {
        case .value:
            let format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
            let target = goal.valueWithUnit(goal.targetValue, formattedValue: format(goal.targetValue))
            return "\(name): \(format(goal.currentValue)) of \(target)"
        case .milestones:
            return "\(name): \(goal.completedMilestoneCount) of \(goal.milestones.count) subtasks"
        }
    }
}
