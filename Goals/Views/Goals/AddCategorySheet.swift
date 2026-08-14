//
//  AddCategorySheet.swift
//  Goals
//

import SwiftUI
import SwiftData

struct AddCategorySheet: View {
    var onCreate: (Category) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("category.field.name", text: $name)
            }
            .navigationTitle("category.new.title")
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
        let category = Category(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        modelContext.insert(category)
        onCreate(category)
        dismiss()
    }
}

#Preview {
    AddCategorySheet(onCreate: { _ in })
        .modelContainer(for: [Category.self], inMemory: true)
}
