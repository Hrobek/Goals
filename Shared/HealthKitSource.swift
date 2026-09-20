//
//  HealthKitSource.swift
//  Goals
//

import Foundation

/// How a linked metric's value is derived from the underlying Health samples. `.sum` adds every
/// sample in the period together (steps, distance, water); `.mostRecent` takes the latest sample
/// instead of summing them (weight - two weigh-ins in a day aren't 2x the weight).
enum HealthKitAggregation: String, Codable {
    case sum
    case mostRecent
}

/// Which way a habit or goal is linked to Health: `.read` mirrors Health into the app (Health is
/// the source of truth, no manual editing), `.write` mirrors the app into Health (the app is the
/// source of truth, Health just gets a copy). Never both at once for the same habit/goal - see
/// `HealthKitMetric.supportedDirections`.
enum HealthKitDirection: String, Codable, CaseIterable, Identifiable, Hashable {
    case read
    case write

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .read: String(localized: "health.direction.read", bundle: AppLanguage.currentBundle)
        case .write: String(localized: "health.direction.write", bundle: AppLanguage.currentBundle)
        }
    }
}

/// A Health metric a habit or goal can be linked to. Kept free of `import HealthKit` on purpose -
/// this type is used from `Habit`/`Goal`/`HabitLogger`/`ProgressLogger`, which also compile into
/// the widget extensions, and HealthKit isn't available there. The actual `HKObjectType` mapping
/// lives in the app target only, in `HealthKitTypeMapping.swift`.
enum HealthKitMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case steps
    case distanceWalkingRunning
    case distanceRunningOnly
    case distanceWalkingOnly
    case distanceCycling
    case distanceSwimming
    case distanceWheelchair
    case activeEnergy
    case exerciseMinutes
    case mindfulMinutes
    case dietaryWater
    case bodyMass

    var id: String { rawValue }

    var aggregation: HealthKitAggregation {
        switch self {
        case .bodyMass: .mostRecent
        default: .sum
        }
    }

    /// Sensor-derived metrics only ever flow *from* Health - writing fake steps or distance would
    /// pollute the same aggregate Health uses for Watch trends and Fitness rings. User-logged
    /// metrics (what someone drank, meditated or weighed) can flow either way, since Health has no
    /// more claim on the "real" number for those than the app does.
    var supportedDirections: Set<HealthKitDirection> {
        switch self {
        case .steps, .distanceWalkingRunning, .distanceRunningOnly, .distanceWalkingOnly,
             .distanceCycling, .distanceSwimming, .distanceWheelchair, .activeEnergy, .exerciseMinutes:
            [.read]
        case .mindfulMinutes, .dietaryWater, .bodyMass:
            [.read, .write]
        }
    }

    /// The `GoalUnit`s this metric can sensibly feed - the editor only offers a metric when the
    /// habit/goal's own unit is in this list.
    var compatibleUnits: [GoalUnit] {
        switch self {
        case .steps: [.steps]
        case .distanceWalkingRunning, .distanceRunningOnly, .distanceWalkingOnly, .distanceCycling, .distanceSwimming, .distanceWheelchair:
            [.km, .meters, .miles]
        case .activeEnergy: [.kcal]
        case .exerciseMinutes, .mindfulMinutes: [.minutes, .hours]
        case .dietaryWater: [.liters, .milliliters, .glasses]
        case .bodyMass: [.kg, .pounds]
        }
    }

    var localizedName: String {
        switch self {
        case .steps: String(localized: "health.metric.steps", defaultValue: "Steps", bundle: AppLanguage.currentBundle)
        case .distanceWalkingRunning: String(localized: "health.metric.walkingRunning", defaultValue: "Walking + running", bundle: AppLanguage.currentBundle)
        case .distanceRunningOnly: String(localized: "health.metric.runningOnly", defaultValue: "Running only", bundle: AppLanguage.currentBundle)
        case .distanceWalkingOnly: String(localized: "health.metric.walkingOnly", defaultValue: "Walking only", bundle: AppLanguage.currentBundle)
        case .distanceCycling: String(localized: "health.metric.cycling", defaultValue: "Cycling", bundle: AppLanguage.currentBundle)
        case .distanceSwimming: String(localized: "health.metric.swimming", defaultValue: "Swimming", bundle: AppLanguage.currentBundle)
        case .distanceWheelchair: String(localized: "health.metric.wheelchair", defaultValue: "Wheelchair", bundle: AppLanguage.currentBundle)
        case .activeEnergy: String(localized: "health.metric.activeEnergy", defaultValue: "Active energy", bundle: AppLanguage.currentBundle)
        case .exerciseMinutes: String(localized: "health.metric.exerciseMinutes", defaultValue: "Exercise minutes", bundle: AppLanguage.currentBundle)
        case .mindfulMinutes: String(localized: "health.metric.mindfulMinutes", defaultValue: "Mindful minutes", bundle: AppLanguage.currentBundle)
        case .dietaryWater: String(localized: "health.metric.water", defaultValue: "Water", bundle: AppLanguage.currentBundle)
        case .bodyMass: String(localized: "health.metric.bodyMass", defaultValue: "Weight", bundle: AppLanguage.currentBundle)
        }
    }
}

extension GoalUnit {
    /// The Health metrics this unit could be linked to, for the given direction - what the editor's
    /// "Link to Health" picker offers. Empty for a unit Health has nothing to say about (pages,
    /// currency, custom units...).
    func healthKitMetrics(for direction: HealthKitDirection) -> [HealthKitMetric] {
        HealthKitMetric.allCases.filter { $0.compatibleUnits.contains(self) && $0.supportedDirections.contains(direction) }
    }
}
