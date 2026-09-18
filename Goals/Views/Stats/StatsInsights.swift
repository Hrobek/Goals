//
//  StatsInsights.swift
//  Goals
//
//  The Pro-only "step back and see the whole picture" cards on the Stats screen: a year-long
//  activity heatmap, the all-time records, and the weekday pattern. `TrendsSection` (the
//  week-over-week chart) rounds out the same area.
//

import SwiftUI
import Charts

/// Aggregate GitHub-style heatmap across every tracked goal and habit, from Jan 1 through today.
/// Unlike `ScheduleActivityView`'s per-item grid, a day here isn't "scheduled" against one
/// schedule - it's just how much happened that day, so the fill ramps from empty straight through
/// busier instead of marking scheduled-but-missed days apart.
struct YearInPixelsCard: View {
    let doneDates: [Date]

    private let calendar = Calendar.current

    private var counts: [Date: Int] {
        var result: [Date: Int] = [:]
        for date in doneDates {
            result[calendar.startOfDay(for: date), default: 0] += 1
        }
        return result
    }

    private var days: [Date] {
        guard let yearStart = calendar.dateInterval(of: .year, for: .now)?.start else { return [] }
        let today = calendar.startOfDay(for: .now)
        let count = (calendar.dateComponents([.day], from: yearStart, to: today).day ?? 0) + 1
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: yearStart) }
    }

    private var activeDayCount: Int {
        days.count { (counts[$0] ?? 0) > 0 }
    }

    private var leadingBlanks: Int {
        guard let firstDay = days.first else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Distinct type from `Date` so the grid's leading blanks never collide with a real day under
    /// `id: \.self` in the same `LazyHGrid`.
    private struct BlankDay: Hashable { let index: Int }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("stats.yearInPixels.title")
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)

            grid

            Text("stats.yearInPixels.summary \(activeDayCount) \(days.count)")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .cardSurface(padding: 16)
    }

    private var grid: some View {
        let cellSize: CGFloat = 11
        let spacing: CGFloat = 3
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 7), spacing: spacing) {
                ForEach((0..<leadingBlanks).map(BlankDay.init), id: \.self) { _ in
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
                ForEach(days, id: \.self) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fill(for: day))
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .frame(height: cellSize * 7 + spacing * 6)
        }
        // The year reads left-to-right up to today, so anchor the scroll on today's edge.
        .defaultScrollAnchor(.trailing)
        // 250-some labelled squares is no way to learn how a year went; answer the actual
        // question - how much happened - in one element instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.yearInPixels.summary \(activeDayCount) \(days.count)"))
    }

    private func fill(for day: Date) -> Color {
        switch counts[day] ?? 0 {
        case 0: Theme.cellBlocked
        case 1: Theme.accent.opacity(0.35)
        case 2: Theme.accent.opacity(0.6)
        case 3: Theme.accent.opacity(0.8)
        default: Theme.accent
        }
    }
}

/// The all-time bests: not what's running right now, but the highest bar ever cleared. A finished
/// goal's frozen streak or a slump six months ago can still hold a record the current lists never
/// show.
struct PersonalRecordsCard: View {
    let longestStreak: Int
    let bestWeek: Int
    let totalCheckIns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("stats.records.title")
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)
                .padding(.bottom, 6)

            ValueRow("stats.records.longestStreak", icon: "flame.fill", value: "\(longestStreak)")
            RowDivider()
            ValueRow("stats.records.bestWeek", icon: "trophy.fill", value: "\(bestWeek)")
            RowDivider()
            ValueRow("stats.records.totalCheckIns", icon: "checkmark.seal.fill", value: "\(totalCheckIns)")
        }
        .cardSurface(padding: 16)
    }
}

/// Which day of the week actually gets things done - a small bar per weekday, the busiest one
/// called out below. Built from every check-in and habit entry, not any single goal.
struct WeekdayPatternCard: View {
    let doneDates: [Date]

    private let calendar = Calendar.current

    private var weekdayCounts: [Int: Int] {
        var result: [Int: Int] = [:]
        for date in doneDates {
            result[calendar.component(.weekday, from: date), default: 0] += 1
        }
        return result
    }

    private var weekdayOrder: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var strongestWeekday: Int? {
        weekdayCounts.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("stats.patterns.title")
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)

            Chart {
                ForEach(weekdayOrder, id: \.self) { weekday in
                    BarMark(
                        x: .value(dayLabel, Recurrence.weekdayAbbreviation(weekday)),
                        y: .value(countLabel, weekdayCounts[weekday] ?? 0)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(weekday == strongestWeekday ? Theme.accent : Theme.textGhost)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Theme.textFaint)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 90)

            if let strongestWeekday, (weekdayCounts[strongestWeekday] ?? 0) > 0 {
                Text("stats.patterns.strongest \(Recurrence.weekdayAbbreviation(strongestWeekday))")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .cardSurface(padding: 16)
    }

    private var dayLabel: String {
        String(localized: "stats.patterns.day", defaultValue: "Day", bundle: AppLanguage.currentBundle)
    }

    private var countLabel: String {
        String(localized: "stats.trends.checkIns", defaultValue: "Check-ins", bundle: AppLanguage.currentBundle)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Theme.Space.card) {
            YearInPixelsCard(doneDates: [])
            PersonalRecordsCard(longestStreak: 21, bestWeek: 9, totalCheckIns: 142)
            WeekdayPatternCard(doneDates: [])
        }
        .padding()
    }
    .screenGround()
}
