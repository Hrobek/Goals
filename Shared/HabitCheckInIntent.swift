//
//  HabitCheckInIntent.swift
//  Goals
//
//  Shared by the app and the widget extension: an interactive widget button only dispatches to
//  a `perform()` that actually runs when the App Intent is in code both targets compile.
//

import AppIntents
import SwiftData
import WidgetKit
import os

private let log = Logger(subsystem: "com.hrobek.goals", category: "HabitCheckIn")

/// The habit widget's one-tap button. Runs in the widget-extension process, logs today's tick
/// through the same code path the app uses, then asks WidgetKit to redraw.
struct HabitCheckInIntent: AppIntent {
    static var title: LocalizedStringResource { "Check off habit" }
    static var description: IntentDescription { "Marks the habit done for today, or adds one tick." }

    // A non-optional @Parameter needs an explicit `default:` — without one it isn't reliably
    // archived into a widget `Button(intent:)`, and the tap never reaches `perform()`.
    @Parameter(title: "Habit", default: "")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }

        let context = ModelContext(SharedStore.container)

        // Filter in Swift rather than in a #Predicate — SwiftData has miscompiled equality
        // predicates in this project before, and a check-in that silently no-ops is exactly the
        // symptom that would hide it.
        let all = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        guard let habit = all.first(where: { $0.id == id }) else {
            log.error("habit \(id, privacy: .public) not found among \(all.count) habits")
            return .result()
        }

        switch habit.widgetAction {
        case .complete:
            HabitLogger.completeOccurrence(habit, in: context)
        case .checkOff:
            if habit.isCheckbox {
                HabitLogger.toggleToday(habit, in: context)
            } else if habit.hasUnit {
                HabitLogger.addQuick(habit, in: context)
            } else {
                // A "times" counter or a quota schedule: one tap is one more tick.
                HabitLogger.cycle(habit, in: context)
            }
        }

        do {
            try context.save()
        } catch {
            log.error("save failed: \(error, privacy: .public)")
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "GoalsHabitsWidget")
        return .result()
    }
}
