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
        Category.seedDefaultsIfNeeded(context: modelContainer.mainContext)
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
