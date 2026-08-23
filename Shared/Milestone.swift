//
//  Milestone.swift
//  Goals
//

import Foundation
import SwiftData

@Model
final class Milestone {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var title: String = ""
    var isCompleted: Bool = false
    var order: Int = 0
    var goal: Goal?

    init(id: UUID = UUID(), ownerId: UUID, title: String, isCompleted: Bool = false, order: Int = 0, goal: Goal? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
        self.goal = goal
    }
}
