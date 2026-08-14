//
//  GoalsApp.swift
//  Goals
//

import SwiftUI
import SwiftData

@main
struct GoalsApp: App {
    @State private var session = AuthSession()
    private let modelContainer = SharedStore.container

    init() {
        Category.seedDefaultsIfNeeded(context: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .modelContainer(modelContainer)
    }
}
