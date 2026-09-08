//
//  GoalsWatchApp.swift
//  GoalsWatch
//

import SwiftUI
import SwiftData

@main
struct GoalsWatchApp: App {
    private let modelContainer = SharedStore.container

    init() {
        WatchConnectivityBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .tint(WatchTheme.accent)
        }
        .modelContainer(modelContainer)
    }
}

/// The sliver of the iOS `Theme` the watch needs. The full `Theme` resolves to the light ramp
/// without UIKit, which reads wrong on the watch's always-black ground — so the watch pins its
/// own handful of colours instead.
enum WatchTheme {
    static let accent = Ramp.red400
    static let track = Color.white.opacity(0.16)
    static let faint = Color.white.opacity(0.55)
}
