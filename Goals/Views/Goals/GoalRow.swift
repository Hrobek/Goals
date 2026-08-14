//
//  GoalRow.swift
//  Goals
//

import SwiftUI

/// The goal summary used by both the Today screen and the goals overview.
struct GoalRow: View {
    let goal: Goal
    /// Today's screen marks off what's already been logged; the overview shows the deadline instead.
    var showsTodayState = false

    private var isDoneToday: Bool {
        goal.hasCheckIn(on: .now)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: goal.colorHex).opacity(0.2))
                    .frame(width: 40, height: 40)
                if let emoji = goal.emoji {
                    Text(emoji).font(.title3)
                } else {
                    Image(systemName: "target").foregroundStyle(Color(hex: goal.colorHex))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(goal.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if showsTodayState {
                        Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isDoneToday ? .green : .secondary)
                    } else if goal.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                ProgressView(value: goal.progressFraction)
                    .tint(Color(hex: goal.colorHex))

                HStack {
                    Text(valueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showsTodayState {
                        Text(Recurrence.localizedSummary(for: goal))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(goal.priority.localizedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let deadline = goal.deadline {
                            Spacer()
                            Text(deadline, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var valueText: String {
        switch goal.trackingMode {
        case .value:
            "\(formatted(goal.currentValue))/\(formatted(goal.targetValue)) \(goal.unitDisplayText)"
        case .milestones:
            "\(goal.completedMilestoneCount)/\(goal.milestones.count) "
                + String(localized: "milestone.unit", defaultValue: "milestones", bundle: AppLanguage.currentBundle)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
