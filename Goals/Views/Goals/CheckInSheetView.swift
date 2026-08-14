//
//  CheckInSheetView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct CheckInSheetView: View {
    let goal: Goal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var note = ""

    init(goal: Goal) {
        self.goal = goal
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

    var body: some View {
        NavigationStack {
            Form {
                // Milestone goals have nothing to count up, so they only record the check-in itself.
                if goal.trackingMode == .value {
                    Section {
                        HStack {
                            TextField(amountPlaceholder, text: $amountText)
                                .keyboardType(.decimalPad)
                            Text(goal.unitDisplayText)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(amountHeader)
                    }
                }
                Section("checkIn.field.note") {
                    TextField("checkIn.field.notePlaceholder", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(goal.trackingMode == .value
                ? String(localized: "goalDetail.logValue", bundle: AppLanguage.currentBundle)
                : String(localized: "goalDetail.checkInToday", bundle: AppLanguage.currentBundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        var newValue: Double?
        if goal.trackingMode == .value, let amount = parsedAmount {
            newValue = goal.isLowerBetter ? amount : goal.currentValue + amount
        }

        ProgressLogger.record(value: newValue, note: note, for: goal, in: modelContext)
        dismiss()
    }
}

#Preview {
    CheckInSheetView(goal: Goal(title: "Run 100 km", targetValue: 100, currentValue: 20, unitKey: GoalUnit.km.rawValue))
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
