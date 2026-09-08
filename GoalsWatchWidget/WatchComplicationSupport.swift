//
//  WatchComplicationSupport.swift
//  GoalsWatchWidget
//

import WidgetKit
import SwiftUI
import SwiftData

/// Today's tally, plus the next thing not yet done — everything the complications draw. A plain
/// value; the timeline outlives the fetch.
struct TodayComplicationEntry: TimelineEntry {
    let date: Date
    var isSignedIn = true
    var done = 0
    var total = 0
    var bestStreak = 0
    var nextTitle: String?
    var nextEmoji: String?
    var nextColorHex: String = ColorPalette.defaultHex
    var nextFraction: Double = 0
    /// Set only when the next item is a habit — that's the one a tap can safely check off.
    var nextHabitID: UUID?

    var fraction: Double { total > 0 ? min(Double(done) / Double(total), 1) : 0 }
    var allDone: Bool { total > 0 && done >= total }
}

struct TodayComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayComplicationEntry {
        TodayComplicationEntry(date: .now, done: 3, total: 7, bestStreak: 12,
                               nextTitle: "Meditace", nextEmoji: "🧘", nextFraction: 0)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (TodayComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.currentEntry())
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayComplicationEntry>) -> Void) {
        let entry = Self.currentEntry()
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    @MainActor
    static func currentEntry() -> TodayComplicationEntry {
        guard let userId = LocalProfile.currentUserId else {
            return TodayComplicationEntry(date: .now, isSignedIn: false)
        }
        let summary = TodaySchedule.summary(userId: userId, context: SharedStore.container.mainContext)
        let next = summary.nextUp
        return TodayComplicationEntry(
            date: .now,
            done: summary.done,
            total: summary.total,
            bestStreak: summary.bestStreak,
            nextTitle: next?.title,
            nextEmoji: next?.emoji,
            nextColorHex: next?.colorHex ?? ColorPalette.defaultHex,
            nextFraction: next?.fraction ?? 0,
            nextHabitID: (next?.isHabit == true) ? next?.id : nil
        )
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular: true
        default: false
        }
    }
}
