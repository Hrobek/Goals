//
//  GoalsApp.swift
//  Goals
//

import SwiftUI
import SwiftData

@main
struct GoalsApp: App {
    @State private var session = AuthSession()
    @State private var purchaseManager = PurchaseManager()
    private let modelContainer = SharedStore.container

    init() {
        // Covers a user who was already signed in before per-user data isolation shipped — they
        // never call `AuthSession.signIn`, since their session is restored directly at launch.
        if let user = session.currentUser {
            OwnershipMigration.claimOrphanData(for: user.id, context: modelContainer.mainContext)
            Category.migrateDefaultKeysIfNeeded(context: modelContainer.mainContext, for: user.id)
            Category.seedDefaultsIfNeeded(context: modelContainer.mainContext, for: user.id)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(purchaseManager)
        }
        .modelContainer(modelContainer)
    }
}
