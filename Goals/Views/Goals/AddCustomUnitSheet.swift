//
//  AddCustomUnitSheet.swift
//  Goals
//

import SwiftUI
import SwiftData

struct AddCustomUnitSheet: View {
    let userId: UUID
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
        let unit = CustomUnit(ownerId: userId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        modelContext.insert(unit)
        onCreate(unit)
        dismiss()
    }
}

#Preview {
    AddCustomUnitSheet(userId: UUID(), onCreate: { _ in })
        .modelContainer(for: [CustomUnit.self], inMemory: true)
}
