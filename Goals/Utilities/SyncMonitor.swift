//
//  SyncMonitor.swift
//  Goals
//

import Foundation
import Observation
import CoreData
import os
#if canImport(CloudKit)
import CloudKit
#endif

/// Surfaces what CloudKit sync is doing, for the iCloud settings screen. SwiftData drives sync
/// through an `NSPersistentCloudKitContainer` under the hood, which posts `eventChangedNotification`
/// for every setup / import / export — this listens for those and remembers the last outcome
/// (persisted to the App Group so it survives a relaunch), plus the iCloud account state.
@MainActor
@Observable
final class SyncMonitor {
    enum AccountState {
        case unknown, available, noAccount, restricted
    }

    private(set) var accountState: AccountState = .unknown
    /// An import or export is in flight.
    private(set) var isSyncing = false
    /// When the last import or export finished cleanly.
    private(set) var lastSync: Date?
    /// The last sync error, if the most recent event failed.
    private(set) var lastErrorMessage: String?

    private let defaults = UserDefaults(suiteName: SharedStore.appGroupID)
    private static let lastSyncKey = "Goals.sync.lastSuccess"
    private static let lastErrorKey = "Goals.sync.lastError"
    private static let log = Logger(subsystem: "com.hrobek.goals", category: "SyncMonitor")

    /// Whether sync is even meant to be running — the settings screen uses this to decide whether
    /// to show a status block at all.
    var isSyncEnabled: Bool { SharedStore.isCloudSyncEnabled }

    init() {
        lastSync = defaults?.object(forKey: Self.lastSyncKey) as? Date
        lastErrorMessage = defaults?.string(forKey: Self.lastErrorKey)

        guard SharedStore.isCloudSyncEnabled else { return }

        _ = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event else { return }
            Task { @MainActor in self?.handle(event) }
        }

        refreshAccountState()
    }

    /// Re-checks the iCloud account — cheap, worth doing whenever the settings screen appears or
    /// the app returns to the foreground.
    func refreshAccountState() {
        #if canImport(CloudKit)
        CKContainer(identifier: SharedStore.cloudKitContainerID).accountStatus { [weak self] status, error in
            if let error { Self.log.error("accountStatus: \(error, privacy: .public)") }
            let mapped: AccountState = switch status {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            default: .unknown
            }
            Task { @MainActor in self?.accountState = mapped }
        }
        #endif
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        // An event with no end date has only just started.
        guard let endDate = event.endDate else {
            isSyncing = true
            return
        }
        isSyncing = false

        if let error = event.error {
            logSyncFailure(event.type, error)

            // A partial failure (some records rejected) or a network hiccup clears itself on the
            // next sync cycle — `NSPersistentCloudKitContainer` retries. The log above has the
            // per-record detail; the user doesn't need to see a raw "CKErrorDomain error 2".
            guard !Self.isTransient(error) else { return }

            lastErrorMessage = error.localizedDescription
            defaults?.set(error.localizedDescription, forKey: Self.lastErrorKey)
            return
        }

        lastErrorMessage = nil
        defaults?.removeObject(forKey: Self.lastErrorKey)

        if event.type == .import || event.type == .export {
            lastSync = endDate
            defaults?.set(endDate, forKey: Self.lastSyncKey)
        }
    }

    /// Logs the failure, and for a CloudKit partial failure walks `CKPartialErrorsByItemIDKey`
    /// (and any nested underlying errors) so the log names which records failed and why.
    private func logSyncFailure(_ type: NSPersistentCloudKitContainer.EventType, _ error: Error) {
        Self.log.error("sync \(String(describing: type), privacy: .public) failed: \(error, privacy: .public)")
        #if canImport(CloudKit)
        Self.logPartialErrors(error, indent: "  ", depth: 0)
        #endif
    }

    #if canImport(CloudKit)
    /// True when the error (or something it wraps) is a CloudKit code that the mirroring delegate
    /// retries on its own — nothing for the user to act on.
    private static func isTransient(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var hops = 0
        while let e = current, hops < 5 {
            if e.domain == CKErrorDomain, transientCKCodes.contains(e.code) { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
            hops += 1
        }
        return false
    }

    private static let transientCKCodes: Set<Int> = [
        CKError.Code.partialFailure.rawValue,
        CKError.Code.networkUnavailable.rawValue,
        CKError.Code.networkFailure.rawValue,
        CKError.Code.serviceUnavailable.rawValue,
        CKError.Code.requestRateLimited.rawValue,
        CKError.Code.zoneBusy.rawValue,
    ]

    private static func logPartialErrors(_ error: Error, indent: String, depth: Int) {
        guard depth < 4 else { return }
        let ns = error as NSError

        if let perItem = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for (id, sub) in perItem {
                let subNS = sub as NSError
                log.error("\(indent, privacy: .public)· \(String(describing: id), privacy: .public): \(subNS.domain, privacy: .public) \(subNS.code) \(subNS.localizedDescription, privacy: .public)")
                logPartialErrors(sub, indent: indent + "  ", depth: depth + 1)
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            logPartialErrors(underlying, indent: indent, depth: depth + 1)
        }
    }
    #endif
}
