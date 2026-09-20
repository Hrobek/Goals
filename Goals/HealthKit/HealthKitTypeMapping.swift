//
//  HealthKitTypeMapping.swift
//  Goals
//

import HealthKit

/// Maps the app's own `HealthKitMetric` (which has to stay HealthKit-free - see its doc comment)
/// onto real `HKObjectType`s and the unit each is read or written in. Lives in the app target only:
/// HealthKit isn't available to the widget extensions this file's sibling model files also compile
/// into.
enum HealthKitTypeMapping {
    /// Where a metric's samples come from - a plain cumulative/most-recent quantity or category
    /// type, or a specific workout activity's distance (for "running only" vs "walking only",
    /// which Health doesn't split into their own quantity types the way it does cycling/swimming).
    enum Source {
        case quantity(HKQuantityType, HKUnit)
        case category(HKCategoryType)
        case workoutDistance(HKWorkoutActivityType, HKUnit)
    }

    static func source(for metric: HealthKitMetric) -> Source {
        switch metric {
        case .steps:
            .quantity(HKQuantityType.quantityType(forIdentifier: .stepCount)!, .count())
        case .distanceWalkingRunning:
            .quantity(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!, .meter())
        case .distanceRunningOnly:
            .workoutDistance(.running, .meter())
        case .distanceWalkingOnly:
            .workoutDistance(.walking, .meter())
        case .distanceCycling:
            .quantity(HKQuantityType.quantityType(forIdentifier: .distanceCycling)!, .meter())
        case .distanceSwimming:
            .quantity(HKQuantityType.quantityType(forIdentifier: .distanceSwimming)!, .meter())
        case .distanceWheelchair:
            .quantity(HKQuantityType.quantityType(forIdentifier: .distanceWheelchair)!, .meter())
        case .activeEnergy:
            .quantity(HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!, .kilocalorie())
        case .exerciseMinutes:
            .quantity(HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!, .minute())
        case .mindfulMinutes:
            .category(HKCategoryType.categoryType(forIdentifier: .mindfulSession)!)
        case .dietaryWater:
            .quantity(HKQuantityType.quantityType(forIdentifier: .dietaryWater)!, .literUnit(with: .milli))
        case .bodyMass:
            .quantity(HKQuantityType.quantityType(forIdentifier: .bodyMass)!, .gramUnit(with: .kilo))
        }
    }

    /// The `HKObjectType` to request read/observe access for - `nil` for the two workout-filtered
    /// metrics, which authorize (and observe) through `HKWorkoutType` instead.
    static func objectType(for metric: HealthKitMetric) -> HKObjectType {
        switch source(for: metric) {
        case .quantity(let type, _): type
        case .category(let type): type
        case .workoutDistance: HKObjectType.workoutType()
        }
    }

    /// How many `HKUnit`s (as reported by `source(for:)`) make up one of the habit/goal's own
    /// units - km -> meters, glasses -> ml, lb -> kg, hours -> minutes. 1 for units that already
    /// match Health's unit one-to-one (steps, ml, kg, minutes, kcal).
    private static func healthUnitsPerAppUnit(for metric: HealthKitMetric, unit: GoalUnit) -> Double {
        switch (metric, unit) {
        case (.distanceWalkingRunning, .km), (.distanceRunningOnly, .km), (.distanceWalkingOnly, .km),
             (.distanceCycling, .km), (.distanceSwimming, .km), (.distanceWheelchair, .km):
            1000   // HKUnit is meters
        case (.distanceWalkingRunning, .miles), (.distanceRunningOnly, .miles), (.distanceWalkingOnly, .miles),
             (.distanceCycling, .miles), (.distanceSwimming, .miles), (.distanceWheelchair, .miles):
            1609.344
        case (.dietaryWater, .liters):
            1000   // HKUnit is milliliters
        case (.dietaryWater, .glasses):
            250    // one "glass" ~= 250 ml, matches the app's own glasses unit
        case (.bodyMass, .pounds):
            0.45359237   // HKUnit is kilograms
        case (.exerciseMinutes, .hours), (.mindfulMinutes, .hours):
            60     // HKUnit is minutes
        default:
            1
        }
    }

    /// Converts a value in the habit/goal's own unit into the `HKUnit` `source(for:)` reports.
    static func toHealthKitValue(_ appValue: Double, metric: HealthKitMetric, unitKey: String) -> Double {
        guard let unit = GoalUnit(rawValue: unitKey) else { return appValue }
        return appValue * healthUnitsPerAppUnit(for: metric, unit: unit)
    }

    /// Converts a value in `source(for:)`'s `HKUnit` back into the habit/goal's own unit.
    static func fromHealthKitValue(_ hkValue: Double, metric: HealthKitMetric, unitKey: String) -> Double {
        guard let unit = GoalUnit(rawValue: unitKey) else { return hkValue }
        return hkValue / healthUnitsPerAppUnit(for: metric, unit: unit)
    }
}
