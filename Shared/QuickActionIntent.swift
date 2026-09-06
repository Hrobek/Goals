//
//  QuickActionIntent.swift
//  Goals
//
//  Shared by the app and the widget extension: an interactive widget button only dispatches to
//  a `perform()` that actually runs when the App Intent is in code both targets compile.
//

import AppIntents
import SwiftData
import WidgetKit
import os

private let log = Logger(subsystem: "com.hrobek.goals", category: "QuickAction")

/// The Goals widget's one-tap button. Runs in the widget-extension process, writes straight into
/// the shared store through the same code path the app uses, then asks WidgetKit to redraw.
struct QuickActionIntent: AppIntent {
    static var title: LocalizedStringResource { "Log progress" }
    static var description: IntentDescription { "Adds the goal's quick amount, or ticks off its next subtask." }

    // A non-optional @Parameter needs an explicit `default:` — without one it isn't reliably
    // archived into a widget `Button(intent:)`, and the tap never reaches `perform()`.
    @Parameter(title: "Goal", default: "")
    var goalID: String

    init() {}

    init(goalID: UUID) {
        self.goalID = goalID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: goalID) else { return .result() }

        let context = ModelContext(SharedStore.container)
        let all = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        guard let goal = all.first(where: { $0.id == id }) else {
            log.error("goal \(id, privacy: .public) not found among \(all.count)")
            return .result()
        }

        ProgressLogger.performQuickAction(on: goal, in: context)
        do {
            try context.save()
        } catch {
            log.error("save failed: \(error, privacy: .public)")
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
