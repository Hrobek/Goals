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
        VStack(alignment: .leading, spacing: 0) {
            MonthComparisonRow(checkIns: checkIns)

            Chart(weeklyPoints) { point in
                BarMark(
                    x: .value(weekLabel, point.weekStart, unit: .weekOfYear),
                    y: .value(checkInsLabel, point.count)
                )
                .cornerRadius(3)
                // The most recent weeks carry the accent, the older ones fall back to grey — the
                // eye lands on "lately" first, which is the question the chart answers.
                .foregroundStyle(point.isRecent ? Theme.accent : Theme.textGhost)
                // Charts hands VoiceOver raw plot values otherwise ("1.7976931348623157e+308"
                // style dates included); spelling each bar out makes the chart navigable.
                .accessibilityLabel(point.weekStart.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue("\(point.count) \(checkInsLabel)")
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairlineSoft)
                    AxisValueLabel().foregroundStyle(Theme.textFaint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.hairlineSoft)
                    AxisValueLabel().foregroundStyle(Theme.textFaint)
                }
            }
            .frame(height: 130)
            .padding(.top, 16)

            Text("stats.trends.footer")
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .cardSurface(padding: 16)
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
    /// Inside the last quarter of the window — the part the chart paints in the accent.
    var isRecent = false

    /// The last `n` calendar weeks ending with the current one, zero-filled so the chart always
    /// shows a full run of bars instead of gaps where nothing happened.
    static func lastWeeks(_ n: Int, from checkIns: [CheckIn], calendar: Calendar = .current, now: Date = .now) -> [WeeklyActivityPoint] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        var counts: [Date: Int] = [:]
        for checkIn in checkIns {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: checkIn.date)?.start else { continue }
            counts[start, default: 0] += 1
        }

        let recentCutoff = max(1, n / 3)
        return (0..<n).reversed().compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek.start) else { return nil }
            return WeeklyActivityPoint(
                weekStart: weekStart,
                count: counts[weekStart] ?? 0,
                isRecent: offset < recentCutoff
            )
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("stats.trends.thisMonth")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                Text("\(thisMonthCount)")
                    .font(Theme.Typo.statMedium)
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            if lastMonthCount > 0 || thisMonthCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 13))
                    Text(deltaText)
                        .monospacedDigit()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(delta >= 0 ? Theme.accentBright : Theme.textMuted)
            }
        }
    }

    private var deltaText: String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }
}

#Preview {
    TrendsSection(checkIns: [])
        .padding()
        .screenGround()
}
