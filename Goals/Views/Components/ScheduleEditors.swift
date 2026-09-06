//
//  ScheduleEditors.swift
//  Goals
//
//  The recurrence and reminder editors, shared by the goal form and the habit form so the two
//  never drift apart. Lifted verbatim from `AddEditGoalView` — same rows, same Pro gating.
//

import SwiftUI

// MARK: - Weekday chips

/// A row of Sun…Sat toggles. Used by the weekly recurrence picker and the weekly reminder picker.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selection.contains(day)
                Button {
                    if isSelected { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Recurrence.weekdayAbbreviation(day))
                        .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(isSelected ? Theme.accent : Theme.control, in: .capsule)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// The 1…31 grid for "specific days of the month".
struct DaysOfMonthGrid: View {
    @Binding var selection: Set<Int>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(1...31, id: \.self) { day in
                let isSelected = selection.contains(day)
                Button {
                    if isSelected { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text("\(day)")
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .monospacedDigit()
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Theme.accent : Theme.control, in: .circle)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Recurrence

/// The "Every day / specific weekdays / N× a week / …" picker plus whatever sub-control the
/// chosen type needs. Caller wraps it in its own `LabeledSection`.
struct RecurrenceEditor: View {
    @Binding var type: RecurrenceType
    @Binding var weekdays: Set<Int>
    @Binding var daysOfMonth: Set<Int>
    @Binding var count: Int

    var body: some View {
        CardGroup {
            MenuRow(
                label: "goal.field.recurrence",
                options: RecurrenceType.allCases,
                selection: $type.animation(),
                title: { $0.localizedName }
            )

            switch type {
            case .daily:
                EmptyView()
            case .specificWeekdays:
                RowDivider()
                WeekdayChips(selection: $weekdays)
                    .padding(.vertical, 14)
            case .timesPerWeek:
                RowDivider()
                Stepper(value: $count, in: 1...7) {
                    Text("recurrence.timesPerWeek.count \(count)")
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 9)
            case .specificDaysOfMonth:
                RowDivider()
                DaysOfMonthGrid(selection: $daysOfMonth)
                    .padding(.vertical, 14)
            case .timesPerMonth:
                RowDivider()
                Stepper(value: $count, in: 1...31) {
                    Text("recurrence.timesPerMonth.count \(count)")
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 9)
            }
        }
    }
}

// MARK: - Reminders

/// The reminder card: on/off, frequency, one or more times of day (extra times are Pro), and the
/// weekday picker when weekly. Caller wraps it in its own `LabeledSection` and owns the
/// notification-permission flow that runs when `isOn` flips true.
struct ReminderEditor: View {
    @Binding var isOn: Bool
    @Binding var frequency: ReminderFrequency
    @Binding var times: [Date]
    @Binding var weekdays: Set<Int>
    var isProUnlocked: Bool
    var maxProReminderTimes = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup {
                SwitchRow(label: "reminder.enabled", isOn: $isOn.animation())

                if isOn {
                    RowDivider()
                    MenuRow(
                        label: "reminder.frequency",
                        options: ReminderFrequency.allCases,
                        selection: $frequency.animation(),
                        title: { $0.localizedName }
                    )

                    ForEach(Array(times.enumerated()), id: \.offset) { index, _ in
                        RowDivider()
                        HStack(spacing: 10) {
                            if index == 0 {
                                Text(times.count > 1 ? "reminder.times" : "reminder.time")
                                    .font(Theme.Typo.row)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 10)
                            DatePicker("", selection: $times[index], displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            if times.count > 1 {
                                Button {
                                    withAnimation { _ = times.remove(at: index) }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 17))
                                        .foregroundStyle(Theme.textGhost)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("a11y.removeTime"))
                            }
                        }
                        .padding(.vertical, 9)
                    }

                    if isProUnlocked, times.count < maxProReminderTimes {
                        RowDivider()
                        Button {
                            addTime()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                                Text("reminder.addTime")
                                    .font(Theme.Typo.row)
                                    .foregroundStyle(Theme.accentText)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                    }

                    if frequency == .weekly {
                        RowDivider()
                        WeekdayChips(selection: $weekdays)
                            .padding(.vertical, 14)
                    }
                }
            }

            if isOn, !isProUnlocked {
                ProLockedCard(title: "reminder.multiple.title", message: "reminder.multiple.locked")
            }

            if isOn, frequency == .weekly, weekdays.isEmpty {
                Text("reminder.pickDays")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Appends a new reminder time an hour after the last one.
    private func addTime() {
        let base = times.last ?? .now
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: base) ?? base
        withAnimation { times.append(next) }
    }
}
