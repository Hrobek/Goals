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

    /// Hooked to `HabitLogger.healthWriteHook` at launch.
    static func mirror(habit: Habit, entry: HabitEntry, delta: Double) {
        guard let metric = habit.healthKitMetric, metric.supportedDirections.contains(.write) else { return }
        let unitKey = habit.unitKey
        let existingIDs = entry.healthKitSampleIDs
        let newAmount = entry.amount
        let date = entry.date

        Task { @MainActor in
            await deleteSamples(ids: existingIDs, metric: metric)
            entry.healthKitSampleIDs = []
            entry.needsHealthKitWriteSync = false
            guard newAmount > 0 else { return }
            if let newID = await saveSample(metric: metric, appValue: newAmount, unitKey: unitKey, date: date) {
                entry.healthKitSampleIDs = [newID]
            }
        }
    }

    /// Hooked to `ProgressLogger.healthWriteHook` at launch. Only ever fires for a `.mostRecent`
    /// metric (weight, in practice) - a goal's `currentValue` is a running total toward its target,
    /// not a per-day amount, so writing it as a `.sum`-type sample (water, mindful minutes) would
    /// dump the whole running total into Health as if it happened in one moment. Habits don't have
    /// this problem: `HabitEntry.amount` is already a single day's value, exactly what Health wants.
    static func mirror(goal: Goal, checkIn: CheckIn, delta: Double) {
        guard let metric = goal.healthKitMetric, metric.supportedDirections.contains(.write), metric.aggregation == .mostRecent,
              let newValue = checkIn.valueSnapshot else { return }
        let unitKey = goal.unitKey
        let existingIDs = checkIn.healthKitSampleIDs
        let date = checkIn.date

        Task { @MainActor in
            await deleteSamples(ids: existingIDs, metric: metric)
            checkIn.healthKitSampleIDs = []
            checkIn.needsHealthKitWriteSync = false
            if let newID = await saveSample(metric: metric, appValue: newValue, unitKey: unitKey, date: date) {
                checkIn.healthKitSampleIDs = [newID]
            }
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
        guard !ids.isEmpty else { return }
        let uuids = ids.compactMap(UUID.init)
        guard !uuids.isEmpty else { return }

        let objectType: HKObjectType
        switch HealthKitTypeMapping.source(for: metric) {
        case .quantity(let type, _): objectType = type
        case .category(let type): objectType = type
        case .workoutDistance: return
        }
        guard let sampleType = objectType as? HKSampleType else { return }

        let predicate = HKQuery.predicateForObjects(with: Set(uuids))
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
