//
//  TrendsSection.swift
//  Goals
//

import SwiftUI
import Charts

/// Pro-only: activity across *all* tracked goals, not one at a time — a weekly trend chart and a
/// month-over-month comparison. The per-goal streak grids above stay free; this is the "step back
/// and see the whole picture" view.
struct TrendsSection: View {
    let checkIns: [CheckIn]

    private var weeklyPoints: [WeeklyActivityPoint] {
        WeeklyActivityPoint.lastWeeks(12, from: checkIns)
    }

    var body: some View {
        Section {
            MonthComparisonRow(checkIns: checkIns)

            Chart(weeklyPoints) { point in
                BarMark(
                    x: .value(weekLabel, point.weekStart, unit: .weekOfYear),
                    y: .value(checkInsLabel, point.count)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3))
            }
            .frame(height: 140)
            .padding(.vertical, 4)
        } header: {
            Text("stats.trends.title")
        } footer: {
            Text("stats.trends.footer")
        }
    }

    private var weekLabel: String {
        String(localized: "stats.trends.week", defaultValue: "Week", bundle: AppLanguage.currentBundle)
    }

    private var checkInsLabel: String {
        String(localized: "stats.trends.checkIns", defaultValue: "Check-ins", bundle: AppLanguage.currentBundle)
    }
}

struct WeeklyActivityPoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let count: Int

    /// The last `n` calendar weeks ending with the current one, zero-filled so the chart always
    /// shows a full run of bars instead of gaps where nothing happened.
    static func lastWeeks(_ n: Int, from checkIns: [CheckIn], calendar: Calendar = .current, now: Date = .now) -> [WeeklyActivityPoint] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        var counts: [Date: Int] = [:]
        for checkIn in checkIns {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: checkIn.date)?.start else { continue }
            counts[start, default: 0] += 1
        }

        return (0..<n).reversed().compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek.start) else { return nil }
            return WeeklyActivityPoint(weekStart: weekStart, count: counts[weekStart] ?? 0)
        }
    }
}

private struct MonthComparisonRow: View {
    let checkIns: [CheckIn]

    private let calendar = Calendar.current

    private var thisMonthCount: Int {
        guard let interval = calendar.dateInterval(of: .month, for: .now) else { return 0 }
        return checkIns.filter { interval.contains($0.date) }.count
    }

    private var lastMonthCount: Int {
        guard let thisMonth = calendar.dateInterval(of: .month, for: .now),
              let previousAnchor = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
              let interval = calendar.dateInterval(of: .month, for: previousAnchor) else { return 0 }
        return checkIns.filter { interval.contains($0.date) }.count
    }

    private var delta: Int { thisMonthCount - lastMonthCount }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("stats.trends.thisMonth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(thisMonthCount)")
                    .font(.title2.bold().monospacedDigit())
            }

            Spacer()

            if lastMonthCount > 0 || thisMonthCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(deltaText)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(delta >= 0 ? Color.green : Color.red)
            }
        }
    }

    private var deltaText: String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }
}

#Preview {
    Form {
        TrendsSection(checkIns: [])
    }
}
