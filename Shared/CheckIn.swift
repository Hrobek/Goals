//
//  CheckIn.swift
//  Goals
//

import Foundation
import SwiftData

@Model
final class CheckIn {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var date: Date = Date.now
    var note: String?
    var valueSnapshot: Double?
    /// UUIDs (as strings) of the HealthKit samples this check-in wrote, for a `.write`-linked goal.
    /// Same purpose as `HabitEntry.healthKitSampleIDs` - lets an undo delete exactly these samples.
    private var storedHealthKitSampleIDs: [String]?
    var goal: Goal?

    init(id: UUID = UUID(), ownerId: UUID, date: Date = .now, note: String? = nil, valueSnapshot: Double? = nil, goal: Goal? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.date = date
        self.note = note
        self.valueSnapshot = valueSnapshot
        self.goal = goal
    }

    var healthKitSampleIDs: [String] {
        get { storedHealthKitSampleIDs ?? [] }
        set { storedHealthKitSampleIDs = newValue.isEmpty ? nil : newValue }
    }
}
