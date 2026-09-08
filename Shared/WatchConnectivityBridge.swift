//
//  WatchConnectivityBridge.swift
//  Goals
//
//  The one link between the iPhone app and the watch app that isn't CloudKit. CloudKit carries
//  the goals and habits themselves; this carries the two things CloudKit can't:
//
//  1. **Identity.** Every stored row is scoped to `LocalProfile.currentUserId`, which the iOS app
//     mints once and writes into *its* App Group. The watch has its own, separate App Group
//     container, so without this the watch would fetch with a nil user id and show nothing. The
//     phone pushes the id (plus nickname and the cloud-sync flag) as the WatchConnectivity
//     application context; the watch caches it into its App Group so `LocalProfile`, `SharedStore`
//     and `Vacation` all resolve.
//  2. **Immediacy.** A check-off on either side sends a lightweight "poke" so the other side
//     reloads its widgets and views now, rather than whenever CloudKit next pushes.
//
//  Declared `nonisolated` so it compiles the same whether or not the target defaults to MainActor
//  isolation. It keeps no mutable stored state — the "last pushed context" lives in App Group
//  `UserDefaults`, which is thread-safe — so `@unchecked Sendable` is honest.
//

import Foundation
import WatchConnectivity
import WidgetKit
import os

extension Notification.Name {
    /// Posted on the main queue when the counterpart device reports a change (a poke), or when the
    /// watch has just applied a fresh identity context. Views observe it to re-fetch immediately.
    static let watchDataDidChange = Notification.Name("Goals.watchDataDidChange")
}

/// Keys in the application-context dictionary. Shared so both sides spell them the same.
nonisolated enum WatchContextKey {
    static let profileID = "profileID"
    static let nickname = "nickname"
    static let cloudSyncEnabled = "cloudSyncEnabled"
    static let language = "language"
    static let vacationActive = "vacationActive"
    static let vacationStart = "vacationStart"
    static let vacationEnd = "vacationEnd"
    static let vacationPausedIDs = "vacationPausedIDs"
    static let stamp = "stamp"
    /// A bare request from the watch asking the phone to re-send the context.
    static let requestContext = "requestContext"
    /// A change notification — the sender logged something.
    static let poke = "poke"
}

nonisolated final class WatchConnectivityBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchConnectivityBridge()

    private static let log = Logger(subsystem: "com.hrobek.goals", category: "WatchConnectivity")

    /// Where the phone stashes the last context it built, so a `requestContext` from the watch can
    /// be answered without the app rebuilding it.
    private static let lastContextKey = "Goals.watch.lastPushedContext"

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    private override init() { super.init() }

    /// Call once at launch on both platforms.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - iOS → watch

    /// Push the local identity to the watch. Safe to call repeatedly; WatchConnectivity coalesces
    /// and only the newest context is delivered.
    func pushIdentity(
        profileID: UUID,
        nickname: String,
        cloudSyncEnabled: Bool,
        language: String,
        vacation: Vacation
    ) {
        let context: [String: Any] = [
            WatchContextKey.profileID: profileID.uuidString,
            WatchContextKey.nickname: nickname,
            WatchContextKey.cloudSyncEnabled: cloudSyncEnabled,
            WatchContextKey.language: language,
            WatchContextKey.vacationActive: vacation.isActive,
            WatchContextKey.vacationStart: vacation.start,
            WatchContextKey.vacationEnd: vacation.end,
            WatchContextKey.vacationPausedIDs: vacation.pausedItemIDs.map(\.uuidString),
            // A monotonic stamp so an unchanged context still counts as "new" and gets delivered.
            WatchContextKey.stamp: Date().timeIntervalSince1970
        ]
        UserDefaults(suiteName: SharedStore.appGroupID)?.set(context, forKey: Self.lastContextKey)
        send(context: context)
    }

    // MARK: - Either direction

    /// Tell the counterpart "I just logged something — refresh." Delivered in the background via
    /// `transferUserInfo`, plus an immediate `sendMessage` when the other side is reachable.
    func pokeCounterpart() {
        guard let session, session.activationState == .activated else { return }
        let payload = [WatchContextKey.poke: true]
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                Self.log.debug("poke sendMessage failed (non-fatal): \(error, privacy: .public)")
            }
        }
    }

    // MARK: - watch → iOS

    /// Ask the phone to re-send the identity context. Used by the watch when it still has no
    /// resolved profile id.
    func requestIdentity() {
        guard let session, session.activationState == .activated else { return }
        let payload = [WatchContextKey.requestContext: true]
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - Helpers

    private func send(context: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            Self.log.error("updateApplicationContext failed: \(error, privacy: .public)")
        }
    }

    private func resendLastContext() {
        guard let context = UserDefaults(suiteName: SharedStore.appGroupID)?
            .dictionary(forKey: Self.lastContextKey) else { return }
        send(context: context)
    }

    private static func notifyChange(applyingContext context: [String: Any]? = nil) {
        #if os(watchOS)
        if let context { WatchContextResolver.apply(context) }
        #endif
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .watchDataDidChange, object: nil)
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Self.log.error("activation failed: \(error, privacy: .public)")
            return
        }
        guard state == .activated else { return }
        #if os(watchOS)
        let cached = session.receivedApplicationContext
        if !cached.isEmpty {
            Self.notifyChange(applyingContext: cached)
        }
        if LocalProfile.currentUserId == nil {
            requestIdentity()
        }
        #else
        resendLastContext()
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(watchOS)
        Self.notifyChange(applyingContext: applicationContext)
        #endif
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    private func handleIncoming(_ payload: [String: Any]) {
        if payload[WatchContextKey.requestContext] != nil {
            #if os(iOS)
            resendLastContext()
            #endif
            return
        }
        if payload[WatchContextKey.poke] != nil {
            Self.notifyChange()
        }
    }
}

#if os(watchOS)
/// Writes an identity context received from the phone into the watch's App Group, under the exact
/// keys `LocalProfile`, `SharedStore` and `Vacation` read.
nonisolated enum WatchContextResolver {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroupID) }

    static func apply(_ context: [String: Any]) {
        guard let defaults else { return }

        if let idString = context[WatchContextKey.profileID] as? String, let id = UUID(uuidString: idString) {
            LocalProfile.applyPushedIdentity(id: id, nickname: context[WatchContextKey.nickname] as? String ?? "")
        }
        if let cloudSync = context[WatchContextKey.cloudSyncEnabled] as? Bool {
            SharedStore.isCloudSyncEnabled = cloudSync
        }
        if let language = context[WatchContextKey.language] as? String, !language.isEmpty {
            // Same key `AppLanguage.current` reads — the watch app follows the phone's in-app
            // language pick rather than the watch's system language.
            defaults.set(language, forKey: "Goals.appLanguage")
        }
        if let userId = LocalProfile.currentUserId {
            // Write straight to the keys `Vacation.current(for:)` reads — `Vacation` itself is a
            // main-actor type in this build and this runs off the main actor.
            let prefix = "Goals.vacation"
            let id = userId.uuidString
            defaults.set(context[WatchContextKey.vacationActive] as? Bool ?? false, forKey: "\(prefix).active.\(id)")
            if let start = context[WatchContextKey.vacationStart] as? Date { defaults.set(start, forKey: "\(prefix).start.\(id)") }
            if let end = context[WatchContextKey.vacationEnd] as? Date { defaults.set(end, forKey: "\(prefix).end.\(id)") }
            let pausedIDs = (context[WatchContextKey.vacationPausedIDs] as? [String]) ?? []
            defaults.set(pausedIDs, forKey: "\(prefix).paused.\(id)")
        }
        defaults.set(true, forKey: "Goals.watch.hasReceivedContext")
    }

    static var hasReceivedContext: Bool {
        defaults?.bool(forKey: "Goals.watch.hasReceivedContext") ?? false
    }
}
#endif
