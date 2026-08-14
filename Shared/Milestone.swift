//
//  Milestone.swift
//  Goals
//

import Foundation
import SwiftData

@Model
final class Milestone {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var order: Int
    var goal: Goal?

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, order: Int = 0, goal: Goal? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
        self.goal = goal
    }
}
