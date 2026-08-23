//
//  QuickActionIntent.swift
//  GoalsWidget
//

import AppIntents
import SwiftData
import WidgetKit

/// The widget's one-tap button. Runs inside the widget process, writes straight into the shared
/// store through the same code path the app uses, then asks WidgetKit to redraw.
struct QuickActionIntent: AppIntent {
    static var title: LocalizedStringResource { "Log progress" }
    static var description: IntentDescription { "Adds the goal's quick amount, or ticks off its next subtask." }

    @Parameter(title: "Goal")
    var goalID: String

    init() {}

    init(goalID: UUID) {
        self.goalID = goalID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: goalID) else { return .result() }

        let context = SharedStore.container.mainContext
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        if let goal = try? context.fetch(descriptor).first {
            ProgressLogger.performQuickAction(on: goal, in: context)
            try? context.save()
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
