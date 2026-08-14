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
}

/// Check-in squares for a single goal. Days the goal isn't scheduled for are dimmed out, so a
/// Mondays-only goal reads as a lit column of Mondays instead of a mostly empty grid.
struct ScheduleActivityView: View {
    let goal: Goal
    let range: StatsRange

    private let calendar = Calendar.current
    /// Keeps week and month cells the same compact size (and the columns aligned between the two)
    /// instead of stretching to the full row width.
    private let gridWidth: CGFloat = 252

    private enum DayState {
        case done, scheduled, blocked
    }

    private var checkInDays: Set<Date> {
        Set(goal.checkIns.map { calendar.startOfDay(for: $0.date) })
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

    private var weekGrid: some View {
        let days = self.days(ofPeriod: .weekOfYear)
        return LazyVGrid(columns: columns(count: 7, spacing: 6), spacing: 4) {
            // Keyed by weekday, not by date: two sibling ForEach over the same dates would share
            // ids inside one grid and collapse the row of cells.
            ForEach(weekdayOrder, id: \.self) { weekday in
                Text(Recurrence.weekdayAbbreviation(weekday))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                cell(for: day, cornerRadius: 6)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: gridWidth, alignment: .leading)
    }

    private var monthGrid: some View {
        let days = self.days(ofPeriod: .month)
        return LazyVGrid(columns: columns(count: 7, spacing: 4), spacing: 4) {
            ForEach(weekdayOrder, id: \.self) { weekday in
                Text(Recurrence.weekdayAbbreviation(weekday))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Blanks so the first day of the month lands under its weekday column.
            ForEach(0..<leadingBlanks(before: days.first), id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
            ForEach(days, id: \.self) { day in
                cell(for: day, cornerRadius: 5)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: gridWidth, alignment: .leading)
    }

    private var yearGrid: some View {
        let cellSize: CGFloat = 11
        let spacing: CGFloat = 3
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 7), spacing: spacing) {
                ForEach(yearDays, id: \.self) { day in
                    cell(for: day, cornerRadius: 2)
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .frame(height: cellSize * 7 + spacing * 6)
        }
        .defaultScrollAnchor(.trailing)
    }

    // MARK: - Days

    private func columns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// Weekday numbers in the order the calendar lays them out (respects `firstWeekday`).
    private var weekdayOrder: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func days(ofPeriod component: Calendar.Component) -> [Date] {
        guard let interval = calendar.dateInterval(of: component, for: .now) else { return [] }
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// 52 whole weeks ending with the current one, so every row is the same weekday.
    private var yearDays: [Date] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now),
              let start = calendar.date(byAdding: .weekOfYear, value: -51, to: thisWeek.start) else { return [] }
        return (0..<(52 * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
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
                        .stroke(Color.primary.opacity(0.4), lineWidth: 1.5)
                }
            }
    }

    private func fill(for day: Date) -> Color {
        switch state(for: day) {
        case .done: Color(hex: goal.colorHex)
        case .scheduled: Color.secondary.opacity(0.18)
        case .blocked: Color.secondary.opacity(0.05)
        }
    }

    // MARK: - Quota

    /// Quota schedules ("3× a week") don't pin down days, so instead of blocking cells they get a
    /// count for the period the quota is defined over.
    @ViewBuilder
    private var quotaCaption: some View {
        let component: Calendar.Component? = switch (goal.recurrenceType, range) {
        case (.timesPerWeek, .week): .weekOfYear
        case (.timesPerMonth, .month): .month
        default: nil
        }

        if let component, let interval = calendar.dateInterval(of: component, for: .now) {
            let done = goal.checkIns.filter { interval.contains($0.date) }.count
            Text("stats.quota \(done) \(goal.recurrenceCount)")
                .font(.caption)
                .foregroundStyle(done >= goal.recurrenceCount ? Color.green : Color.secondary)
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
