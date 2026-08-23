//
//  OwnershipMigration.swift
//  Goals
//

import Foundation
import SwiftData

/// Claims rows written before per-user data isolation existed. Every `Goal`/`Category`/
/// `CustomUnit` created before this shipped carries `Goal.unownedId` — the first account to sign
/// in (or resume a session) after the update claims all of it, so a single existing user doesn't
/// lose their data. Cheap to call repeatedly: once claimed, the fetch is empty.
enum OwnershipMigration {
    static func claimOrphanData(for userId: UUID, context: ModelContext) {
        let unownedId = Goal.unownedId

        let goalDescriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId == unownedId })
        if let orphanGoals = try? context.fetch(goalDescriptor), !orphanGoals.isEmpty {
            for goal in orphanGoals {
                goal.ownerId = userId
                for milestone in goal.milestones { milestone.ownerId = userId }
                for checkIn in goal.checkIns { checkIn.ownerId = userId }
            }
        }

        let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.ownerId == unownedId })
        if let orphanCategories = try? context.fetch(categoryDescriptor) {
            for category in orphanCategories { category.ownerId = userId }
        }

        let unitDescriptor = FetchDescriptor<CustomUnit>(predicate: #Predicate { $0.ownerId == unownedId })
        if let orphanUnits = try? context.fetch(unitDescriptor) {
            for unit in orphanUnits { unit.ownerId = userId }
        }

        do {
            try context.save()
        } catch {
            // In-memory `ownerId` reassignments above are now out of sync with disk. Surfacing
            // this beats the previous silent `try?` — there's no user-facing recovery to offer,
            // but a future run (next launch or sign-in) will simply retry the same claim.
            assertionFailure("OwnershipMigration failed to save claimed rows: \(error)")
        }
    }
}
