//
//  Category.swift
//  Goals
//

import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var name: String = ""
    var createdAt: Date = Date.now
    /// Set only for the four seeded categories ("health", "career", "finance", "relationships").
    /// `name` is a point-in-time snapshot taken at seed time in whatever language was active then;
    /// `displayName` re-resolves from this key so the label follows later language changes. Nil for
    /// user-created categories, whose `name` is the only source of truth.
    var defaultKey: String?

    init(id: UUID = UUID(), ownerId: UUID, name: String, createdAt: Date = .now, defaultKey: String? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.createdAt = createdAt
        self.defaultKey = defaultKey
    }

    /// The four seeded categories are pre-translated into every shipped language, keyed by the
    /// `defaultKey`. Used to recognize already-seeded categories from before `defaultKey` existed,
    /// no matter which app language they were originally created under.
    private static let knownDefaultNames: [String: Set<String>] = [
        "health": ["Health", "Zdraví", "Gesundheit", "Salud", "Santé", "Saúde"],
        "career": ["Career", "Kariéra", "Karriere", "Carrera", "Carrière", "Carreira"],
        "finance": ["Finance", "Finanzen", "Finanzas", "Finances", "Finanças"],
        "relationships": ["Relationships", "Vztahy", "Beziehungen", "Relaciones", "Relations", "Relacionamentos"],
    ]

    var displayName: String {
        guard let defaultKey else { return name }
        return Self.localizedDefaultName(for: defaultKey) ?? name
    }

    /// The one place that resolves a default category's translated name, keyed by a literal
    /// (compile-time) string per case so it can carry a real `defaultValue:` fallback — unlike a
    /// dynamically-interpolated key, which can't. Returns `nil` for anything outside the four
    /// known keys, so callers can fall back to whatever's appropriate for them.
    private static func localizedDefaultName(for key: String) -> String? {
        switch key {
        case "health": String(localized: "category.health", defaultValue: "Health", bundle: AppLanguage.currentBundle)
        case "career": String(localized: "category.career", defaultValue: "Career", bundle: AppLanguage.currentBundle)
        case "finance": String(localized: "category.finance", defaultValue: "Finance", bundle: AppLanguage.currentBundle)
        case "relationships": String(localized: "category.relationships", defaultValue: "Relationships", bundle: AppLanguage.currentBundle)
        default: nil
        }
    }

    static func seedDefaultsIfNeeded(context: ModelContext, for userId: UUID) {
        // Seeding is a one-time-ever thing per account, not "whenever the count is zero" — the
        // latter would recreate the defaults if a user deletes them and then signs out and back
        // into the same account without restarting the app.
        let seededKey = "Goals.didSeedDefaults.\(userId.uuidString)"
        let seedFlags = UserDefaults(suiteName: SharedStore.appGroupID)
        guard seedFlags?.bool(forKey: seededKey) != true else { return }
        seedFlags?.set(true, forKey: seededKey)

        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.ownerId == userId })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for key in ["health", "career", "finance", "relationships"] {
            context.insert(Category(ownerId: userId, name: localizedDefaultName(for: key) ?? key, defaultKey: key))
        }
    }

    /// Backfills `defaultKey` on this user's own categories seeded before it existed, so they
    /// start following language changes instead of staying frozen in whatever language they were
    /// first created in. Scoped by `ownerId` so one account's category names can never be matched
    /// against — and silently relabeled as — another account's on a shared device.
    static func migrateDefaultKeysIfNeeded(context: ModelContext, for userId: UUID) {
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.ownerId == userId })
        guard let categories = try? context.fetch(descriptor) else { return }
        for category in categories where category.defaultKey == nil {
            for (key, names) in knownDefaultNames where names.contains(category.name) {
                category.defaultKey = key
                break
            }
        }
    }
}
