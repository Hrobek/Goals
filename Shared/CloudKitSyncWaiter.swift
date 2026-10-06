//
//  CloudKitSyncWaiter.swift
//  Goals
//

import CoreData
import Foundation

/// Waits for the synced store to finish its next CloudKit export or import.
///
/// Used where the process would otherwise be suspended before the sync ran: a widget tap the
/// system launched the app in the background for (export), and the watch woken by a CloudKit
/// push (import). Without it the change sat in the local store until the phone app or the
/// watch app happened to be opened.
nonisolated enum CloudKitSyncWaiter {
    /// Returns once an event of `type` that started after the call has finished, or after
    /// `timeout`, whichever comes first. Returns whether it saw the event finish.
    @discardableResult
    static func waitForNext(
        _ type: NSPersistentCloudKitContainer.EventType,
        timeout: Duration = .seconds(20)
    ) async -> Bool {
        let started = Date()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let events = NotificationCenter.default.notifications(
                    named: NSPersistentCloudKitContainer.eventChangedNotification
                )
                for await note in events {
                    guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                            as? NSPersistentCloudKitContainer.Event,
                          event.type == type,
                          event.startDate >= started.addingTimeInterval(-1),
                          event.endDate != nil else { continue }
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
