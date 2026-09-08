//
//  WatchRootView.swift
//  GoalsWatch
//

import SwiftUI
import SwiftData

/// Picks between the Today list and the "open your iPhone" prompt, the only branch the watch app
/// has. The prompt shows until an identity is resolved — normally the moment the paired phone
/// pushes its profile id over WatchConnectivity, or straight away if a previous launch already
/// cached one.
struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var userId: UUID? = LocalProfile.currentUserId
    /// The phone's in-app language pick, mirrored here over WatchConnectivity. Drives the locale
    /// and a full rebuild on change, the same way `RootView` does on the phone — so the watch
    /// follows the app's language, not the watch's system language.
    @State private var languageRaw = AppLanguage.current.rawValue

    var body: some View {
        NavigationStack {
            if let userId {
                WatchTodayView(userId: userId)
            } else {
                WatchNeedsPhoneView()
            }
        }
        .environment(\.locale, (AppLanguage(rawValue: languageRaw) ?? .deviceDefault).locale)
        .id(languageRaw)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchDataDidChange)) { _ in
            refresh()
        }
    }

    private func refresh() {
        languageRaw = AppLanguage.current.rawValue
        resolveIdentity()
    }

    /// Order of preference: a cached id, then the owner of any row CloudKit has already synced
    /// (covers a genuinely standalone watch whose phone hasn't pushed context yet), then nothing —
    /// and ask the phone.
    private func resolveIdentity() {
        if let cached = LocalProfile.currentUserId {
            userId = cached
            return
        }
        if let adopted = WatchIdentityFallback.ownerOfSyncedData(in: modelContext) {
            userId = adopted
            return
        }
        userId = nil
        WatchConnectivityBridge.shared.requestIdentity()
    }
}

/// Last-ditch identity: if the phone never pushed a profile id but CloudKit has mirrored some
/// rows, every row carries the `ownerId` we'd have been told. Adopt the most common one.
enum WatchIdentityFallback {
    static func ownerOfSyncedData(in context: ModelContext) -> UUID? {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let owners = habits.map(\.ownerId) + goals.map(\.ownerId)
        let real = owners.filter { $0 != Goal.unownedId }
        guard !real.isEmpty else { return nil }
        let tally = Dictionary(real.map { ($0, 1) }, uniquingKeysWith: +)
        return tally.max { $0.value < $1.value }?.key
    }
}
