//
//  CheckInSheetView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct CheckInSheetView: View {
    let goal: Goal
    /// Called after a check-in is written. The haptic belongs to the screen that stays on
    /// screen — this sheet is already dismissing by then and would never get to play it.
    var onSave: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    @State private var amountText: String
    @State private var note = ""

    init(goal: Goal, onSave: @escaping () -> Void = {}) {
        self.goal = goal
        self.onSave = onSave
        // Lower-is-better goals record today's measurement (step on the scale, read 94);
        // everything else adds to a running total.
        _amountText = State(initialValue: goal.isLowerBetter
            ? goal.currentValue.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            : "1")
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var isValid: Bool {
        goal.trackingMode == .milestones || parsedAmount != nil
    }

    private var amountHeader: LocalizedStringKey {
        goal.isLowerBetter ? "checkIn.field.newValue" : "checkIn.field.amount"
    }

    private var amountPlaceholder: LocalizedStringKey {
        goal.isLowerBetter ? "checkIn.field.newValuePlaceholder" : "checkIn.field.amountPlaceholder"
    }

    /// What the −/+ buttons move by: the unit's own natural step, so a run nudges by a kilometre
    /// and a savings goal by whatever that unit counts in.
    private var step: Double {
        GoalUnit(rawValue: goal.unitKey)?.quickAddSteps.first ?? 1
    }

    /// Where the goal lands if this check-in is saved as it stands.
    private var projectedValue: Double? {
        guard goal.trackingMode == .value, let amount = parsedAmount else { return nil }
        return goal.isLowerBetter ? amount : goal.currentValue + amount
    }

    private var projectedFraction: Double {
        guard let projectedValue, goal.targetValue != goal.startValue else { return goal.progressFraction }
        let span = goal.targetValue - goal.startValue
        return min(max((projectedValue - goal.startValue) / span, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.card) {
                    goalLine

                    if goal.trackingMode == .value {
                        amountPanel
                    }

                    notePanel

                    Button { save() } label: {
                        Label(
                            goal.trackingMode == .value ? "goalDetail.logValue" : "goalDetail.checkInToday",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.5)
                    .padding(.top, 4)
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .screenGround()
            .navigationTitle(goal.trackingMode == .value
                ? String(localized: "goalDetail.logValue", bundle: AppLanguage.currentBundle)
                : String(localized: "goalDetail.checkInToday", bundle: AppLanguage.currentBundle))
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

    /// Which goal this is about — the sheet can be opened from a row that's already scrolled away.
    private var goalLine: some View {
        HStack(spacing: 12) {
            GoalBadge(emoji: goal.emoji, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(Theme.Typo.rowTitle)
                    .foregroundStyle(Theme.text)
                Text(currentText)
                    .font(Theme.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 0)
        }
    }

    private var currentText: String {
        switch goal.trackingMode {
        case .value:
            "\(formatted(goal.currentValue))/\(goal.valueWithUnit(goal.targetValue, formattedValue: formatted(goal.targetValue)))"
        case .milestones:
            "\(goal.completedMilestoneCount)/"
                + String(localized: "milestone.unit.count \(goal.milestones.count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        }
    }

    /// The number being logged, big enough to read at arm's length, with a step either side.
    private var amountPanel: some View {
        VStack(spacing: 0) {
            SectionLabel(amountHeader)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 18) {
                stepButton(systemImage: "minus", accent: false) { adjust(by: -step) }

                // The number ends where the unit begins, and that seam sits in the middle of the
                // row — so the pair stays centred however many digits are typed.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    TextField(amountPlaceholder, text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
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

            ThinBar(progress: projectedFraction)
                .padding(.top, 18)
                .padding(.bottom, 8)

            Text(projectionText)
                .font(Theme.Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(radius: Theme.Radius.panel, padding: 18)
    }

    private var projectionText: String {
        guard let projectedValue else { return currentText }
        return "\(formatted(goal.currentValue)) → \(goal.valueWithUnit(projectedValue, formattedValue: formatted(projectedValue)))"
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
            ? "a11y.quickAdd \(goal.valueWithUnit(step, formattedValue: formatted(step)))"
            : "a11y.quickSubtract \(goal.valueWithUnit(step, formattedValue: formatted(step)))"))
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
        let base = parsedAmount ?? 0
        let next = max(base + delta, 0)
        amountText = next.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func save() {
        guard isValid else { return }
        var newValue: Double?
        if goal.trackingMode == .value, let amount = parsedAmount {
            newValue = goal.isLowerBetter ? amount : goal.currentValue + amount
        }

        ProgressLogger.record(value: newValue, note: note, for: goal, in: modelContext)
        onSave()
        dismiss()
    }
}

#Preview {
    CheckInSheetView(goal: Goal(title: "Run 100 km", targetValue: 100, currentValue: 20, unitKey: GoalUnit.km.rawValue))
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
