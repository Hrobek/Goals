//
//  CategoryFilter.swift
//  Goals
//

import SwiftUI

/// One choice in a list's category filter: a real category, or everything without one.
enum CategoryFilter: Hashable {
    case category(UUID)
    case uncategorized

    init(_ category: Category?) {
        self = category.map { .category($0.id) } ?? .uncategorized
    }
}

struct CategoryFilterOption {
    let filter: CategoryFilter
    let title: String
}

struct CategoryGroup<Item: Identifiable>: Identifiable {
    let id: CategoryFilter?
    /// `nil` draws no header - the list is a single run of items.
    let title: String?
    let items: [Item]
}

/// The category filter the Goals and Habits lists share: which categories to offer, which of the
/// chosen ones still apply, and how the list groups under them.
struct CategoryFiltering<Item: Identifiable> {
    let items: [Item]
    /// The categories the items actually use, so no choice leads to an empty list. "No category"
    /// joins only next to a real category - on its own it would be the whole list.
    let options: [CategoryFilterOption]
    /// The chosen categories that still apply - recategorizing an item, or switching to a tab
    /// without one, drops it, and dropping the last one falls back to everything rather than an
    /// empty list.
    let active: Set<CategoryFilter>
    private let categoryOf: (Item) -> Category?

    init(items: [Item], selection: Set<CategoryFilter>, category: @escaping (Item) -> Category?) {
        self.items = items
        self.categoryOf = category

        var seen = Set<UUID>()
        var categories: [Category] = []
        for item in items {
            if let category = category(item), seen.insert(category.id).inserted {
                categories.append(category)
            }
        }
        var options = categories
            .sorted(by: Category.ordered)
            .map { CategoryFilterOption(filter: .category($0.id), title: $0.displayName) }
        if !options.isEmpty && items.contains(where: { category($0) == nil }) {
            options.append(CategoryFilterOption(
                filter: .uncategorized,
                title: String(localized: "goals.filter.uncategorized", defaultValue: "No category", bundle: AppLanguage.currentBundle)
            ))
        }
        self.options = options
        self.active = options.count >= 2 ? selection.intersection(options.map(\.filter)) : []
    }

    /// One option is no choice at all, so the filter only shows once there are two to pick from.
    var isShowingFilter: Bool { options.count >= 2 }

    /// The options the list is showing, in the menu's order.
    var shownOptions: [CategoryFilterOption] {
        active.isEmpty ? options : options.filter { active.contains($0.filter) }
    }

    var visibleItems: [Item] {
        guard !active.isEmpty else { return items }
        return items.filter { active.contains(CategoryFilter(categoryOf($0))) }
    }

    /// The items sit under a header per category, in the menu's order, so the list shows its shape
    /// without a tap. A single category, or a list with nothing to tell apart, is one plain run.
    var groups: [CategoryGroup<Item>] {
        let shown = shownOptions
        guard isShowingFilter, shown.count >= 2 else {
            return [CategoryGroup(id: shown.first?.filter, title: nil, items: visibleItems)]
        }
        return shown.map { option in
            CategoryGroup(id: option.filter, title: option.title, items: items.filter { CategoryFilter(categoryOf($0)) == option.filter })
        }
    }

    /// The one real category the list is narrowed to, if it is exactly one - what a new item
    /// starts out in.
    var selectedCategory: Category? {
        guard active.count == 1, case .category(let id) = active.first else { return nil }
        return items.lazy.compactMap(categoryOf).first { $0.id == id }
    }
}

/// Choosing categories is occasional - the headers already show the list's shape - so it lives
/// behind a button rather than taking a row of its own.
struct CategoryFilterMenu: View {
    let options: [CategoryFilterOption]
    let active: Set<CategoryFilter>
    @Binding var selection: Set<CategoryFilter>

    var body: some View {
        Menu {
            Button {
                selection = []
            } label: {
                if active.isEmpty {
                    Label(allTitle, systemImage: "checkmark")
                } else {
                    Text(allTitle)
                }
            }
            Divider()
            // Toggles that leave the menu open, so several categories can be picked in one go.
            // Not animated: the list reshuffling under the open menu is enough motion.
            ForEach(options, id: \.filter) { option in
                Toggle(option.title, isOn: Binding(
                    get: { active.contains(option.filter) },
                    // Mutates the selection in place: the open menu keeps the closures it was
                    // built with, so anything derived here would be a stale snapshot.
                    set: { isOn in
                        if isOn { selection.insert(option.filter) } else { selection.remove(option.filter) }
                    }
                ))
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            // Lights up while categories are chosen, so a narrowed list never passes for the whole.
            IconButtonLabel(accent: !active.isEmpty) { FunnelGlyph() }
        }
        .accessibilityLabel(Text("a11y.filterByCategory"))
    }

    private var allTitle: String {
        String(localized: "goals.filter.all", defaultValue: "All", bundle: AppLanguage.currentBundle)
    }
}

/// Names the categories the list is narrowed to; each one's ✕ takes it back out.
struct CategoryFilterPills: View {
    let options: [CategoryFilterOption]
    @Binding var selection: Set<CategoryFilter>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(options, id: \.filter) { option in
                    pill(option.title) {
                        withAnimation(.snappy(duration: 0.18)) { _ = selection.remove(option.filter) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.screen)
        }
        .scrollIndicators(.hidden)
    }

    private func pill(_ title: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Theme.accentWell, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.accentWellBorder, lineWidth: 1) }
            .foregroundStyle(Theme.accentWellText)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("a11y.clearCategoryFilter"))
        .accessibilityValue(Text(verbatim: title))
    }
}

/// A category's header inside a card list. A plain row rather than a `Section` header: a plain
/// List pins those with a system background that doesn't sit on the screen's own ground. The list
/// needs `.environment(\.defaultMinListRowHeight, 0)`, or the label is padded out to 44 pt.
struct CategoryGroupHeader: View {
    let title: String
    let isFirst: Bool

    var body: some View {
        // The card rows' own 5 pt insets already make up the label-to-card gap.
        SectionLabel(verbatim: title)
            .padding(.top, isFirst ? 0 : Theme.Space.section - 10)
            .listRowInsets(EdgeInsets(top: 5, leading: Theme.Space.screen, bottom: 5, trailing: Theme.Space.screen))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}
