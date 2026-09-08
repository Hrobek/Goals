//
//  GoalsApp.swift
//  Goals
//

import SwiftUI
import SwiftData

@main
struct GoalsApp: App {
    @State private var profile = Profile()
    @State private var purchaseManager = PurchaseManager()
    @State private var syncMonitor = SyncMonitor()
    private let modelContainer = SharedStore.container

    init() {
        // Rows created before per-user isolation carry `Goal.unownedId`; rows created under the
        // retired account system carry that account's id, which `Profile` adopts as the device id.
        // Either way, claim everything for the one local identity and seed its defaults.
        OwnershipMigration.claimOrphanData(for: profile.id, context: modelContainer.mainContext)
        Category.migrateDefaultKeysIfNeeded(context: modelContainer.mainContext, for: profile.id)
        Category.seedDefaultsIfNeeded(context: modelContainer.mainContext, for: profile.id)
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
