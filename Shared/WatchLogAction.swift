//
//  WatchLogAction.swift
//  Goals
//

#if os(watchOS)
import Foundation
import SwiftData

/// One tap on a row in the watch app. Routes to the same `HabitLogger` / `ProgressLogger` entry
/// points the iOS app and the widgets use, so a check-off from the wrist leaves an identical
/// trace, then pokes the phone to refresh now instead of at the next CloudKit push.
///
/// Plain (non-isolated) like `HabitLogger` itself — callers run it on the main thread, where the
/// watch app's `ModelContext` lives.
enum WatchLogAction {
    /// Logs today's progress for the habit. Mirrors `HabitCheckInIntent.perform()`.
    /// Returns whether the day is now done (for the success haptic).
    @discardableResult
    static func toggle(_ habit: Habit, in context: ModelContext) -> Bool {
        guard !habit.isAvoid else { return habit.isDone(on: .now) }

        if habit.isCheckbox {
            HabitLogger.toggleToday(habit, in: context)
        } else if habit.hasUnit {
            HabitLogger.addQuick(habit, in: context)
        } else {
            HabitLogger.cycle(habit, in: context)
        }
        save(context)
        return habit.isDone(on: .now)
    }

    /// Runs the goal's configured one-tap action. Mirrors the goal widget button.
    @discardableResult
    static func quickAction(_ goal: Goal, in context: ModelContext) -> Bool {
        let changed = ProgressLogger.performQuickAction(on: goal, in: context)
        save(context)
        return changed
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("watch log save failed: \(error)")
        }
        WatchConnectivityBridge.shared.pokeCounterpart()
    }
}
#endif
