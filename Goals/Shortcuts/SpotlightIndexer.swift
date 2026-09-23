//
//  SpotlightIndexer.swift
//  Goals
//
//  Puts every habit and goal into Spotlight, so typing its name on the Home Screen finds it and a
//  tap opens its detail.
//

import AppIntents
import CoreSpotlight
import SwiftUI
import os

private let log = Logger(subsystem: "com.hrobek.goals", category: "Spotlight")

enum SpotlightIndexer {
    private static let habitDomain = "com.hrobek.goals.habit"
    private static let goalDomain = "com.hrobek.goals.goal"

    /// Rebuilds the whole index from the store. Cheap at this app's scale, and a full rebuild is
    /// the simplest way to also drop anything deleted, archived or renamed - here, from the
    /// widget, or on another device through iCloud.
    ///
    /// Each item's identifier is the item's own `goals://` deep link, so a tapped result routes
    /// through the same `RootView.handleDeepLink` a widget tap does.
    static func reindex() async {
        let habits = ShortcutData.activeHabits().map(item(for:))
        let goals = ShortcutData.goals().filter { !$0.isArchived }.map(item(for:))

        let index = CSSearchableIndex.default()
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [habitDomain, goalDomain])
            try await index.indexSearchableItems(habits + goals)
        } catch {
            log.error("reindex failed: \(error, privacy: .public)")
        }
    }

    /// The deep link a tapped result carries, if the activity is a Spotlight tap on one of ours.
    static func deepLink(from activity: NSUserActivity) -> URL? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return URL(string: id)
    }

    // MARK: - Items

    private static func item(for habit: Habit) -> CSSearchableItem {
        let kind = String(localized: "spotlight.habit", defaultValue: "Habit", bundle: AppLanguage.currentBundle)
        var details = [kind, Recurrence.localizedSummary(for: habit)]
        if habit.hasUnit {
            details.append(habit.targetText)
        }

        let attributes = attributeSet(
            title: habit.title,
            emoji: habit.emoji,
            colorHex: habit.colorHex,
            details: details,
            kind: kind
        )
        if #available(iOS 18.0, *) {
            attributes.associateAppEntity(HabitEntity(habit))
        }
        return CSSearchableItem(
            uniqueIdentifier: GoalsDeepLink.habit(habit.id).absoluteString,
            domainIdentifier: habitDomain,
            attributeSet: attributes
        )
    }

    private static func item(for goal: Goal) -> CSSearchableItem {
        let kind = String(localized: "spotlight.goal", defaultValue: "Goal", bundle: AppLanguage.currentBundle)
        var details = [kind]
        if goal.trackingMode == .value {
            let target = goal.targetValue.formatted(.number.precision(.fractionLength(0...1)))
            details.append(goal.valueWithUnit(goal.targetValue, formattedValue: target))
        }
        if goal.isCompleted {
            details.append(GoalStatus.completed.localizedName)
        }

        let attributes = attributeSet(
            title: goal.title,
            emoji: goal.emoji,
            colorHex: goal.colorHex,
            details: details,
            kind: kind
        )
        if #available(iOS 18.0, *) {
            attributes.associateAppEntity(GoalEntity(goal))
        }
        return CSSearchableItem(
            uniqueIdentifier: GoalsDeepLink.goal(goal.id).absoluteString,
            domainIdentifier: goalDomain,
            attributeSet: attributes
        )
    }

    private static func attributeSet(
        title: String,
        emoji: String?,
        colorHex: String,
        details: [String],
        kind: String
    ) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = details.joined(separator: " · ")
        attributes.keywords = [kind]
        attributes.thumbnailData = thumbnail(emoji: emoji, colorHex: colorHex)
        return attributes
    }

    /// The emoji on a tint of the item's color - the same badge the app's rows show. Nil without
    /// an emoji, which leaves Spotlight showing the app icon instead.
    private static func thumbnail(emoji: String?, colorHex: String) -> Data? {
        guard let emoji, !emoji.isEmpty else { return nil }
        let badge = ZStack {
            Circle().fill(Color(hex: colorHex).opacity(0.25))
            Text(emoji).font(.system(size: 34))
        }
        .frame(width: 60, height: 60)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

/// The `goals://` links the app routes in `RootView.handleDeepLink`.
enum GoalsDeepLink {
    static func habit(_ id: UUID) -> URL {
        URL(string: "goals://habit/\(id.uuidString)") ?? URL(string: "goals://")!
    }

    static func goal(_ id: UUID) -> URL {
        URL(string: "goals://goal/\(id.uuidString)") ?? URL(string: "goals://")!
    }
}

@available(iOS 18.0, *)
extension HabitEntity: IndexedEntity {}

@available(iOS 18.0, *)
extension GoalEntity: IndexedEntity {}
