//
//  TodayAndOpenIntents.swift
//  Goals
//
//  "What's left today?" and the open-a-habit / open-a-goal shortcuts.
//

import AppIntents
import Observation
import SwiftData

// MARK: - Today

struct TodayStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "What's left today" }
    static var description: IntentDescription {
        IntentDescription("Tells you how much of today is done and what's still left.", categoryName: "Today")
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let userId = LocalProfile.currentUserId else {
            return .result(value: 0, dialog: "Open Goals once to get started.")
        }
        let summary = TodaySchedule.summary(userId: userId, context: ShortcutData.context)
        let left = summary.items.filter { !$0.isDone }
        let remaining = left.count

        if summary.isEmpty {
            return .result(value: 0, dialog: "Nothing is planned for today.")
        }
        if left.isEmpty {
            return .result(value: 0, dialog: "All done for today, \(summary.done) of \(summary.total).")
        }
        let names = left.map(\.title).formatted(.list(type: .and))
        return .result(value: remaining, dialog: "\(summary.done) of \(summary.total) done. Still left: \(names).")
    }
}

// MARK: - Open

/// Hands a deep link from an intent to `RootView`. An intent that opens the app can run before
/// the root view is even on screen (a cold launch), so the link is parked here rather than fired
/// as a one-shot notification, and `RootView` picks it up whenever it's ready.
@Observable
final class ShortcutRouter {
    static let shared = ShortcutRouter()
    var pendingURL: URL?
}

struct OpenHabitIntent: OpenIntent {
    static var title: LocalizedStringResource { "Open habit" }
    static var description: IntentDescription {
        IntentDescription("Opens a habit in Goals.", categoryName: "Habits")
    }

    @Parameter(title: "Habit")
    var target: HabitEntity

    @MainActor func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pendingURL = URL(string: "goals://habit/\(target.id.uuidString)")
        return .result()
    }
}

struct OpenGoalIntent: OpenIntent {
    static var title: LocalizedStringResource { "Open goal" }
    static var description: IntentDescription {
        IntentDescription("Opens a goal in Goals.", categoryName: "Goals")
    }

    @Parameter(title: "Goal")
    var target: GoalEntity

    @MainActor func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pendingURL = URL(string: "goals://goal/\(target.id.uuidString)")
        return .result()
    }
}
