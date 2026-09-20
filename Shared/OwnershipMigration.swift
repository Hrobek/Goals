//
//  OwnershipMigration.swift
//  Goals
//

import Foundation
import SwiftData

/// Claims every row in the local store that isn't already owned by the current profile. There are
/// no accounts in this app - one device install is one person - so any row with a different
/// `ownerId` can only be this same person's own data under an id they no longer hold: the retired
/// account system's `Goal.unownedId` sentinel, an old per-user-isolation id, or (see
/// `LocalProfile`) a profile id from before the app was deleted and reinstalled, which iCloud sync
/// still faithfully mirrored back down under its original `ownerId`. Claiming everything rather
/// than just the sentinel means a reinstall that predates `LocalProfile`'s Keychain fix - or any
/// future way an id gets lost - still recovers the data once iCloud has it back on the device.
/// Cheap to call repeatedly: once claimed, every fetch here comes back empty.
enum OwnershipMigration {
    static func claimOrphanData(for userId: UUID, context: ModelContext) {
        let goalDescriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId != userId })
        if let orphanGoals = try? context.fetch(goalDescriptor), !orphanGoals.isEmpty {
            for goal in orphanGoals {
                goal.ownerId = userId
                for milestone in goal.milestones { milestone.ownerId = userId }
                for checkIn in goal.checkIns { checkIn.ownerId = userId }
            }
        }

        let habitDescriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId != userId })
        if let orphanHabits = try? context.fetch(habitDescriptor), !orphanHabits.isEmpty {
            for habit in orphanHabits {
                habit.ownerId = userId
                for entry in habit.entries { entry.ownerId = userId }
            }
        }

        let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.ownerId != userId })
        if let orphanCategories = try? context.fetch(categoryDescriptor) {
            for category in orphanCategories { category.ownerId = userId }
        }

        let unitDescriptor = FetchDescriptor<CustomUnit>(predicate: #Predicate { $0.ownerId != userId })
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
