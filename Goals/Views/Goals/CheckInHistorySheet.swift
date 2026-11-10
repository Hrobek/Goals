//
//  CheckInHistorySheet.swift
//  Goals
//

import SwiftUI
import SwiftData

/// Fixes the goal's history after the fact: edits or deletes one past check-in, or, without one,
/// logs a day that was missed. Values are what the day logged, the same as the check-in sheet
/// asks for, so a running total is edited by the day's amount, not by the total it reached.
struct CheckInHistorySheet: View {
    let goal: Goal
    /// The check-in being edited. Nil adds a new entry on a day the user picks.
    let checkIn: CheckIn?
    var onSave: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var amountText: String
    @State private var note: String
    @State private var isConfirmingDelete = false
    /// Set on save, so the check-in that save just wrote doesn't flash up as "already has an
    /// entry" while the sheet slides away.
    @State private var isSaved = false

    init(goal: Goal, checkIn: CheckIn?, onSave: @escaping () -> Void = {}) {
        self.goal = goal
        self.checkIn = checkIn
        self.onSave = onSave
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        _day = State(initialValue: checkIn?.date ?? max(yesterday, goal.startDate))
        _note = State(initialValue: checkIn?.note ?? "")
        let value = checkIn.flatMap { ProgressLogger.loggedValue(of: $0, on: goal) }
        _amountText = State(initialValue: Self.format(value ?? (goal.isLowerBetter ? goal.currentValue : 1)))
    }

    private var isAdding: Bool { checkIn == nil }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var isValid: Bool {
        goal.trackingMode == .milestones || parsedAmount != nil
    }

    /// From the goal's start up to today. Nothing in the future: that hasn't happened yet.
    private var dayRange: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: min(goal.startDate, .now))
        return start...Date.now
    }

    /// The check-in already on the picked day, which adding to that day merges into.
    private var existingOnDay: CheckIn? {
        guard isAdding, !isSaved else { return nil }
        return goal.checkIns.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var amountHeader: LocalizedStringKey {
        goal.isLowerBetter ? "checkIn.field.newValue" : "checkIn.field.amount"
    }

    private var step: Double {
        GoalUnit(rawValue: goal.unitKey)?.quickAddSteps.first ?? 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.card) {
                    dayPanel

                    if goal.trackingMode == .value {
                        amountPanel
                    }

                    notePanel

                    if !isAdding {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("history.delete", systemImage: "trash")
                        }
                        .buttonStyle(NeutralOutlineButtonStyle())
                        .foregroundStyle(Theme.accentText)
                        // On the button, so the confirmation's popover points at it.
                        .confirmationDialog("history.delete.title", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("action.delete", role: .destructive) { delete() }
                            Button("action.cancel", role: .cancel) {}
                        } message: {
                            Text(goal.trackingMode == .value && !goal.isLowerBetter ? "history.delete.message.total" : "history.delete.message")
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .screenGround()
            .navigationTitle(isAdding ? "history.add.title" : "history.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Theme.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .foregroundStyle(Theme.accentText)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents(goal.trackingMode == .value ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAdding {
                DatePicker(selection: $day, in: dayRange, displayedComponents: .date) {
                    SectionLabel("history.field.day")
                }
                .tint(Theme.accent)
                if existingOnDay != nil {
                    Text(goal.trackingMode == .value && !goal.isLowerBetter ? "history.existingDay.total" : "history.existingDay")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textFaint)
                }
            } else {
                HStack {
                    SectionLabel("history.field.day")
                    Spacer()
                    Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var amountPanel: some View {
        VStack(spacing: 0) {
            SectionLabel(amountHeader)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 18) {
                stepButton(systemImage: "minus", accent: false) { adjust(by: -step) }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    TextField("checkIn.field.amountPlaceholder", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 44, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(goal.unitDisplayText)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                stepButton(systemImage: "plus", accent: true) { adjust(by: step) }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(radius: Theme.Radius.panel, padding: 18)
    }

    private func stepButton(systemImage: String, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(accent ? Theme.accentText : Theme.textStrong)
                .overlay {
                    Circle().strokeBorder(accent ? Theme.accent : Theme.textGhost, lineWidth: 1)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accent
            ? "a11y.quickAdd \(goal.valueWithUnit(step, formattedValue: Self.format(step)))"
            : "a11y.quickSubtract \(goal.valueWithUnit(step, formattedValue: Self.format(step)))"))
    }

    private var notePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("checkIn.field.note")
            TextField("checkIn.field.notePlaceholder", text: $note, axis: .vertical)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.text)
                .lineLimit(2...4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func adjust(by delta: Double) {
        let next = max((parsedAmount ?? 0) + delta, 0)
        amountText = Self.format(next)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private func save() {
        guard isValid else { return }
        let value = goal.trackingMode == .value ? parsedAmount : nil
        isSaved = true
        if let checkIn {
            ProgressLogger.edit(checkIn, on: goal, value: value, note: note, in: modelContext)
        } else {
            ProgressLogger.log(value: value, note: note, on: day, for: goal, in: modelContext)
        }
        onSave()
        dismiss()
    }

    private func delete() {
        guard let checkIn else { return }
        ProgressLogger.delete(checkIn, from: goal, in: modelContext)
        onSave()
        dismiss()
    }
}

#Preview {
    CheckInHistorySheet(goal: Goal(ownerId: UUID(), title: "Run 100 km", targetValue: 100, currentValue: 20, unitKey: GoalUnit.km.rawValue), checkIn: nil)
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
