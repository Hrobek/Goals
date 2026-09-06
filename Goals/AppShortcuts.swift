//
//  AppShortcuts.swift
//  Goals
//

import AppIntents
import WidgetKit

/// A trivial intent so the app can vend at least one App Shortcut.
///
/// Why it exists: the widget extension's `Button(intent:)` taps were dispatched
/// ("Starting to run action") but their `perform()` never ran and no intent was even
/// instantiated. The app carried no `AppShortcutsProvider`, so the AppIntents runtime was
/// never fully brought up for the app side of the pair. Declaring one here forces that.
struct RefreshWidgetsIntent: AppIntent {
    static var title: LocalizedStringResource { "Refresh Goals widgets" }
    static var description: IntentDescription { "Reloads every Goals widget." }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct GoalsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshWidgetsIntent(),
            phrases: ["Refresh \(.applicationName) widgets"],
            shortTitle: "Refresh widgets",
            systemImageName: "arrow.clockwise"
        )
    }
}
