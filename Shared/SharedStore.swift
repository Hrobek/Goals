//
//  SharedStore.swift
//  Goals
//

import Foundation
import SwiftData

/// The SwiftData store, living in the App Group container so the widget extension reads and
/// writes the same database as the app.
enum SharedStore {
    static let appGroupID = "group.com.hrobek.goals"
    static let cloudKitContainerID = "iCloud.com.hrobek.goals"

    static let schema = Schema([
        Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self
    ])

    private static let cloudSyncKey = "Goals.cloudSyncEnabled"

    /// Whether the store syncs through CloudKit. Read once, at `container`'s first access — flip
    /// it from Settings and it takes effect on the next launch, not live: swapping a running
    /// `ModelContainer`'s `cloudKitDatabase` option would invalidate every `@Query` and context
    /// already bound to it throughout the app and the widget.
    static var isCloudSyncEnabled: Bool {
        get { UserDefaults(suiteName: appGroupID)?.bool(forKey: cloudSyncKey) ?? false }
        set { UserDefaults(suiteName: appGroupID)?.set(newValue, forKey: cloudSyncKey) }
    }

    static let container: ModelContainer = {
        migrateLocalStoreIfNeeded()
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: isCloudSyncEnabled ? .private(cloudKitContainerID) : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

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
