//
//  CloudKitSyncWaiter.swift
//  Goals
//

import CoreData
import Foundation

/// Waits for the synced store to finish its next CloudKit export or import.
///
/// Used where the process would otherwise be suspended before the sync ran: the phone woken by
/// the watch to upload what its widgets logged (export), and the watch woken by a CloudKit push
/// (import).
nonisolated enum CloudKitSyncWaiter {
    /// Returns once an event of `type` that started after the call has finished, or after
    /// `timeout`, whichever comes first. With `includingInFlight`, one already running when the
    /// call was made counts too. Returns whether it saw the event finish.
    @discardableResult
    static func waitForNext(
        _ type: NSPersistentCloudKitContainer.EventType,
        includingInFlight: Bool = false,
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
                          includingInFlight || event.startDate >= started.addingTimeInterval(-1),
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
