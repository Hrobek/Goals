//
//  SharedStore.swift
//  Goals
//

import Foundation
import SwiftData
import os

/// The SwiftData store, living in the App Group container so the widget extension reads and
/// writes the same database as the app.
enum SharedStore {
    static let appGroupID = "group.com.hrobek.goals"
    static let cloudKitContainerID = "iCloud.com.hrobek.goals"

    static let schema = Schema([
        Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self,
        Habit.self, HabitEntry.self
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
    /// CloudKit is the app process's job. The widget extension has no CloudKit entitlement (adding
    /// one drags in a signing capability and, if the profile misses it, the extension won't even
    /// launch) — it opens the local store the app keeps mirrored, and a write from its button
    /// reaches the app through Core Data's cross-process change notifications.
    private static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    static let container: ModelContainer = {
        migrateLocalStoreIfNeeded()

        let wantsCloudKit = isCloudSyncEnabled && !isAppExtension

        if let container = makeContainer(cloudKit: wantsCloudKit ? .private(cloudKitContainerID) : .none) {
            return container
        }

        if wantsCloudKit, let container = makeContainer(cloudKit: .none) {
            log.error("Opened the store without CloudKit after the synced configuration failed.")
            return container
        }

        log.error("Store could not be opened — moving it aside and starting fresh.")
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
