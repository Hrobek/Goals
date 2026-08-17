//
//  ProgressChartWidget.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI
import SwiftData
import Charts

// MARK: - Entry

struct ChartSnapshot {
    let id: UUID
    let title: String
    let emoji: String?
    let colorHex: String
    /// "40/100 km" — the same summary the goals widget puts on its rows.
    let detail: String
    let periodLabel: String
    let target: Double
    let points: [ChartPoint]
    let domain: ClosedRange<Date>
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct ChartEntry: TimelineEntry {
    let date: Date
    let snapshot: ChartSnapshot?
    var isProUnlocked = true
    var page = 0
    var pageCount = 1
    var scope = WidgetKind.progressChart
}

// MARK: - Provider

struct ChartProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChartEntry {
        ChartEntry(date: .now, snapshot: Self.sample)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (ChartEntry) -> Void) {
        completion(context.isPreview ? ChartEntry(date: .now, snapshot: Self.sample) : Self.entry(for: context.family))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChartEntry>) -> Void) {
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [Self.entry(for: context.family)], policy: .after(midnight)))
    }

    @MainActor
    private static func entry(for family: WidgetFamily) -> ChartEntry {
        let scope = "\(WidgetKind.progressChart).\(family.pageScopeName)"
        guard ProEntitlement.isUnlocked else {
            return ChartEntry(date: .now, snapshot: nil, isProUnlocked: false, scope: scope)
        }

        // Milestone goals are left out rather than shown empty: there's no number to trend, so
        // they'd only ever be a page of "not enough data".
        let paged = WidgetGoals.page(
            WidgetGoals.fetch { $0.trackingMode == .value },
            perPage: 1,
            scope: scope
        ) {
            snapshot(for: $0)
        }
        return ChartEntry(
            date: .now,
            snapshot: paged.items.first,
            page: paged.page,
            pageCount: paged.count,
            scope: scope
        )
    }

    @MainActor
    private static func snapshot(for goal: Goal, calendar: Calendar = .current) -> ChartSnapshot? {
        guard let interval = WidgetPeriod.month.interval(calendar: calendar) else { return nil }

        var all = [ChartPoint(date: goal.createdAt, value: goal.startValue)]
        all += goal.checkIns
            .compactMap { checkIn in checkIn.valueSnapshot.map { ChartPoint(date: checkIn.date, value: $0) } }
            .sorted { $0.date < $1.date }

        // The last value from before the month, pinned to its first day, so a quiet start still
        // draws the line at the right height instead of leaving the widget blank.
        var points = all.filter { interval.contains($0.date) }
        if let anchor = all.last(where: { $0.date < interval.start }) {
            points.insert(ChartPoint(date: interval.start, value: anchor.value), at: 0)
        }

        return ChartSnapshot(
            id: goal.id,
            title: goal.title,
            emoji: goal.emoji,
            colorHex: goal.colorHex,
            detail: "\(formatted(goal.currentValue))/\(goal.valueWithUnit(goal.targetValue, formattedValue: formatted(goal.targetValue)))",
            periodLabel: WidgetPeriod.month.label(for: interval, calendar: calendar, locale: AppLanguage.current.locale),
            target: goal.targetValue,
            points: points,
            domain: interval.start...interval.end
        )
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static var sample: ChartSnapshot {
        let calendar = Calendar.current
        let interval = WidgetPeriod.month.interval(calendar: calendar) ?? DateInterval(start: .now, duration: 86_400 * 30)
        let points = (0..<5).compactMap { step -> ChartPoint? in
            guard let date = calendar.date(byAdding: .day, value: step * 5, to: interval.start) else { return nil }
            return ChartPoint(date: date, value: Double(step) * 12)
        }
        return ChartSnapshot(
            id: UUID(),
            title: "Uběhnout 100 km",
            emoji: "🏃",
            colorHex: ColorPalette.defaultHex,
            detail: "48/100 km",
            periodLabel: WidgetPeriod.month.label(for: interval, calendar: calendar, locale: AppLanguage.current.locale),
            target: 100,
            points: points,
            domain: interval.start...interval.end
        )
    }
}

// MARK: - Views

struct ChartWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ChartEntry

    var body: some View {
        if !entry.isProUnlocked {
            ProLockedWidgetView(title: "widget.chart.displayName", systemImage: "chart.line.uptrend.xyaxis")
        } else if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                WidgetGoalHeader(
                    id: snapshot.id,
                    title: snapshot.title,
                    emoji: snapshot.emoji,
                    detail: snapshot.detail
                )
                if snapshot.points.count >= 2 {
                    chart(for: snapshot)
                } else {
                    Text("goalDetail.chart.empty")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Side by side rather than stacked: the chart is the point of this widget, and a
                // second full-width row underneath it would come out of the plot's height.
                HStack(spacing: 6) {
                    Text(snapshot.periodLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    WidgetPager(
                        kind: WidgetKind.progressChart,
                        scope: entry.scope,
                        page: entry.page,
                        pageCount: entry.pageCount,
                        compact: true
                    )
                    .frame(width: 96)
                }
            }
        } else {
            WidgetMessageView(message: "widget.empty.noValueGoals", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    /// Both axes are labelled, at 8pt and only a few marks each: a bare line says the goal is
    /// going up, but not from what to what or over which days, which is most of what a progress
    /// chart is for. The dashed rule is the target, so the gap left to close is visible too.
    private func chart(for snapshot: ChartSnapshot) -> some View {
        let locale = AppLanguage.current.locale
        return Chart {
            ForEach(snapshot.points) { point in
                LineMark(x: .value(dateLabel, point.date), y: .value(valueLabel, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color(hex: snapshot.colorHex))
            }
            RuleMark(y: .value(targetLabel, snapshot.target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary)
        }
        .chartXScale(domain: snapshot.domain)
        // `automatic` rather than a fixed stride: a stride from the 1st lands its last label on the
        // last day of the month, right on the plot's edge, where half of it gets clipped away.
        // Colours are spelled out as `Color.secondary` — the hierarchical `.secondary` picks up the
        // widget's accent tint in Charts and comes out blue.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: family == .systemLarge ? 5 : 3)) { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(locale))
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: family == .systemLarge ? 4 : 3)) { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartPlotStyle { plot in
            plot.frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Widget

struct ProgressChartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.progressChart, provider: ChartProvider()) { entry in
            ChartWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .environment(\.locale, AppLanguage.current.locale)
        }
        .configurationDisplayName("widget.chart.displayName")
        .description("widget.chart.description")
        // No small size: a line chart shrunk to a square with a title on top is a squiggle, and
        // the goals widget already covers "one number at a glance".
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
