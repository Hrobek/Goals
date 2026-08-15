//
//  GoalProgressChartView.swift
//  Goals
//

import SwiftUI
import Charts

/// The goal's value over time — starting point, then every check-in — plotted as a line, so a
/// downward (or upward) trend is visible at a glance instead of just today's number. Value-tracking
/// goals only; a milestone checklist has nothing numeric to trend.
struct GoalProgressChartView: View {
    let goal: Goal
    let range: StatsRange

    private var calendarComponent: Calendar.Component {
        switch range {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    private var interval: DateInterval? {
        Calendar.current.dateInterval(of: calendarComponent, for: .now)
    }

    private var allPoints: [ProgressPoint] {
        var result = [ProgressPoint(date: goal.createdAt, value: goal.startValue)]
        result += goal.checkIns
            .compactMap { checkIn -> ProgressPoint? in
                guard let value = checkIn.valueSnapshot else { return nil }
                return ProgressPoint(date: checkIn.date, value: value)
            }
            .sorted { $0.date < $1.date }
        return result
    }

    /// Points inside the selected window, plus the last known one from before it — so a quiet
    /// week still starts the line at the right value instead of showing nothing at all. That
    /// carried-forward point is clamped to the window's start, so it always lands inside the
    /// plotted axis domain instead of off its left edge.
    private var points: [ProgressPoint] {
        let all = allPoints
        guard let interval else { return all }

        let inWindow = all.filter { interval.contains($0.date) }
        if let anchor = all.last(where: { $0.date < interval.start }) {
            return [ProgressPoint(date: interval.start, value: anchor.value)] + inWindow
        }
        return inWindow
    }

    /// The full week/month/year, not just the span between the earliest and latest point — so a
    /// month with two check-ins still reads as "that month", axis and all, not a random few days.
    private var xDomain: ClosedRange<Date> {
        if let interval {
            return interval.start...interval.end
        }
        let dates = points.map(\.date)
        let start = dates.min() ?? .now
        let end = dates.max() ?? .now
        return start...max(end, start.addingTimeInterval(1))
    }

    var body: some View {
        if points.count >= 2 {
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value(dateLabel, point.date),
                        y: .value(valueLabel, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color(hex: goal.colorHex))
                    PointMark(
                        x: .value(dateLabel, point.date),
                        y: .value(valueLabel, point.value)
                    )
                    .foregroundStyle(Color(hex: goal.colorHex))
                }
                RuleMark(y: .value(targetLabel, goal.targetValue))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartXScale(domain: xDomain)
            .chartXAxis { axisMarks }
            .frame(height: 160)
            .padding(.vertical, 4)
        } else {
            Text("goalDetail.chart.empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Tick granularity follows the selected range — days of the week, spread-out days of the
    /// month, or months of the year — instead of Charts' default, which picks a format from the
    /// data's actual span and shows clock times for anything less than a day apart.
    @AxisContentBuilder
    private var axisMarks: some AxisContent {
        // Explicit locale, matching how the rest of the app localizes: the in-app language is an
        // override independent of the system locale, and date format styles don't pick that up
        // from the SwiftUI environment on their own.
        let locale = AppLanguage.current.locale
        switch range {
        case .week:
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).locale(locale))
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(locale))
            }
        case .year:
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(locale))
            }
        }
    }

    private var dateLabel: String {
        String(localized: "goalDetail.chart.date", defaultValue: "Date", bundle: AppLanguage.currentBundle)
    }

    private var valueLabel: String {
        String(localized: "goalDetail.chart.value", defaultValue: "Value", bundle: AppLanguage.currentBundle)
    }

    private var targetLabel: String {
        String(localized: "goalDetail.chart.target", defaultValue: "Target", bundle: AppLanguage.currentBundle)
    }
}

private struct ProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

#Preview {
    GoalProgressChartView(
        goal: Goal(title: "Lose weight", targetValue: 84, currentValue: 90, isLowerBetter: true, unitKey: GoalUnit.kg.rawValue),
        range: .month
    )
    .padding()
}
