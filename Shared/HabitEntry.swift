//
//  HabitEntry.swift
//  Goals
//

import Foundation
import SwiftData

/// One day's worth of doing a habit. At most one per (habit, day) — `HabitLogger` keeps it that
/// way — with `count` for habits that want more than one tick a day ("8 glasses of water").
@Model
final class HabitEntry {
    var id: UUID = UUID()
    var ownerId: UUID = Goal.unownedId
    var date: Date = Date.now
    var count: Int = 1
    var habit: Habit?

    init(id: UUID = UUID(), ownerId: UUID, date: Date = .now, count: Int = 1, habit: Habit? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.date = date
        self.count = count
        self.habit = habit
    }
}
