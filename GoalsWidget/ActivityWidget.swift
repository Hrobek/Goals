//
//  ActivityWidget.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

/// One goal's check-in grid, flattened out of SwiftData: the day states are worked out while the
/// models are still alive, so the timeline only ever carries plain values.
struct ActivitySnapshot: Identifiable {
    let id: UUID
    let title: String
    let emoji: String?
    let colorHex: String
    let periodLabel: String
    let weekdaySymbols: [String]
    let leadingBlanks: Int
    let days: [ActivityDay]
    /// Only for quota schedules ("3× a week"), which don't name days to shade in.
    let quota: (done: Int, target: Int)?
}

struct ActivityDay: Identifiable {
    enum State { case done, scheduled, blocked }

    let id: Date
    let state: State
    let isToday: Bool
}

struct ActivityEntry: TimelineEntry {
    let date: Date
    /// One goal on the medium and large sizes; the small one stacks a few weeks-at-a-glance.
    let snapshots: [ActivitySnapshot]
    var isProUnlocked = true
    var page = 0
    var pageCount = 1
    var scope = WidgetKind.activity
}

// MARK: - Provider

struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        ActivityEntry(date: .now, snapshots: Self.sample(for: context.family))
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        completion(context.isPreview
            ? ActivityEntry(date: .now, snapshots: Self.sample(for: context.family))
            : Self.entry(for: context.family))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        // The grid only moves when a day is checked off or the date changes; both push their own
        // reload, so the timeline just needs to survive until midnight.
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [Self.entry(for: context.family)], policy: .after(midnight)))
    }

    @MainActor
    private static func entry(for family: WidgetFamily) -> ActivityEntry {
        let scope = "\(WidgetKind.activity).\(family.pageScopeName)"
        guard ProEntitlement.isUnlocked else {
            return ActivityEntry(date: .now, snapshots: [], isProUnlocked: false, scope: scope)
        }

        let period = self.period(for: family)
        let paged = WidgetGoals.page(
            WidgetGoals.fetch { _ in true },
            perPage: goalsPerPage(for: family),
            scope: scope
        ) {
            snapshot(for: $0, period: period)
        }
        return ActivityEntry(
            date: .now,
            snapshots: paged.items,
            page: paged.page,
            pageCount: paged.count,
            scope: scope
        )
    }

    /// A week is all the small widget has room for; the bigger ones get the whole month, same as
    /// the goal's own Activity section.
    private static func period(for family: WidgetFamily) -> WidgetPeriod {
        family == .systemSmall ? .week : .month
    }

    /// A week strip is one row tall, so the small widget stacks three of them rather than leaving
    /// two-thirds of itself empty for a single goal. A month grid fills a widget on its own.
    private static func goalsPerPage(for family: WidgetFamily) -> Int {
        family == .systemSmall ? 3 : 1
    }

    @MainActor
    private static func snapshot(for goal: Goal, period: WidgetPeriod, calendar: Calendar = .current) -> ActivitySnapshot? {
        guard let interval = period.interval(calendar: calendar) else { return nil }

        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        let checkInDays = Set(goal.checkIns.map { calendar.startOfDay(for: $0.date) })
        let days = (0..<dayCount).compactMap { offset -> ActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let state: ActivityDay.State = if checkInDays.contains(calendar.startOfDay(for: day)) {
                .done
            } else if Recurrence.isDayScheduled(day, for: goal, calendar: calendar) {
                .scheduled
            } else {
                .blocked
            }
            return ActivityDay(id: day, state: state, isToday: calendar.isDateInToday(day))
        }

        let quotaApplies = (goal.recurrenceType == .timesPerWeek && period == .week)
            || (goal.recurrenceType == .timesPerMonth && period == .month)

        return ActivitySnapshot(
            id: goal.id,
            title: goal.title,
            emoji: goal.emoji,
            colorHex: goal.colorHex,
            periodLabel: period.label(for: interval, calendar: calendar, locale: AppLanguage.current.locale),
            weekdaySymbols: (0..<7).map { Recurrence.weekdayAbbreviation((calendar.firstWeekday - 1 + $0) % 7 + 1) },
            leadingBlanks: leadingBlanks(before: days.first?.id, calendar: calendar),
            days: days,
            quota: quotaApplies ? (goal.checkIns.filter { interval.contains($0.date) }.count, goal.recurrenceCount) : nil
        )
    }

    private static func leadingBlanks(before firstDay: Date?, calendar: Calendar) -> Int {
        guard let firstDay else { return 0 }
        return (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
    }

    private static func sample(for family: WidgetFamily) -> [ActivitySnapshot] {
        let calendar = Calendar.current
        let period = period(for: family)
        let interval = period.interval(calendar: calendar) ?? DateInterval(start: .now, duration: 86_400 * 30)
        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
        let titles = [("Uběhnout 100 km", "🏃"), ("Číst každý den", "📚"), ("Meditace", "🧘")]

        return titles.prefix(goalsPerPage(for: family)).enumerated().map { index, goal in
            let days = (0..<dayCount).compactMap { offset -> ActivityDay? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
                return ActivityDay(
                    id: day,
                    state: (offset + index) % 3 == 0 ? .done : .scheduled,
                    isToday: calendar.isDateInToday(day)
                )
            }
            return ActivitySnapshot(
                id: UUID(),
                title: goal.0,
                emoji: goal.1,
                colorHex: ColorPalette.defaultHex,
                periodLabel: period.label(for: interval, calendar: calendar, locale: AppLanguage.current.locale),
                weekdaySymbols: (0..<7).map { Recurrence.weekdayAbbreviation((calendar.firstWeekday - 1 + $0) % 7 + 1) },
                leadingBlanks: leadingBlanks(before: days.first?.id, calendar: calendar),
                days: days,
                quota: nil
            )
        }
    }
}

// MARK: - Views

struct ActivityWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ActivityEntry

    private var isCompact: Bool { family == .systemSmall }

    var body: some View {
        if !entry.isProUnlocked {
            ProLockedWidgetView(title: "widget.activity.displayName", systemImage: "square.grid.3x3.fill")
        } else if entry.snapshots.isEmpty {
            WidgetMessageView(message: "widget.empty.noGoals")
        } else if isCompact {
            compactBody
        } else {
            fullBody
        }
    }

    /// Small: this week for up to three goals, one strip each, under a shared row of weekday
    /// initials — a single goal's week left most of the widget blank, and bare squares with
    /// nothing labelling them don't say what a column is.
    private var compactBody: some View {
        GeometryReader { geometry in
            let side = max(6, (geometry.size.width - spacing * 6) / 7)
            VStack(alignment: .leading, spacing: 4) {
                weekdayHeader(symbols: entry.snapshots[0].weekdaySymbols, side: side)
                ForEach(entry.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 2) {
                        Link(destination: GoalLink.url(for: snapshot.id)) {
                            HStack(spacing: 3) {
                                GoalIdentity(emoji: snapshot.emoji, size: 14)
                                Text(snapshot.title).lineLimit(1)
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .contentShape(.rect)
                        }
                        weekStrip(snapshot, side: side)
                    }
                }
                Spacer(minLength: 0)
                WidgetPager(
                    kind: WidgetKind.activity,
                    scope: entry.scope,
                    page: entry.page,
                    pageCount: entry.pageCount,
                    compact: true
                )
            }
        }
    }

    private var fullBody: some View {
        let snapshot = entry.snapshots[0]
        return VStack(alignment: .leading, spacing: 6) {
            WidgetGoalHeader(
                id: snapshot.id,
                title: snapshot.title,
                emoji: snapshot.emoji,
                detail: snapshot.periodLabel
            )
            ActivityGridView(snapshot: snapshot)
            if let quota = snapshot.quota {
                Text("stats.quota \(quota.done) \(quota.target)")
                    .font(.system(size: 10))
                    .foregroundStyle(quota.done >= quota.target ? Theme.accentBright : Theme.textFaint)
            }
            WidgetPager(
                kind: WidgetKind.activity,
                scope: entry.scope,
                page: entry.page,
                pageCount: entry.pageCount
            )
        }
    }

    private var spacing: CGFloat { 2 }

    private func weekdayHeader(symbols: [String], side: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 7))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: side)
            }
        }
    }

    private func weekStrip(_ snapshot: ActivitySnapshot, side: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(snapshot.days) { day in
                RoundedRectangle(cornerRadius: max(1, side / 5))
                    .fill(fill(for: day.state))
                    .frame(width: side, height: side)
                    .overlay {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: max(1, side / 5))
                                .stroke(Theme.text, lineWidth: 1)
                        }
                    }
            }
        }
    }

    private func fill(for state: ActivityDay.State) -> Color {
        switch state {
        case .done: Theme.accent
        case .scheduled: Theme.cellScheduled
        case .blocked: Theme.cellBlocked
        }
    }
}

/// The grid sizes itself to whatever space is left rather than to its width: seven columns of
/// square cells across a medium widget would need six rows taller than the widget itself.
private struct ActivityGridView: View {
    let snapshot: ActivitySnapshot

    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let rows = max(1, Int(ceil(Double(snapshot.leadingBlanks + snapshot.days.count) / 7)))
            let headerHeight: CGFloat = 11
            let widthFit = (geometry.size.width - spacing * 6) / 7
            let heightFit = (geometry.size.height - headerHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            // A month grid is six rows deep, so on the wider sizes height runs out long before
            // width does. Rather than leave squares stranded in the middle of a lot of empty
            // widget, the cells are allowed to stretch — but only to 1.6×, past which they stop
            // reading as a calendar and start reading as bars.
            let side = max(3, min(widthFit, heightFit))
            let cellWidth = min(widthFit, side * 1.6)

            VStack(spacing: 1) {
                HStack(spacing: spacing) {
                    ForEach(Array(snapshot.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: cellWidth)
                    }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: 7),
                    spacing: spacing
                ) {
                    // Blanks are keyed by Int and days by Date, so the two ForEachs can't collide
                    // on an id the way same-typed siblings in one grid would.
                    ForEach(0..<snapshot.leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(width: cellWidth, height: side)
                    }
                    ForEach(snapshot.days) { day in
                        cell(for: day, width: cellWidth, height: side)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func cell(for day: ActivityDay, width: CGFloat, height: CGFloat) -> some View {
        let radius = max(1, height / 5)
        return RoundedRectangle(cornerRadius: radius)
            .fill(fill(for: day.state))
            .frame(width: width, height: height)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Theme.text, lineWidth: 1)
                }
            }
    }

    private func fill(for state: ActivityDay.State) -> Color {
        switch state {
        case .done: Theme.accent
        case .scheduled: Theme.cellScheduled
        case .blocked: Theme.cellBlocked
        }
    }
}

// MARK: - Widget

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.activity, provider: ActivityProvider()) { entry in
            ActivityWidgetEntryView(entry: entry)
                .containerBackground(Theme.ground, for: .widget)
                .environment(\.locale, AppLanguage.current.locale)
        }
        .configurationDisplayName("widget.activity.displayName")
        .description("widget.activity.description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
