//
//  WatchAppDelegate.swift
//  GoalsWatch
//

import CoreData
import WatchKit
import WidgetKit

/// Lets CloudKit reach the watch between launches. Without a push registration the synced store
/// only imported when the app was opened, so a check-off made on the phone (or its widget) could
/// take ages to show on the wrist.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private var importObserver: NSObjectProtocol?

    func applicationDidFinishLaunching() {
        WKApplication.shared().registerForRemoteNotifications()

        // A finished import is the moment new rows from the phone actually land here - refresh the
        // views and the complications then, not just when a WatchConnectivity poke happens to
        // arrive (which usually beats the data it announces).
        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil, event.succeeded else { return }
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .watchDataDidChange, object: nil)
        }
    }

    /// A CloudKit change push. The synced store fetches the change on its own; this only keeps the
    /// app awake until that import has finished, so the complication can redraw with it.
    func didReceiveRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (WKBackgroundFetchResult) -> Void
    ) {
        _ = SharedStore.container
        Task {
            let imported = await CloudKitSyncWaiter.waitForNext(.import, timeout: .seconds(20))
            completionHandler(imported ? .newData : .noData)
        }
    }
}
