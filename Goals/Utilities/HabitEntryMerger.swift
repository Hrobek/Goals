//
//  HabitEntryMerger.swift
//  Goals
//

import Foundation
import SwiftData
import os

/// Cleans up days that ended up with two `HabitEntry` rows. `HabitLogger` keeps one per day on a
/// single device, but the phone and the watch can each log the same day before CloudKit has
/// brought the other's row over, and once it does, both rows sync everywhere. Readers already
/// agree on the winner (`HabitEntry.ranksAbove`, the higher amount); this deletes the rest so the
/// store, the export and Health stop carrying the duplicate too.
///
/// Runs only in the app on the phone: a losing row may hold Health samples the phone wrote, and
/// only this target can delete those.
enum HabitEntryMerger {
    private static let log = Logger(subsystem: "com.hrobek.goals", category: "HabitEntryMerger")

    @MainActor
    static func mergeDuplicates(in context: ModelContext, calendar: Calendar = .current) {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        var removed = 0

        for habit in habits {
            let byDay = Dictionary(grouping: habit.entries) { calendar.startOfDay(for: $0.date) }
            for (_, dayEntries) in byDay where dayEntries.count > 1 {
                let ranked = dayEntries.sorted(by: HabitEntry.ranksAbove)
                let winner = ranked[0]
                for loser in ranked.dropFirst() {
                    if !loser.healthKitSampleIDs.isEmpty, let metric = habit.healthKitMetric {
                        HealthKitWriteSync.discardSamples(ids: loser.healthKitSampleIDs, metric: metric)
                        // The day's Health total came from the losing row; have the winner write
                        // its own amount instead on the next catch-up.
                        if winner.healthKitSampleIDs.isEmpty, habit.healthKitDirection == .write {
                            winner.needsHealthKitWriteSync = true
                        }
                    }
                    context.delete(loser)
                    removed += 1
                }
            }
        }

        guard removed > 0 else { return }
        log.info("merged \(removed, privacy: .public) duplicate habit entries")
        do {
            try context.save()
        } catch {
            log.error("save failed: \(error, privacy: .public)")
        }
        NotificationCenter.default.post(name: .checkInDidChange, object: nil)
    }
}
