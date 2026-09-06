//
//  WidgetDiagnostics.swift
//  Goals
//

import Foundation

/// A tiny ring buffer in the App Group. The widget-extension process writes here; the app reads
/// it back in Settings. On-device Console filtering across processes is unreliable, so this is
/// how we find out whether a widget button's `perform()` actually ran and how far it got.
///
/// Diagnostic only — safe to delete this file and its call sites once the widget intents are
/// confirmed working.
enum WidgetDiagnostics {
    private static let key = "Goals.widgetBreadcrumbs"
    private static let limit = 24

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    static func log(_ message: String) {
        guard let defaults else { return }
        let stamp = timeFormatter.string(from: Date())
        var lines = defaults.stringArray(forKey: key) ?? []
        lines.append("\(stamp)  \(message)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        defaults.set(lines, forKey: key)
    }

    static var lines: [String] {
        defaults?.stringArray(forKey: key) ?? []
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
