//
//  UnitPickerSheet.swift
//  Goals
//

import SwiftUI
import SwiftData

/// Preset units grouped by kind (Weight, Currency, …), the user's own units, and
/// "Add Unit" as the last entry.
struct UnitPickerSheet: View {
    @Binding var selection: UnitSelection

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomUnit.createdAt) private var customUnits: [CustomUnit]

    @State private var isShowingAddUnit = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(GoalUnitCategory.allCases) { category in
                    Section(category.localizedName) {
                        ForEach(category.units) { unit in
                            row(title: unit.localizedName, isSelected: selection == .preset(unit)) {
                                selection = .preset(unit)
                                dismiss()
                            }
                        }
                    }
                }

                if !customUnits.isEmpty {
                    Section("unit.category.custom") {
                        ForEach(customUnits) { unit in
                            row(title: unit.name, isSelected: selection == .custom(unit.name)) {
                                selection = .custom(unit.name)
                                dismiss()
                            }
                        }
                        .onDelete(perform: deleteCustomUnits)
                    }
                }

                Section {
                    Button {
                        isShowingAddUnit = true
                    } label: {
                        Label("unit.add", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("goal.field.unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingAddUnit) {
                AddCustomUnitSheet { newUnit in
                    selection = .custom(newUnit.name)
                    dismiss()
                }
            }
        }
    }

    private func row(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func deleteCustomUnits(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customUnits[index])
        }
    }
}

#Preview {
    UnitPickerSheet(selection: .constant(.preset(.times)))
        .modelContainer(for: [CustomUnit.self], inMemory: true)
}
