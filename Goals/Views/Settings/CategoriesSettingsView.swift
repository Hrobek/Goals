//
//  CategoriesSettingsView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// The one place to look after categories: rename, reorder, delete, add. Pushed from Settings.
/// The order set here is the order every category list and filter shows.
struct CategoriesSettingsView: View {
    let userId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [Category]
    @Query private var goals: [Goal]
    @Query private var habits: [Habit]

    @State private var isShowingAddCategory = false
    @State private var renaming: Category?
    @State private var renameText = ""
    @State private var pendingDelete: Category?

    init(userId: UUID) {
        self.userId = userId
        _categories = Query(filter: #Predicate<Category> { $0.ownerId == userId }, sort: Category.sortOrder)
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId })
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId })
    }

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button {
                        renameText = category.displayName
                        renaming = category
                    } label: {
                        row(for: category)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            requestDelete(category)
                        } label: {
                            Label("action.delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("category.manage.footer")
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
        .navigationTitle("settings.categories.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .sheet(isPresented: $isShowingAddCategory) {
            AddCategorySheet(userId: userId) { _ in }
        }
        .alert("category.rename.title", isPresented: isRenaming) {
            TextField("category.field.name", text: $renameText)
            Button("action.cancel", role: .cancel) {}
            Button("action.save") { rename() }
        }
        .alert(deleteTitle, isPresented: isConfirmingDelete) {
            Button("action.cancel", role: .cancel) {}
            Button("action.delete", role: .destructive) {
                if let pendingDelete { modelContext.delete(pendingDelete) }
            }
        } message: {
            Text("category.delete.message")
        }
    }

    private func row(for category: Category) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category.displayName)
                .foregroundStyle(.primary)
            Text(usageText(for: category))
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// "3 goals · 2 habits", leaving out whichever is zero, so it's clear what a delete touches.
    private func usageText(for category: Category) -> String {
        let goalCount = goals.count { $0.category?.id == category.id }
        let habitCount = habits.count { $0.category?.id == category.id }
        var parts: [String] = []
        if goalCount > 0 {
            parts.append(String(localized: "category.usage.goals \(goalCount)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale))
        }
        if habitCount > 0 {
            parts.append(String(localized: "category.usage.habits \(habitCount)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale))
        }
        guard !parts.isEmpty else {
            return String(localized: "category.usage.none", bundle: AppLanguage.currentBundle)
        }
        return parts.joined(separator: " · ")
    }

    private func isUsed(_ category: Category) -> Bool {
        goals.contains { $0.category?.id == category.id } || habits.contains { $0.category?.id == category.id }
    }

    /// An unused category just goes; one that still holds goals or habits asks first.
    private func requestDelete(_ category: Category) {
        if isUsed(category) {
            pendingDelete = category
        } else {
            modelContext.delete(category)
        }
    }

    /// Rewrites `sortIndex` across every category so the new order sticks and stays dense.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortIndex = index
        }
    }

    /// A renamed seeded category drops its `defaultKey`: the user's own name now wins over the
    /// translated default, in every language.
    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let renaming, !name.isEmpty, name != renaming.displayName else { return }
        renaming.name = name
        renaming.defaultKey = nil
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteTitle: String {
        let name = pendingDelete?.displayName ?? ""
        return String(localized: "category.delete.title \(name)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
    }
}

#Preview {
    NavigationStack {
        CategoriesSettingsView(userId: UUID())
            .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
    }
}
