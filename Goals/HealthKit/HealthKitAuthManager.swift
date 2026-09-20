//
//  HealthKitAuthManager.swift
//  Goals
//

import HealthKit
import SwiftData

/// Requests HealthKit access for exactly the metrics currently linked to a habit or goal - never a
/// blanket "give me everything" request. Read access is requested for `.read`-linked metrics,
/// share (write) access for `.write`-linked ones.
enum HealthKitAuthManager {
    static let healthStore = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// One authorization sheet covering every metric currently linked across a user's habits and
    /// goals - called right after the editor links a new one, so the sheet only ever grows to cover
    /// what's actually in use.
    static func requestAuthorization(for context: ModelContext) async throws {
        guard isAvailable else { return }

        let (readMetrics, writeMetrics) = linkedMetrics(in: context)

        var readTypes: Set<HKObjectType> = []
        for metric in readMetrics {
            readTypes.insert(HealthKitTypeMapping.objectType(for: metric))
        }

        var shareTypes: Set<HKSampleType> = []
        for metric in writeMetrics {
            if let sampleType = HealthKitTypeMapping.objectType(for: metric) as? HKSampleType {
                shareTypes.insert(sampleType)
            }
        }

        guard !readTypes.isEmpty || !shareTypes.isEmpty else { return }
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Every metric currently linked to some habit or goal, split by direction.
    static func linkedMetrics(in context: ModelContext) -> (read: Set<HealthKitMetric>, write: Set<HealthKitMetric>) {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []

        var read: Set<HealthKitMetric> = []
        var write: Set<HealthKitMetric> = []

        for habit in habits where habit.isHealthLinked {
            guard let metric = habit.healthKitMetric else { continue }
            switch habit.healthKitDirection {
            case .read: read.insert(metric)
            case .write: write.insert(metric)
            case nil: break
            }
        }
        for goal in goals where goal.isHealthLinked {
            guard let metric = goal.healthKitMetric else { continue }
            switch goal.healthKitDirection {
            case .read: read.insert(metric)
            case .write: write.insert(metric)
            case nil: break
            }
        }
        return (read, write)
    }
}
