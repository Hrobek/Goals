//
//  AppShortcuts.swift
//  Goals
//

import AppIntents

/// The shortcuts Goals offers out of the box - in Siri, Spotlight and the Shortcuts app - with no
/// setup.
///
/// This provider also has a second job: the widget extension's `Button(intent:)` taps only reach
/// their `perform()` once the app vends at least one App Shortcut, since that's what brings the
/// AppIntents runtime up for the app side of the pair. Keep at least one shortcut here.
///
/// Phrases are translated in `AppShortcuts.xcstrings`; every one of them has to mention the app.
struct GoalsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHabitIntent(),
            phrases: [
                "Complete \(\.$habit) in \(.applicationName)",
                "Check off \(\.$habit) in \(.applicationName)",
                "Log a habit in \(.applicationName)"
            ],
            shortTitle: "Log habit",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: LogGoalIntent(),
            phrases: [
                "Log progress on \(\.$goal) in \(.applicationName)",
                "Add to \(\.$goal) in \(.applicationName)",
                "Log goal progress in \(.applicationName)"
            ],
            shortTitle: "Log goal progress",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayStatusIntent(),
            phrases: [
                "What's left today in \(.applicationName)",
                "How is my day going in \(.applicationName)",
                "\(.applicationName) today"
            ],
            shortTitle: "What's left today",
            systemImageName: "list.bullet.circle"
        )
        AppShortcut(
            intent: OpenHabitIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show habit \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open habit",
            systemImageName: "repeat.circle"
        )
        AppShortcut(
            intent: OpenGoalIntent(),
            phrases: [
                "Show goal \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open goal",
            systemImageName: "target"
        )
    }
}
