//
//  WidgetIntentSync.swift
//  Goals
//

#if os(iOS)
import AppIntents
import CoreData
import Foundation

// The iPhone widget buttons are declared as `LiveActivityIntent`s for one side effect: the system
// then runs `perform()` in the app's process (launching it in the background if it isn't running)
// instead of the widget extension's. Only the app opens the CloudKit-synced store - the extension
// writes to the plain local one - so a tap handled in the extension stayed off iCloud, and off
// the watch, until the app was next opened.
extension HabitCheckInIntent: LiveActivityIntent {}
extension QuickActionIntent: LiveActivityIntent {}

/// What a widget button does once its change is saved.
nonisolated enum WidgetIntentSync {
    /// Keeps the app alive in the background until CloudKit has exported the change that was
    /// just saved, so a widget tap reaches iCloud (and from there the watch) right away. Returns
    /// immediately, so the widget redraws without waiting on the network. A no-op in the widget
    /// extension or with iCloud sync off, where there's nothing to export.
    static func flushToCloud() {
        guard Bundle.main.bundleURL.pathExtension != "appex", SharedStore.isCloudSyncEnabled else { return }
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Upload widget check-in") { expired in
            // Called a second time with `true` if the system wants the time back; the first call's
            // wait then just ends at the system's say-so.
            guard !expired else { return }
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await CloudKitSyncWaiter.waitForNext(.export, timeout: .seconds(25))
                done.signal()
            }
            done.wait()
        }
    }
}
#endif
