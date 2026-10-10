//
//  HealthKitWriteSync.swift
//  Goals
//

import HealthKit
import SwiftData
import os

/// Mirrors a `.write`-linked habit or goal's own logged value into Health. The opposite direction
/// of `HealthKitSyncEngine` - this one never reads Health as a source of truth, only writes to it.
///
/// Rather than tracking per-tap deltas as separate samples, each change deletes whatever this
/// entry/check-in previously wrote and replaces it with one fresh sample holding the day's (or
/// check-in's) current total. Simpler to keep correct than delta bookkeeping, and Health's own
/// aggregate views don't care whether a day's water is one sample or several.
enum HealthKitWriteSync {
    private static let logger = Logger(subsystem: "com.hrobek.goals", category: "HealthKitWriteSync")

    /// Every mirror runs after the previous one has finished, and reads the row's sample ids and
    /// amount when it runs rather than when it was asked for. Two mirrors of the same entry used to
    /// overlap - a catch-up on foreground racing one from a CloudKit import - and each would delete
    /// the same old sample and save its own new one, leaving the day counted twice in Health.
    private static var queue: Task<Void, Never>?

    private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Hooked to `HabitLogger.healthWriteHook` at launch.
    static func mirror(habit: Habit, entry: HabitEntry, delta: Double) {
        guard let metric = habit.healthKitMetric, metric.supportedDirections.contains(.write) else { return }
        entry.needsHealthKitWriteSync = false

        enqueue {
            // The row may have been merged away, or belong to a context that's already gone.
            guard let context = entry.modelContext, !entry.isDeleted else { return }
            await deleteSamples(ids: entry.healthKitSampleIDs, metric: metric)
            entry.healthKitSampleIDs = []
            if entry.amount > 0,
               let newID = await saveSample(metric: metric, appValue: entry.amount, unitKey: habit.unitKey, date: entry.date) {
                entry.healthKitSampleIDs = [newID]
            }
            // Saved here rather than left to autosave: an id that never reaches the store means the
            // next change can't delete this sample, and Health keeps adding up every version of it.
            try? context.save()
        }
    }

    /// Hooked to `ProgressLogger.healthWriteHook` at launch. Only ever fires for a `.mostRecent`
    /// metric (weight, in practice) - a goal's `currentValue` is a running total toward its target,
    /// not a per-day amount, so writing it as a `.sum`-type sample (water, mindful minutes) would
    /// dump the whole running total into Health as if it happened in one moment. Habits don't have
    /// this problem: `HabitEntry.amount` is already a single day's value, exactly what Health wants.
    static func mirror(goal: Goal, checkIn: CheckIn, delta: Double) {
        guard let metric = goal.healthKitMetric, metric.supportedDirections.contains(.write), metric.aggregation == .mostRecent else { return }
        checkIn.needsHealthKitWriteSync = false

        enqueue {
            guard let context = checkIn.modelContext, !checkIn.isDeleted else { return }
            await deleteSamples(ids: checkIn.healthKitSampleIDs, metric: metric)
            checkIn.healthKitSampleIDs = []
            if let newValue = checkIn.valueSnapshot,
               let newID = await saveSample(metric: metric, appValue: newValue, unitKey: goal.unitKey, date: checkIn.date) {
                checkIn.healthKitSampleIDs = [newID]
            }
            try? context.save()
        }
    }

    // MARK: - Repair

    private static let repairKey = "Goals.health.duplicateWriteRepair.v1"

    /// One-time cleanup for build 57, where a widget tap could write a habit's day total to Health
    /// without remembering the sample, so every later tap added another full total on top (a 4 l
    /// water habit showing as 19 l). For each recent day a `.write`-linked habit has entries on,
    /// deletes every sample *this app* wrote of that type that day and writes the day's amount
    /// back once per habit. Samples from other apps or entered by hand aren't touched.
    static func repairDuplicatedWrites(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: repairKey), HealthKitAuthManager.isAvailable else { return }
        // On the same queue as the mirrors, so none of them runs halfway through a day's rewrite.
        enqueue { await runRepair(context: context) }
    }

    private static func runRepair(context: ModelContext, calendar: Calendar = .current) async {
        guard !UserDefaults.standard.bool(forKey: repairKey) else { return }

        let habits = ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).filter {
            $0.healthKitDirection == .write
                && $0.healthKitMetric?.supportedDirections.contains(.write) == true
                && $0.healthKitMetric?.aggregation == .sum
        }
        let windowStart = calendar.date(byAdding: .day, value: -60, to: calendar.startOfDay(for: .now)) ?? .distantPast
        let byMetric = Dictionary(grouping: habits) { $0.healthKitMetric! }

        for (metric, metricHabits) in byMetric {
            // A type the app can't write to has nothing of ours in Health to repair. Skipped rather
            // than retried on every launch - the repair walks weeks of entries and was part of
            // what made the app sluggish right after opening.
            guard let sampleType = sampleType(for: metric),
                  HealthKitAuthManager.healthStore.authorizationStatus(for: sampleType) == .sharingAuthorized else {
                continue
            }
            let entries = metricHabits.flatMap { habit in
                habit.entries.filter { $0.date >= windowStart }.map { (habit, $0) }
            }
            let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.1.date) }

            for (day, dayEntries) in byDay {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    HKQuery.predicateForSamples(withStart: day, end: nextDay, options: .strictEndDate),
                    HKQuery.predicateForObjects(from: HKSource.default())
                ])
                await deleteObjects(of: sampleType, predicate: predicate)

                for (_, habitDay) in Dictionary(grouping: dayEntries, by: { $0.0.id }) {
                    // A day the phone and the watch both logged counts once - the same winner
                    // `HabitEntryMerger` keeps; the other rows just lose their stale ids.
                    let ranked = habitDay.sorted { HabitEntry.ranksAbove($0.1, $1.1) }
                    for (_, loser) in ranked.dropFirst() {
                        loser.healthKitSampleIDs = []
                        loser.needsHealthKitWriteSync = false
                    }
                    let (habit, entry) = ranked[0]
                    entry.healthKitSampleIDs = []
                    entry.needsHealthKitWriteSync = false
                    if entry.amount > 0,
                       let newID = await saveSample(metric: metric, appValue: entry.amount, unitKey: habit.unitKey, date: entry.date) {
                        entry.healthKitSampleIDs = [newID]
                    }
                }
            }
        }

        UserDefaults.standard.set(true, forKey: repairKey)
        do {
            try context.save()
            logger.notice("repaired Health writes for \(habits.count, privacy: .public) habits")
        } catch {
            logger.error("repair save failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Catch-up

    /// Every `.write`-linked entry/check-in flagged by `HabitLogger`/`ProgressLogger` because it
    /// changed outside the app target (widget or watch), where there's no HealthKit access to mirror
    /// it immediately. Called on app foreground so those changes still land in Health, without
    /// needing the user to also tap the habit or goal again from inside the app.
    @MainActor
    static func reconcilePending(context: ModelContext) {
        let pendingEntries = (try? context.fetch(FetchDescriptor<HabitEntry>(
            predicate: #Predicate { $0.needsHealthKitWriteSync }
        ))) ?? []
        for entry in pendingEntries {
            guard let habit = entry.habit, habit.healthKitDirection == .write else {
                entry.needsHealthKitWriteSync = false
                continue
            }
            mirror(habit: habit, entry: entry, delta: 0)
        }

        let pendingCheckIns = (try? context.fetch(FetchDescriptor<CheckIn>(
            predicate: #Predicate { $0.needsHealthKitWriteSync }
        ))) ?? []
        for checkIn in pendingCheckIns {
            guard let goal = checkIn.goal, goal.healthKitDirection == .write else {
                checkIn.needsHealthKitWriteSync = false
                continue
            }
            mirror(goal: goal, checkIn: checkIn, delta: 0)
        }
    }

    /// Deletes samples an entry wrote that no longer stands for anything - a duplicate day row
    /// `HabitEntryMerger` is about to remove.
    static func discardSamples(ids: [String], metric: HealthKitMetric) {
        guard metric.supportedDirections.contains(.write) else { return }
        Task { await deleteSamples(ids: ids, metric: metric) }
    }

    // MARK: - Private

    private static func saveSample(metric: HealthKitMetric, appValue: Double, unitKey: String, date: Date) async -> String? {
        let hkValue = HealthKitTypeMapping.toHealthKitValue(appValue, metric: metric, unitKey: unitKey)
        switch HealthKitTypeMapping.source(for: metric) {
        case .quantity(let type, let unit):
            let quantity = HKQuantity(unit: unit, doubleValue: hkValue)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
            return await save(sample)
        case .category(let type):
            // A mindful session needs a span, not an instant - lay it out ending now.
            let start = date.addingTimeInterval(-hkValue * 60)
            let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue, start: start, end: date)
            return await save(sample)
        case .workoutDistance:
            return nil // read-only source, never a write target
        }
    }

    private static func save(_ sample: HKObject) async -> String? {
        await withCheckedContinuation { continuation in
            HealthKitAuthManager.healthStore.save(sample) { success, error in
                if !success {
                    logger.error("Failed to save Health sample: \(String(describing: error))")
                }
                continuation.resume(returning: success ? sample.uuid.uuidString : nil)
            }
        }
    }

    private static func deleteSamples(ids: [String], metric: HealthKitMetric) async {
        let uuids = ids.compactMap(UUID.init)
        guard !uuids.isEmpty, let sampleType = sampleType(for: metric) else { return }
        await deleteObjects(of: sampleType, predicate: HKQuery.predicateForObjects(with: Set(uuids)))
    }

    private static func sampleType(for metric: HealthKitMetric) -> HKSampleType? {
        switch HealthKitTypeMapping.source(for: metric) {
        case .quantity(let type, _): type
        case .category(let type): type
        case .workoutDistance: nil
        }
    }

    private static func deleteObjects(of sampleType: HKSampleType, predicate: NSPredicate) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            HealthKitAuthManager.healthStore.deleteObjects(of: sampleType, predicate: predicate) { _, _, error in
                if let error {
                    logger.error("Failed to delete Health samples: \(String(describing: error))")
                }
                continuation.resume()
            }
        }
    }
}
