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

    static let schema = Schema([
        Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self
    ])

    static let container: ModelContainer = {
        migrateLocalStoreIfNeeded()
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
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
