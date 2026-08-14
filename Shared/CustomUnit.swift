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
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
