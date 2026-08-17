//
//  AddCustomUnitSheet.swift
//  Goals
//

import SwiftUI
import SwiftData

struct AddCustomUnitSheet: View {
    var onCreate: (CustomUnit) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("unit.field.name", text: $name)
            }
            .themedList()
            .navigationTitle("unit.new.title")
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
        let unit = CustomUnit(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        modelContext.insert(unit)
        onCreate(unit)
        dismiss()
    }
}

#Preview {
    AddCustomUnitSheet(onCreate: { _ in })
        .modelContainer(for: [CustomUnit.self], inMemory: true)
}
