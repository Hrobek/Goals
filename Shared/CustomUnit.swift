//
//  CustomUnit.swift
//  Goals
//

import Foundation
import SwiftData

/// A unit the user typed in themselves. Stored like categories so it stays available
/// for later goals instead of living on a single goal.
@Model
final class CustomUnit {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var name: String = ""
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), ownerId: UUID, name: String, createdAt: Date = .now) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.createdAt = createdAt
    }
}
