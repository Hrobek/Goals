//
//  GoalsApp.swift
//  Goals
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct GoalsApp: App {
    // Plain `let`, not `@State`: `GoalsApp` is built exactly once for the process's life, and
    // each of these is an `@Observable` reference type, so there's no reassignment for `@State`
    // to preserve across rebuilds. `@State` would only be safe to read after SwiftUI installs it
    // on the view - `init()` needs `profile.id` immediately, before that ever happens.
    private let profile = Profile()
    private let purchaseManager = PurchaseManager()
    private let syncMonitor = SyncMonitor()
    private let modelContainer = SharedStore.container

    init() {
        // Rows created before per-user isolation carry `Goal.unownedId`; rows created under the
        // retired account system carry that account's id, which `Profile` adopts as the device id.
        // Either way, claim everything for the one local identity and seed its defaults.
        OwnershipMigration.claimOrphanData(for: profile.id, context: modelContainer.mainContext)
        Category.migrateDefaultKeysIfNeeded(context: modelContainer.mainContext, for: profile.id)
        Category.seedDefaultsIfNeeded(context: modelContainer.mainContext, for: profile.id)

        // The watch app has no identity of its own — push this one to it (and stay listening for
        // its check-off pokes).
        WatchConnectivityBridge.shared.activate()

        // So tapping a goal or habit reminder opens that goal or habit, not just the app.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profile)
                .environment(purchaseManager)
                .environment(syncMonitor)
        }
        .modelContainer(modelContainer)
    }
}
