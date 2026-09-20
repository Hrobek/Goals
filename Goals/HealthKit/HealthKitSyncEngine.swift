//
//  HealthKitSyncEngine.swift
//  Goals
//

import HealthKit
import SwiftData
import os

/// Pulls Health data into `.read`-linked habits and goals. Never touches a `.write`-linked one -
/// see `HealthKitWriteSync` for the other direction.
///
/// Two sync shapes, matching the two models' own shape:
/// - **Habit**: a day is its own bucket (`HabitEntry.amount`), so a day's Health value can just
///   overwrite it - re-running the same day's query always gives the same answer.
/// - **Goal**: `currentValue` is a running total toward `targetValue`, not a daily bucket, so it's
///   recomputed from scratch each time from a single "since start" query rather than accumulated
///   day by day - that stays correct no matter how many times or how often it runs.
enum HealthKitSyncEngine {
    private static let logger = Logger(subsystem: "com.hrobek.goals", category: "HealthKitSync")
    private static var observerQueries: [HKQuery] = []

    // MARK: - Public entry points

    /// Syncs every `.read`-linked habit and goal once. Called on app foreground and whenever an
    /// observer query reports new Health data.
    static func syncAll(context: ModelContext, calendar: Calendar = .current, now: Date = .now) async {
        guard HealthKitAuthManager.isAvailable else { return }

        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for habit in habits where habit.isHealthLinked && habit.healthKitDirection == .read {
            await syncHabit(habit, in: context, calendar: calendar, now: now)
        }

        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        for goal in goals where goal.isHealthLinked && goal.healthKitDirection == .read {
            await syncGoal(goal, in: context, calendar: calendar, now: now)
        }

        HealthSyncStatus.lastSyncDate = now
    }

    /// One habit's today. A quota or avoid habit is never linked in the editor, but a defensive
    /// guard here means an old link left over from a schedule change is simply ignored, not acted on.
    static func syncHabit(_ habit: Habit, in context: ModelContext, calendar: Calendar = .current, now: Date = .now) async {
        guard let metric = habit.healthKitMetric, habit.healthKitDirection == .read,
              !habit.isQuota, !habit.isAvoid else { return }

        let day = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 0)
        guard let hkValue = await value(for: metric, aggregation: metric.aggregation, in: day) else { return }

        let appValue = HealthKitTypeMapping.fromHealthKitValue(hkValue, metric: metric, unitKey: habit.unitKey)
        // `setAmount` is a no-op once the value already matches, so a re-run with unchanged Health
        // data touches nothing - no spurious widget reloads or analytics pings.
        HabitLogger.setAmount(habit, to: appValue, in: context, now: now, calendar: calendar)
    }

    /// One goal, recomputed in full from `startDate` to now rather than accumulated - see the type
    /// doc comment for why. Only touches `currentValue`/today's `CheckIn` when the recomputed total
    /// actually differs, so a habit with no new Health data today doesn't manufacture a streak day.
    static func syncGoal(_ goal: Goal, in context: ModelContext, calendar: Calendar = .current, now: Date = .now) async {
        guard let metric = goal.healthKitMetric, goal.healthKitDirection == .read, goal.trackingMode == .value else { return }

        let range = DateInterval(start: goal.startDate, end: max(goal.startDate, now))
        let newCurrentValue: Double
        switch metric.aggregation {
        case .sum:
            guard let hkTotal = await value(for: metric, aggregation: .sum, in: range) else { return }
            let appTotal = HealthKitTypeMapping.fromHealthKitValue(hkTotal, metric: metric, unitKey: goal.unitKey)
            newCurrentValue = goal.isLowerBetter ? goal.startValue - appTotal : goal.startValue + appTotal
        case .mostRecent:
            guard let hkLatest = await value(for: metric, aggregation: .mostRecent, in: range) else { return }
            newCurrentValue = HealthKitTypeMapping.fromHealthKitValue(hkLatest, metric: metric, unitKey: goal.unitKey)
        }

        guard newCurrentValue != goal.currentValue else { return }
        ProgressLogger.record(value: newCurrentValue, for: goal, in: context, now: now, calendar: calendar)
    }

    /// Fills in a habit's history after it's freshly linked, so the streak and heatmap don't start
    /// from a blank slate. Only ever fills a day that has no entry yet - a day the user already
    /// logged by hand keeps whatever they entered, never silently overwritten.
    static func backfillHabit(_ habit: Habit, in context: ModelContext, calendar: Calendar = .current, now: Date = .now, maxDays: Int = 90) async {
        guard let metric = habit.healthKitMetric, habit.healthKitDirection == .read else { return }

        let today = calendar.startOfDay(for: now)
        let earliestAllowed = calendar.date(byAdding: .day, value: -maxDays, to: today) ?? today
        let start = max(calendar.startOfDay(for: habit.startDate), earliestAllowed)
        guard start < today else { return }

        let dailyValues = await dailySeries(for: metric, from: start, to: today, calendar: calendar)
        for (day, hkValue) in dailyValues {
            guard habit.entry(on: day, calendar: calendar) == nil else { continue }
            let appValue = HealthKitTypeMapping.fromHealthKitValue(hkValue, metric: metric, unitKey: habit.unitKey)
            guard appValue > 0 else { continue }
            HabitLogger.setAmount(habit, to: appValue, in: context, now: day, calendar: calendar)
        }
    }

    // MARK: - Background delivery

    /// Registers one observer per distinct Health type currently linked for reading, so the app
    /// wakes up (or, foregrounded, re-syncs immediately) whenever new matching data lands in
    /// Health - a workout finishing, a manual water log from another app, and so on.
    static func startObserving(context: ModelContext) {
        observerQueries.forEach(HealthKitAuthManager.healthStore.stop)
        observerQueries.removeAll()

        let (readMetrics, _) = HealthKitAuthManager.linkedMetrics(in: context)
        let objectTypes = Set(readMetrics.map(HealthKitTypeMapping.objectType(for:)))

        for objectType in objectTypes {
            guard let sampleType = objectType as? HKSampleType else { continue }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
                defer { completionHandler() }
                guard error == nil else {
                    logger.error("Observer query failed for \(sampleType, privacy: .public): \(String(describing: error))")
                    return
                }
                Task { await syncAll(context: context) }
            }
            HealthKitAuthManager.healthStore.execute(query)
            observerQueries.append(query)

            HealthKitAuthManager.healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
                if !success {
                    logger.error("Background delivery not enabled for \(sampleType, privacy: .public): \(String(describing: error))")
                }
            }
        }
    }

    // MARK: - Queries

    /// One value for `metric` over `interval`, in `source(for:)`'s own `HKUnit` - a cumulative sum
    /// or the most recent sample, whichever `aggregation` asks for. `nil` if Health has nothing to
    /// say (no access, or genuinely no samples).
    private static func value(for metric: HealthKitMetric, aggregation: HealthKitAggregation, in interval: DateInterval) async -> Double? {
        switch HealthKitTypeMapping.source(for: metric) {
        case .quantity(let type, let unit):
            switch aggregation {
            case .sum: return await sumQuantity(type, unit: unit, in: interval)
            case .mostRecent: return await mostRecentQuantity(type, unit: unit, in: interval)
            }
        case .category(let type):
            return await sumCategoryDuration(type, in: interval)
        case .workoutDistance(let activityType, let unit):
            return await sumWorkoutDistance(activityType, unit: unit, in: interval)
        }
    }

    /// Each day's value between `start` (inclusive) and `end` (exclusive), for backfill.
    private static func dailySeries(for metric: HealthKitMetric, from start: Date, to end: Date, calendar: Calendar) async -> [(Date, Double)] {
        var results: [(Date, Double)] = []
        var day = start
        while day < end {
            guard let interval = calendar.dateInterval(of: .day, for: day) else { break }
            if let value = await value(for: metric, aggregation: metric.aggregation, in: interval) {
                results.append((day, value))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    private static func sumQuantity(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                guard error == nil, let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            HealthKitAuthManager.healthStore.execute(query)
        }
    }

    private static func mostRecentQuantity(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                guard error == nil, let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            HealthKitAuthManager.healthStore.execute(query)
        }
    }

    /// Mindful minutes: Health has no cumulative quantity for this, just category samples whose
    /// duration is the minutes themselves - so the "sum" is the total duration of every session
    /// that overlaps the interval.
    private static func sumCategoryDuration(_ type: HKCategoryType, in interval: DateInterval) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil, let samples else {
                    continuation.resume(returning: nil)
                    return
                }
                let totalMinutes = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60 }
                continuation.resume(returning: totalMinutes)
            }
            HealthKitAuthManager.healthStore.execute(query)
        }
    }

    /// Sum of `totalDistance` across every workout of `activityType` overlapping `interval` - the
    /// "running only" / "walking only" split Health's own cumulative distance type doesn't offer.
    private static func sumWorkoutDistance(_ activityType: HKWorkoutActivityType, unit: HKUnit, in interval: DateInterval) async -> Double? {
        await withCheckedContinuation { continuation in
            let datePredicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
            let activityPredicate = HKQuery.predicateForWorkouts(with: activityType)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, activityPredicate])
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil, let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: nil)
                    return
                }
                let total = workouts.reduce(0.0) { $0 + ($1.totalDistance?.doubleValue(for: unit) ?? 0) }
                continuation.resume(returning: total)
            }
            HealthKitAuthManager.healthStore.execute(query)
        }
    }
}
