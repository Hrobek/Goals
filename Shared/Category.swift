//
//  Category.swift
//  Goals
//

import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    static func seedDefaultsIfNeeded(context: ModelContext) {
        let existingCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard existingCount == 0 else { return }

        let health = String(localized: "category.health", defaultValue: "Health", bundle: AppLanguage.currentBundle)
        let career = String(localized: "category.career", defaultValue: "Career", bundle: AppLanguage.currentBundle)
        let finance = String(localized: "category.finance", defaultValue: "Finance", bundle: AppLanguage.currentBundle)
        let relationships = String(localized: "category.relationships", defaultValue: "Relationships", bundle: AppLanguage.currentBundle)

        context.insert(Category(name: health))
        context.insert(Category(name: career))
        context.insert(Category(name: finance))
        context.insert(Category(name: relationships))
    }
}
