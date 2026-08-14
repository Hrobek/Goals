//
//  CheckIn.swift
//  Goals
//

import Foundation
import SwiftData

@Model
final class CheckIn {
    var id: UUID
    var date: Date
    var note: String?
    var valueSnapshot: Double?
    var goal: Goal?

    init(id: UUID = UUID(), date: Date = .now, note: String? = nil, valueSnapshot: Double? = nil, goal: Goal? = nil) {
        self.id = id
        self.date = date
        self.note = note
        self.valueSnapshot = valueSnapshot
        self.goal = goal
    }
}
