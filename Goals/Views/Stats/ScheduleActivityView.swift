//
//  ScheduleActivityView.swift
//  Goals
//

import SwiftUI

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .week: String(localized: "stats.range.week", defaultValue: "Week", bundle: AppLanguage.currentBundle)
        case .month: String(localized: "stats.range.month", defaultValue: "Month", bundle: AppLanguage.currentBundle)
        case .year: String(localized: "stats.range.year", defaultValue: "Year", bundle: AppLanguage.currentBundle)
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// The Nth period before/after the one `now` falls in — offset 0 is the current one, matching
    /// how `PeriodNavigator` pages back and forth.
    func interval(offset: Int, calendar: Calendar = .current, now: Date = .now) -> DateInterval? {
        guard let current = calendar.dateInterval(of: calendarComponent, for: now) else { return nil }
        guard offset != 0 else { return current }
        guard let anchor = calendar.date(byAdding: calendarComponent, value: offset, to: current.start) else { return nil }
        return calendar.dateInterval(of: calendarComponent, for: anchor)
    }

    /// A human-readable name for the interval — "11 Aug – 17 Aug 2026", "August 2026", "2026".
    func label(for interval: DateInterval, calendar: Calendar = .current, locale: Locale) -> String {
        switch self {
        case .week:
            let lastDay = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            let start = interval.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            let end = lastDay.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
            return "\(start) – \(end)"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year().locale(locale))
        case .year:
            return interval.start.formatted(.dateTime.year().locale(locale))
        }
    }
}

/// Check-in squares for a single goal. Days the goal isn't scheduled for are dimmed out, so a
/// Mondays-only goal reads as a lit column of Mondays instead of a mostly empty grid.
struct ScheduleActivityView: View {
    let goal: Goal
    let range: StatsRange
    /// Which week/month/year to show — 0 is the current one, negative pages into the past.
    var offset: Int = 0

    private let calendar = Calendar.current

    private enum DayState {
        case done, scheduled, blocked
    }

    /// Distinct type from the weekday-label `Int` ids (1–7) so a grid's leading blanks never
    /// collide with them under `id: \.self` — SwiftUI faults if two sibling child views in the
    /// same LazyVGrid/LazyHGrid share an id, even across different `ForEach`s.
    private struct BlankDay: Hashable {
        let index: Int
    }

    private var checkInDays: Set<Date> {
        Set(goal.checkIns.map { calendar.startOfDay(for: $0.date) })
    }

    private var interval: DateInterval? {
        range.interval(offset: offset)
    }

    /// Every day in the displayed period, in order.
    private var periodDays: [Date] {
        guard let interval else { return [] }
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var doneCountInPeriod: Int {
        let days = checkInDays
        return periodDays.count { days.contains(calendar.startOfDay(for: $0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch range {
            case .week: weekGrid
            case .month: monthGrid
            case .year: yearGrid
            }
            quotaCaption
        }
    }

    // MARK: - Layouts

    // Plain stacks rather than a `LazyVGrid`: square cells inside a lazy grid resolve their size
    // from a width the grid only knows after the fact, so on a screen with a Chart above them the
    // grid measured one row short and the last week spilled out past the card. Rows of at most
    // seven cells are nothing to be lazy about anyway.

    private var weekGrid: some View {
        VStack(spacing: 4) {
            weekdayHeader(spacing: 6)
            HStack(spacing: 6) {
                ForEach(periodDays, id: \.self) { day in
                    square { cell(for: day, cornerRadius: 6) }
                }
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 4) {
            weekdayHeader(spacing: 4)
            // Blanks so the first day of the month lands under its weekday column.
            ForEach(Array(monthWeeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        square {
                            if let day {
                                cell(for: day, cornerRadius: 5)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
    }

    /// The month laid out a week to a row, padded with `nil` at both ends so every row has seven
    /// slots and the columns line up under their weekday.
    private var monthWeeks: [[Date?]] {
        var slots: [Date?] = Array(repeating: nil, count: leadingBlanks(before: periodDays.first))
        slots += periodDays.map { Optional($0) }
        if slots.count % 7 != 0 {
            slots += Array(repeating: nil, count: 7 - slots.count % 7)
        }
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    private func weekdayHeader(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(weekdayOrder, id: \.self) { weekday in
                Text(Recurrence.weekdayAbbreviation(weekday))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textGhost)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// One cell of a row: an equal share of the width, kept square.
    private func square<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
    }

    private var yearGrid: some View {
        let cellSize: CGFloat = 11
        let spacing: CGFloat = 3
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 7), spacing: spacing) {
                // Blanks so Jan 1 lands in its correct weekday row, same idea as the month grid.
                ForEach((0..<leadingBlanks(before: periodDays.first)).map(BlankDay.init), id: \.self) { _ in
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
                ForEach(periodDays, id: \.self) { day in
                    cell(for: day, cornerRadius: 2)
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .frame(height: cellSize * 7 + spacing * 6)
        }
        // The current year reads left-to-right up to today, so anchor on today's edge; a past
        // year is complete, so start from the beginning instead.
        .defaultScrollAnchor(offset == 0 ? .trailing : .leading)
        // Swiping through 365 labelled squares one at a time is no way to learn how a year went,
        // so the year view answers the actual question in one element instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("a11y.activity.summary \(doneCountInPeriod) \(periodDays.count)"))
    }

    // MARK: - Days

    /// Weekday numbers in the order the calendar lays them out (respects `firstWeekday`).
    private var weekdayOrder: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func leadingBlanks(before firstDay: Date?) -> Int {
        guard let firstDay else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    // MARK: - Cells

    private func state(for day: Date) -> DayState {
        if checkInDays.contains(calendar.startOfDay(for: day)) { return .done }
        return Recurrence.isDayScheduled(day, for: goal, calendar: calendar) ? .scheduled : .blocked
    }

    private func cell(for day: Date, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill(for: day))
            .overlay {
                if calendar.isDateInToday(day) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Theme.text, lineWidth: 1.5)
                }
            }
            // A filled square carries all its meaning in colour, so each day has to say its date
            // and its state out loud.
            .accessibilityElement()
            .accessibilityLabel(Text("\(day.formatted(date: .abbreviated, time: .omitted)), \(stateDescription(for: day))"))
    }

    private func stateDescription(for day: Date) -> String {
        let key: String.LocalizationValue = switch state(for: day) {
        case .done: "a11y.day.done"
        case .scheduled: "a11y.day.scheduled"
        case .blocked: "a11y.day.notScheduled"
        }
        return String(localized: key, bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
    }

    private func fill(for day: Date) -> Color {
        switch state(for: day) {
        case .done: Theme.accent
        case .scheduled: Theme.cellScheduled
        case .blocked: Theme.cellBlocked
        }
    }

    // MARK: - Quota

    /// Quota schedules ("3× a week") don't pin down days, so instead of blocking cells they get a
    /// count for the period the quota is defined over.
    @ViewBuilder
    private var quotaCaption: some View {
        let appliesToRange: Bool = switch (goal.recurrenceType, range) {
        case (.timesPerWeek, .week), (.timesPerMonth, .month): true
        default: false
        }

        if appliesToRange, let interval {
            let done = goal.checkIns.filter { interval.contains($0.date) }.count
            Text("stats.quota \(done) \(goal.recurrenceCount)")
                .font(Theme.Typo.caption)
                .foregroundStyle(done >= goal.recurrenceCount ? Theme.accentBright : Theme.textFaint)
        }
    }
}

#Preview {
    ScheduleActivityView(
        goal: Goal(title: "Gym", recurrenceType: .specificWeekdays, recurrenceWeekdays: [2, 4, 6]),
        range: .month
    )
    .padding()
}
