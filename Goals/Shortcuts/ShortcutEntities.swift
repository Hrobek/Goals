//
//  ShortcutEntities.swift
//  Goals
//
//  The habits and goals as App Entities, so Siri, Shortcuts and Spotlight can offer them by name
//  instead of the bare UUID string the widget intents carry.
//

import AppIntents
import SwiftData

/// Reads for the entity queries and the intents that act on them. Always the app's main context:
/// these intents run in the app process, and a change made there shows up in any open screen at
/// once instead of waiting on a merge from a side context.
enum ShortcutData {
    static var context: ModelContext { SharedStore.container.mainContext }

    /// The current user's habits, archived ones included - an already-configured shortcut should
    /// still resolve its habit, even if it's since been archived. Filtered in Swift rather than in
    /// a `#Predicate`, the same caution `HabitCheckInIntent` takes.
    static func habits() -> [Habit] {
        guard let userId = LocalProfile.currentUserId else { return [] }
        let all = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        return all.filter { $0.ownerId == userId }
    }

    static func goals() -> [Goal] {
        guard let userId = LocalProfile.currentUserId else { return [] }
        let all = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        return all.filter { $0.ownerId == userId }
    }

    /// What a picker or Siri should offer: live habits, in the user's own order.
    static func activeHabits() -> [Habit] {
        habits()
            .filter { !$0.isArchived }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Goals still being worked on, most urgent first.
    static func activeGoals() -> [Goal] {
        goals()
            .filter { !$0.isArchived && !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func habit(id: UUID) -> Habit? {
        habits().first { $0.id == id }
    }

    static func goal(id: UUID) -> Goal? {
        goals().first { $0.id == id }
    }

    /// Saves, then lets the watch know there's something new to show.
    static func save() {
        try? context.save()
        WatchConnectivityBridge.shared.pokeCounterpart()
    }
}

// MARK: - Habit

struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Habit" }
    static var defaultQuery: HabitEntityQuery { HabitEntityQuery() }

    let id: UUID
    let title: String
    let emoji: String?

    init(_ habit: Habit) {
        id = habit.id
        title = habit.title
        emoji = habit.emoji
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ShortcutText.label(title, emoji: emoji))")
    }
}

struct HabitEntityQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        ShortcutData.habits()
            .filter { identifiers.contains($0.id) }
            .map(HabitEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [HabitEntity] {
        ShortcutData.activeHabits()
            .filter { $0.title.localizedStandardContains(string) }
            .map(HabitEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [HabitEntity] {
        ShortcutData.activeHabits().map(HabitEntity.init)
    }
}

// MARK: - Goal

struct GoalEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Goal" }
    static var defaultQuery: GoalEntityQuery { GoalEntityQuery() }

    let id: UUID
    let title: String
    let emoji: String?

    init(_ goal: Goal) {
        id = goal.id
        title = goal.title
        emoji = goal.emoji
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ShortcutText.label(title, emoji: emoji))")
    }
}

struct GoalEntityQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [GoalEntity] {
        ShortcutData.goals()
            .filter { identifiers.contains($0.id) }
            .map(GoalEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [GoalEntity] {
        ShortcutData.activeGoals()
            .filter { $0.title.localizedStandardContains(string) }
            .map(GoalEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [GoalEntity] {
        ShortcutData.activeGoals().map(GoalEntity.init)
    }
}

enum ShortcutText {
    /// "📚 Reading", or just "Reading" when there's no emoji.
    static func label(_ title: String, emoji: String?) -> String {
        guard let emoji, !emoji.isEmpty else { return title }
        return "\(emoji) \(title)"
    }
}
