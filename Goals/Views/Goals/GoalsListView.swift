//
//  GoalsListView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct GoalsListView: View {
    static let freeActiveGoalLimit = 3

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query private var goals: [Goal]

    let userId: UUID

    /// Flipped by `RootView` to drop the new-user straight into Add Goal after the first-run
    /// welcome sheet, instead of leaving them looking at an empty list.
    @Binding private var addGoalTrigger: Bool

    /// Pushing is driven by the path rather than by a `NavigationLink` inside each row: a link in a
    /// List row brings a disclosure chevron the design doesn't have, and hiding it behind the card
    /// leaves two overlapping tap targets that can push the wrong goal.
    @State private var path: [UUID] = []
    @State private var filter: GoalStatus = .active
    /// The categories the list is narrowed to, on top of the status tab. Empty is all of them.
    @State private var categoryFilter: Set<CategoryFilter> = []
    @State private var isShowingLimitAlert = false
    @State private var isShowingPaywall = false

    /// The first-run template grid, shown once via `addGoalTrigger` in place of a blank form.
    @State private var isShowingTemplatePicker = false
    /// What the template picker chose, applied once the picker has finished dismissing so the Add
    /// Goal sheet isn't stacked on the outgoing one.
    @State private var pendingAdd: PendingAdd?
    /// Drives the Add Goal sheet. An item rather than a bool so its template/category ride in as
    /// the presentation payload — captured once, and safe from a stray dismiss clearing them.
    @State private var addGoalConfig: AddGoalConfig?

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The screen's width, which decides whether the selected goal opens beside the list.
    @State private var availableWidth: CGFloat = 0
    /// The goal showing in the pane beside the list, while the screen is split.
    @State private var selectedGoalID: UUID?

    /// The open iPhone Duo held sideways: the list on one side, the selected goal on the other.
    private var isSplit: Bool {
        MainTabView.usesRail(sizeClass) && availableWidth >= Theme.listDetailMinWidth
    }

    private enum PendingAdd {
        case blank
        case template(GoalTemplate)
    }

    private enum CategoryFilter: Hashable {
        case category(UUID)
        case uncategorized
    }

    private struct AddGoalConfig: Identifiable {
        let id = UUID()
        var template: GoalTemplate?
        var category: Category?
    }

    init(userId: UUID, addGoalTrigger: Binding<Bool> = .constant(false)) {
        self.userId = userId
        self._addGoalTrigger = addGoalTrigger
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
    }

    private var activeGoalsCount: Int {
        goals.filter { $0.status == .active }.count
    }

    private var statusGoals: [Goal] {
        goals.filter { $0.status == filter }
    }

    /// The categories the current tab's goals actually use, so no choice leads to an empty list.
    /// "No category" joins only next to a real category - on its own it would be the whole list.
    private var categoryOptions: [(filter: CategoryFilter, title: String)] {
        var seen = Set<UUID>()
        var categories: [Category] = []
        for goal in statusGoals {
            if let category = goal.category, seen.insert(category.id).inserted {
                categories.append(category)
            }
        }
        var options = categories
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { (filter: CategoryFilter.category($0.id), title: $0.displayName) }
        if !options.isEmpty && statusGoals.contains(where: { $0.category == nil }) {
            options.append((
                filter: .uncategorized,
                title: String(localized: "goals.filter.uncategorized", defaultValue: "No category", bundle: AppLanguage.currentBundle)
            ))
        }
        return options
    }

    /// One option is no choice at all, so the filter only shows once there are two to pick from.
    private var isShowingCategoryFilter: Bool {
        categoryOptions.count >= 2
    }

    /// The chosen categories that still apply - switching to a tab without one, or recategorizing
    /// its last goal, drops it, and dropping the last one falls back to everything rather than an
    /// empty list.
    private var activeCategoryFilter: Set<CategoryFilter> {
        guard isShowingCategoryFilter else { return [] }
        return categoryFilter.intersection(categoryOptions.map(\.filter))
    }

    /// The options the list is showing, in the menu's order.
    private var shownCategoryOptions: [(filter: CategoryFilter, title: String)] {
        let active = activeCategoryFilter
        return active.isEmpty ? categoryOptions : categoryOptions.filter { active.contains($0.filter) }
    }

    private func goals(in filter: CategoryFilter) -> [Goal] {
        switch filter {
        case .uncategorized: statusGoals.filter { $0.category == nil }
        case .category(let id): statusGoals.filter { $0.category?.id == id }
        }
    }

    private var visibleGoals: [Goal] {
        let active = activeCategoryFilter
        guard !active.isEmpty else { return statusGoals }
        return statusGoals.filter { goal in
            active.contains(goal.category.map { .category($0.id) } ?? .uncategorized)
        }
    }

    private struct GoalGroup: Identifiable {
        let id: CategoryFilter?
        /// `nil` draws no header - the list is a single run of goals.
        let title: String?
        let goals: [Goal]
    }

    /// The goals sit under a header per category, in the menu's order, so the list shows its shape
    /// without a tap. A single category, or a list with nothing to tell apart, is one plain run.
    private var goalGroups: [GoalGroup] {
        let shown = shownCategoryOptions
        guard isShowingCategoryFilter, shown.count >= 2 else {
            return [GoalGroup(id: shown.first?.filter, title: nil, goals: visibleGoals)]
        }
        return shown.map { GoalGroup(id: $0.filter, title: $0.title, goals: goals(in: $0.filter)) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSplit {
                    ListDetailSplit { listColumn } detail: { goalPane }
                } else {
                    listColumn.readableWidth()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .screenGround()
            // Folding the phone shut, or turning it upright, carries the open goal over as a
            // pushed page - and opening it back up moves a pushed goal into the pane.
            .onChange(of: isSplit) { _, split in
                if split {
                    if let id = path.last {
                        selectedGoalID = id
                        path = []
                    }
                } else if let id = selectedGoalID {
                    path = [id]
                    selectedGoalID = nil
                }
            }
            .onChange(of: path) { _, newPath in
                if isSplit, let id = newPath.last {
                    selectedGoalID = id
                    path = []
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let goal = goals.first(where: { $0.id == id }) {
                    GoalDetailView(goal: goal)
                }
            }
            .sheet(item: $addGoalConfig) { config in
                AddEditGoalView(goal: nil, userId: userId, template: config.template, presetCategory: config.category)
            }
            .sheet(isPresented: $isShowingTemplatePicker, onDismiss: presentPendingAdd) {
                TemplatePickerView(mode: .goalsOnly) { selection in
                    if case .goal(let template) = selection {
                        pendingAdd = .template(template)
                    } else {
                        pendingAdd = .blank
                    }
                    isShowingTemplatePicker = false
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView(source: .limitAlert)
            }
            .sensoryFeedback(.warning, trigger: isShowingLimitAlert) { _, isShowing in isShowing }
            .alert("goals.limit.title", isPresented: $isShowingLimitAlert) {
                Button("goals.limit.upgrade") { isShowingPaywall = true }
                Button("action.ok", role: .cancel) {}
            } message: {
                Text("goals.limit.message")
            }
        }
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle("goals.title") {
                HStack(spacing: 8) {
                    if isShowingCategoryFilter {
                        categoryMenu
                    }
                    IconButton(systemImage: "plus") { addGoalTapped() }
                        .accessibilityLabel(Text("a11y.addGoal"))
                }
            }

            SegmentStrip(
                options: GoalStatus.allCases,
                selection: $filter,
                title: { $0.localizedName }
            )
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, 18)

            if !activeCategoryFilter.isEmpty {
                activeCategoryPills
                    .padding(.top, 12)
            }

            goalsContent
        }
    }

    /// Choosing categories is occasional - the headers already show the list's shape - so it lives
    /// behind a button rather than taking a row of its own.
    private var categoryMenu: some View {
        Menu {
            Button {
                categoryFilter = []
            } label: {
                if activeCategoryFilter.isEmpty {
                    Label(allCategoriesTitle, systemImage: "checkmark")
                } else {
                    Text(allCategoriesTitle)
                }
            }
            Divider()
            // Toggles that leave the menu open, so several categories can be picked in one go.
            // Not animated: the list reshuffling under the open menu is enough motion.
            ForEach(categoryOptions, id: \.filter) { option in
                Toggle(option.title, isOn: Binding(
                    get: { activeCategoryFilter.contains(option.filter) },
                    // Mutates the state in place: the open menu keeps the closures it was built
                    // with, so anything derived here would be a stale snapshot.
                    set: { isOn in
                        if isOn { categoryFilter.insert(option.filter) } else { categoryFilter.remove(option.filter) }
                    }
                ))
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            // Lights up while categories are chosen, so a narrowed list never passes for the whole.
            IconButtonLabel(accent: !activeCategoryFilter.isEmpty) { FunnelGlyph() }
        }
        .accessibilityLabel(Text("a11y.filterByCategory"))
    }

    private var allCategoriesTitle: String {
        String(localized: "goals.filter.all", defaultValue: "All", bundle: AppLanguage.currentBundle)
    }

    /// Names the categories the list is narrowed to; each one's ✕ takes it back out.
    private var activeCategoryPills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(shownCategoryOptions, id: \.filter) { option in
                    activeCategoryPill(option.title) {
                        withAnimation(.snappy(duration: 0.18)) { categoryFilter.remove(option.filter) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.screen)
        }
        .scrollIndicators(.hidden)
    }

    private func activeCategoryPill(_ title: String, remove: @escaping () -> Void) -> some View {
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

    /// Only a goal the list is showing, so archiving or deleting the open one empties the pane
    /// instead of leaving it behind.
    @ViewBuilder
    private var goalPane: some View {
        if let id = selectedGoalID, let goal = visibleGoals.first(where: { $0.id == id }) {
            GoalDetailView(goal: goal)
                .id(goal.id)
        } else {
            EmptyStateView(title: "split.goal.placeholder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenGround()
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func open(_ goal: Goal) {
        if isSplit {
            selectedGoalID = goal.id
        } else {
            path.append(goal.id)
        }
    }

    @ViewBuilder
    private var goalsContent: some View {
        if visibleGoals.isEmpty {
            VStack {
                Spacer(minLength: 40)
                EmptyStateView(
                    systemImage: emptySymbol,
                    title: emptyTitle,
                    message: filter == .active ? "goals.empty.description" : nil
                ) {
                    if filter == .active {
                        Button { addGoalTapped() } label: {
                            Label("a11y.addGoal", systemImage: "plus")
                        }
                        .buttonStyle(AccentOutlineButtonStyle(height: 42))
                        .fixedSize()
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .tabBarClearance()
        } else {
            // Still a `List` under the card styling: swiping a goal away to archive or delete it
            // is the screen's other half, and only a List brings that with it.
            // Headers are plain rows rather than `Section` headers: a plain List pins those with a
            // system background that doesn't sit on the screen's own ground.
            List {
                ForEach(Array(goalGroups.enumerated()), id: \.element.id) { index, group in
                    if let title = group.title {
                        // The card rows' own 5 pt insets already make up the label-to-card gap.
                        SectionLabel(verbatim: title)
                            .padding(.top, index > 0 ? Theme.Space.section - 10 : 0)
                            .listRowInsets(EdgeInsets(top: 5, leading: Theme.Space.screen, bottom: 5, trailing: Theme.Space.screen))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.goals) { goal in
                        goalRow(goal)
                    }
                }
            }
            .listStyle(.plain)
            // Otherwise a section label is padded out to a full 44 pt row.
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(.top, 18, for: .scrollContent)
            .tabBarClearance()
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        Button {
            open(goal)
        } label: {
            GoalRow(goal: goal)
                .selectedRowOutline(isSplit && selectedGoalID == goal.id)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: Theme.Space.screen, bottom: 5, trailing: Theme.Space.screen))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(goal)
                syncReminders()
            } label: {
                Label("action.delete", systemImage: "trash")
            }
            Button {
                goal.isArchived.toggle()
                syncReminders()
            } label: {
                Label(
                    goal.isArchived ? "action.unarchive" : "action.archive",
                    systemImage: goal.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .tint(Theme.control)
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch filter {
        case .active: "goals.empty.title"
        case .completed: "goals.empty.completed"
        case .archived: "goals.empty.archived"
        }
    }

    /// `nil` for the active tab, which draws the app's own mark instead of a symbol.
    private var emptySymbol: String? {
        switch filter {
        case .active: nil
        case .completed: "checkmark.circle"
        case .archived: "archivebox"
        }
    }

    /// Archived and deleted goals must stop nudging right away, not at the next app launch.
    private func syncReminders() {
        let context = modelContext
        let userId = userId
        Task { await NotificationScheduler.syncAll(context: context, userId: userId) }
    }

    private func addGoalTapped() {
        if !purchaseManager.isProUnlocked && activeGoalsCount >= Self.freeActiveGoalLimit {
            isShowingLimitAlert = true
            Analytics.send(.limitAlertShown)
        } else {
            // The "+" and the empty-state button open the template grid; "Custom goal" on it
            // leads to the blank form.
            isShowingTemplatePicker = true
        }
    }

    /// Runs after the template picker has fully dismissed: opens the Add Goal sheet seeded with
    /// whatever was chosen. A plain Cancel on the picker leaves `pendingAdd` nil and does nothing.
    private func presentPendingAdd() {
        guard let pendingAdd else { return }
        self.pendingAdd = nil

        switch pendingAdd {
        case .blank:
            // A goal added while the list is narrowed to a category most likely belongs in it.
            addGoalConfig = AddGoalConfig(category: selectedCategory)
        case .template(let template):
            addGoalConfig = AddGoalConfig(template: template, category: resolveCategory(template.categoryDefaultKey))
        }
    }

    /// Only when exactly one category is chosen - with several there's no telling which one.
    private var selectedCategory: Category? {
        guard activeCategoryFilter.count == 1, case .category(let id) = activeCategoryFilter.first else { return nil }
        return statusGoals.lazy.compactMap(\.category).first { $0.id == id }
    }

    /// The user's own seeded category for a template key, or nil if they've deleted it. Filtered in
    /// Swift rather than in the predicate — an optional-to-non-optional `defaultKey` comparison
    /// inside `#Predicate` is exactly the kind of thing SwiftData miscompiles.
    private func resolveCategory(_ key: String?) -> Category? {
        guard let key else { return nil }
        let userId = userId
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.ownerId == userId })
        return (try? modelContext.fetch(descriptor))?.first { $0.defaultKey == key }
    }
}

#Preview {
    GoalsListView(userId: UUID())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
