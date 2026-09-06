//
//  HabitCheckInIntent.swift
//  GoalsWidget
//

import AppIntents
import SwiftData
import WidgetKit

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
        guard let id = UUID(uuidString: habitID) else { return .result() }

        let context = SharedStore.container.mainContext
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        if let habit = try? context.fetch(descriptor).first {
            HabitLogger.toggleToday(habit, in: context)
            try? context.save()
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
