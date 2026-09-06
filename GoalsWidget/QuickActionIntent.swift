//
//  QuickActionIntent.swift
//  GoalsWidget
//

import AppIntents
import SwiftData
import WidgetKit
import os

private let log = Logger(subsystem: "com.hrobek.goals.GoalsWidget", category: "QuickAction")

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
        WidgetDiagnostics.log("goal tap: enter id=\(goalID.prefix(8))")

        guard let id = UUID(uuidString: goalID) else {
            WidgetDiagnostics.log("goal tap: bad id \(goalID)")
            return .result()
        }

        let context = ModelContext(SharedStore.container)
        WidgetDiagnostics.log("goal tap: context ready")

        let all = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        guard let goal = all.first(where: { $0.id == id }) else {
            log.error("goal \(id, privacy: .public) not found among \(all.count)")
            WidgetDiagnostics.log("goal tap: not found (\(all.count) goals)")
            return .result()
        }

        ProgressLogger.performQuickAction(on: goal, in: context)
        do {
            try context.save()
            log.notice("saved quick action for \(goal.title, privacy: .public)")
            WidgetDiagnostics.log("goal tap: SAVED \(goal.title)")
        } catch {
            log.error("save failed: \(error, privacy: .public)")
            WidgetDiagnostics.log("goal tap: save FAILED \(error)")
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
