//
//  HealthLinkSection.swift
//  Goals
//

import SwiftUI

/// The "link this to Apple Health" card, shared by the habit and goal editors. Hidden entirely when
/// the current unit has nothing Health can offer (pages, currency, custom units…). Pro-gated, same
/// as the other cross-cutting features.
struct HealthLinkSection: View {
    let unitKey: String
    @Binding var metric: HealthKitMetric?
    @Binding var direction: HealthKitDirection?
    let isProUnlocked: Bool
    /// A goal's `currentValue` is a running total, not a per-day amount - writing a `.sum` metric
    /// (water) would dump that whole total into Health as one moment, so the goal editor passes
    /// `true` here to only ever offer a `.mostRecent` metric (weight) for the write direction. A
    /// habit's day-bucketed `amount` doesn't have this problem, so it stays `false`.
    var restrictWriteToMostRecent = false

    private var unit: GoalUnit? { GoalUnit(rawValue: unitKey) }

    private func metrics(for direction: HealthKitDirection) -> [HealthKitMetric] {
        guard let unit else { return [] }
        let metrics = unit.healthKitMetrics(for: direction)
        guard direction == .write, restrictWriteToMostRecent else { return metrics }
        return metrics.filter { $0.aggregation == .mostRecent }
    }

    private var availableDirections: [HealthKitDirection] {
        HealthKitDirection.allCases.filter { !metrics(for: $0).isEmpty }
    }

    private var isLinked: Bool { metric != nil && direction != nil }

    private var linkedToggle: Binding<Bool> {
        Binding(
            get: { isLinked },
            set: { newValue in
                guard newValue else {
                    direction = nil
                    metric = nil
                    return
                }
                let firstDirection = availableDirections.first ?? .read
                direction = firstDirection
                metric = metrics(for: firstDirection).first
            }
        )
    }

    private var directionBinding: Binding<HealthKitDirection> {
        Binding(
            get: { direction ?? availableDirections.first ?? .read },
            set: { newDirection in
                direction = newDirection
                let available = metrics(for: newDirection)
                if !available.contains(where: { $0 == metric }) {
                    metric = available.first
                }
            }
        )
    }

    private func metricBinding(for metrics: [HealthKitMetric]) -> Binding<HealthKitMetric> {
        Binding(
            get: { metric ?? metrics[0] },
            set: { metric = $0 }
        )
    }

    var body: some View {
        if !availableDirections.isEmpty {
            LabeledSection("health.link.title") {
                if !isProUnlocked {
                    ProLockedCard(title: "health.link.title", message: "health.link.locked")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        CardGroup {
                            SwitchRow(label: "health.link.enable", icon: "heart.fill", isOn: linkedToggle.animation())
                            if isLinked {
                                if availableDirections.count > 1 {
                                    RowDivider()
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("health.link.direction")
                                            .font(Theme.Typo.footnote)
                                            .foregroundStyle(Theme.textMuted)
                                        SegmentStrip(options: availableDirections, selection: directionBinding, title: \.localizedName)
                                    }
                                    .padding(.vertical, 9)
                                }
                                let currentMetrics = metrics(for: directionBinding.wrappedValue)
                                if currentMetrics.count > 1 {
                                    RowDivider()
                                    MenuRow(label: "health.link.metric", options: currentMetrics, selection: metricBinding(for: currentMetrics)) { $0.localizedName }
                                } else if let only = currentMetrics.first {
                                    RowDivider()
                                    ValueRow("health.link.metric", value: only.localizedName)
                                }
                            }
                        }
                        Text(isLinked
                             ? (direction == .read ? "health.link.hint.read" : "health.link.hint.write")
                             : "health.link.hint.off")
                            .font(Theme.Typo.footnote)
                            .foregroundStyle(Theme.textGhost)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }
}
