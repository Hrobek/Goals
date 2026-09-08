//
//  SharedStore.swift
//  Goals
//

import Foundation
import SwiftData
import os

/// The SwiftData store, living in the App Group container so the widget extension reads and
/// writes the same database as the app.
///
/// `nonisolated`: everything here is UserDefaults / filesystem / `ModelContainer` construction, none
/// of it main-actor state. The widget extensions already treat it that way; spelling it out keeps
/// it callable from the `WatchConnectivityBridge` (which is nonisolated by necessity) without the
/// app target's default main-actor isolation getting in the way.
nonisolated enum SharedStore {
    static let appGroupID = "group.com.hrobek.goals"
    static let cloudKitContainerID = "iCloud.com.hrobek.goals"

    static let schema = Schema([
        Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self,
        Habit.self, HabitEntry.self, StreakFreeze.self
    ])

    private static let log = Logger(subsystem: "com.hrobek.goals", category: "SharedStore")
    private static let cloudSyncKey = "Goals.cloudSyncEnabled"

    /// Whether the store syncs through CloudKit. Read once, at `container`'s first access — flipping
    /// it from Settings takes effect on the next launch, not live (swapping a running container's
    /// `cloudKitDatabase` would invalidate every `@Query` and context bound to it).
    static var isCloudSyncEnabled: Bool {
        get { UserDefaults(suiteName: appGroupID)?.bool(forKey: cloudSyncKey) ?? false }
        set { UserDefaults(suiteName: appGroupID)?.set(newValue, forKey: cloudSyncKey) }
    }

    /// The container, built defensively: a store that won't open must never crash-loop the app
    /// on every launch. The ladder is
    ///   1. as configured (CloudKit when the user asked for it),
    ///   2. local-only, in case CloudKit is the thing it can't satisfy,
    ///   3. a fresh store with the old file moved aside as a `.bak`, if it's corrupt or can't
    ///      migrate,
    ///   4. in-memory, so the app still runs even if the disk is the problem.
    /// Standing up `NSPersistentCloudKitContainer` in a fresh widget-intent process can overrun
    /// the intent's short time budget, so the tap appears to do nothing. The widget writes to the
    /// plain local store instead; the app's synced container observes that write through Core
    /// Data persistent history and mirrors it up.
    private static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// The watch app has no Settings screen and no local-only story worth having — CloudKit is the
    /// only way goals and habits reach the wrist. So it always opens the synced store; if the phone
    /// has iCloud sync off, that store is simply empty and the UI says so.
    private static var alwaysWantsCloudKit: Bool {
        #if os(watchOS)
        return !isAppExtension
        #else
        return false
        #endif
    }

    static let container: ModelContainer = {
        migrateLocalStoreIfNeeded()

        let wantsCloudKit = (isCloudSyncEnabled || alwaysWantsCloudKit) && !isAppExtension

        if let container = makeContainer(cloudKit: wantsCloudKit ? .private(cloudKitContainerID) : .none) {
            log.notice("store opened (cloudKit=\(wantsCloudKit))")
            return container
        }

        if wantsCloudKit, let container = makeContainer(cloudKit: .none) {
            log.error("Opened the store without CloudKit after the synced configuration failed.")
            return container
        }

        log.error("Store could not be opened - moving it aside and starting fresh.")
        moveStoreAside()
        if let container = makeContainer(cloudKit: .none) {
            return container
        }

        log.fault("Falling back to an in-memory store; changes will not persist.")
        // Truly nothing worked (read-only disk?). An in-memory container keeps the app usable.
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }()

    private static func makeContainer(cloudKit: ModelConfiguration.CloudKitDatabase) -> ModelContainer? {
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: cloudKit)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            log.error("ModelContainer(cloudKit: \(String(describing: cloudKit), privacy: .public)) failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Renames the current store (and its SQLite siblings) to `*.bak-<epoch>` so a failed migration
    /// leaves a fresh, working store behind without destroying the old data outright.
    private static func moveStoreAside() {
        let fileManager = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(filePath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let backup = URL(filePath: storeURL.path + suffix + ".bak-\(stamp)")
            try? fileManager.moveItem(at: source, to: backup)
        }
    }

    private static var sharedDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var storeURL: URL {
        guard let sharedDirectory else { return localStoreURL }
        return sharedDirectory.appending(path: "Goals.store")
    }

    /// Where SwiftData put the database before the App Group existed.
    private static var localStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// One-time move of an existing database into the shared container, so goals created before
    /// the widget shipped don't disappear. SQLite keeps its -wal and -shm siblings; all three go.
    private static func migrateLocalStoreIfNeeded() {
        let fileManager = FileManager.default
        let destination = storeURL
        guard destination != localStoreURL,
              fileManager.fileExists(atPath: localStoreURL.path),
              !fileManager.fileExists(atPath: destination.path) else { return }

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(filePath: localStoreURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.copyItem(at: source, to: URL(filePath: destination.path + suffix))
        }
    }
}
