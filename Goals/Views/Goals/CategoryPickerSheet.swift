//
//  CategoryPickerSheet.swift
//  Goals
//

import SwiftUI
import SwiftData

/// Full-height picker presented from the goal form: a plain list of categories with
/// "Add Category" as the last entry.
struct CategoryPickerSheet: View {
    @Binding var selection: Category?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.createdAt) private var categories: [Category]

    @State private var isShowingAddCategory = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            selection = category
                            dismiss()
                        } label: {
                            HStack {
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selection?.id == category.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentText)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteCategories)
                }

                Section {
                    Button {
                        isShowingAddCategory = true
                    } label: {
                        Label("category.add", systemImage: "plus.circle")
                    }
                }
            }
            .themedList()
            .navigationTitle("goal.field.category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingAddCategory) {
                AddCategorySheet { newCategory in
                    selection = newCategory
                    dismiss()
                }
            }
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            let category = categories[index]
            if selection?.id == category.id {
                selection = nil
            }
            modelContext.delete(category)
        }
    }
}

#Preview {
    CategoryPickerSheet(selection: .constant(nil))
        .modelContainer(for: [Category.self], inMemory: true)
}
