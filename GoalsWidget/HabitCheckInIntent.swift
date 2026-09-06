//
//  HabitCheckInIntent.swift
//  GoalsWidget
//

import AppIntents
import SwiftData
import WidgetKit
import os

private let log = Logger(subsystem: "com.hrobek.goals.GoalsWidget", category: "HabitCheckIn")

/// The habit widget's one-tap button. Runs inside the widget process, logs today's tick through
/// the same code path the app uses, then asks WidgetKit to redraw.
struct HabitCheckInIntent: AppIntent {
    static var title: LocalizedStringResource { "Check off habit" }
    static var description: IntentDescription { "Marks the habit done for today, or adds one tick." }

    @Parameter(title: "Habit")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else {
            log.error("bad habitID \(habitID, privacy: .public)")
            return .result()
        }

        let context = ModelContext(SharedStore.container)
        // Filter in Swift rather than in a #Predicate — SwiftData has miscompiled equality
        // predicates in this project before, and a check-in that silently no-ops is exactly the
        // symptom that would hide it.
        let all = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        guard let habit = all.first(where: { $0.id == id }) else {
            log.error("habit \(id, privacy: .public) not found among \(all.count) habits")
            return .result()
        }

        if habit.isCheckbox {
            HabitLogger.toggleToday(habit, in: context)
        } else {
            HabitLogger.addQuick(habit, in: context)
        }

        do {
            try context.save()
            log.notice("saved check-in for \(habit.title, privacy: .public)")
        } catch {
            log.error("save failed: \(error, privacy: .public)")
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "GoalsHabitsWidget")
        return .result()
    }
}
