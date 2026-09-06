//
//  WidgetDiagnostics.swift
//  Goals
//

import Foundation

/// A tiny append-only log file in the App Group container. The widget-extension process writes
/// here; the app reads it back in Settings. A file (written synchronously) rather than
/// `UserDefaults` so a breadcrumb can't be lost to an unflushed defaults database when the
/// short-lived intent process is torn down right after `perform()`.
///
/// Diagnostic only — safe to delete this file and its call sites once the widget intents are
/// confirmed working.
enum WidgetDiagnostics {
    private static let limit = 40
    private static let queue = DispatchQueue(label: "com.hrobek.goals.WidgetDiagnostics")

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appending(path: "widget-diagnostics.log")
    }

    static func log(_ message: String) {
        guard let fileURL else { return }
        let stamp = timeFormatter.string(from: Date())
        let entry = "\(stamp)  \(message)"
        queue.sync {
            var lines = (try? String(contentsOf: fileURL, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init) ?? []
            lines.append(entry)
            if lines.count > limit { lines.removeFirst(lines.count - limit) }
            try? (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static var lines: [String] {
        guard let fileURL,
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
