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

    private enum PendingAdd {
        case blank
        case template(GoalTemplate)
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

    private var visibleGoals: [Goal] {
        goals.filter { $0.status == filter }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("goals.title") {
                    IconButton(systemImage: "plus") { addGoalTapped() }
                        .accessibilityLabel(Text("a11y.addGoal"))
                }

                SegmentStrip(
                    options: GoalStatus.allCases,
                    selection: $filter,
                    title: { $0.localizedName }
                )
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 18)

                goalsContent
            }
            .screenGround()
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
                TemplatePickerView { picked in
                    pendingAdd = picked.map(PendingAdd.template) ?? .blank
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
            .onChange(of: addGoalTrigger) { _, isTriggered in
                guard isTriggered else { return }
                addGoalTrigger = false
                // A brand-new user gets the template grid rather than the empty form — but the
                // free-tier limit still applies, in the odd case the trigger fires with goals
                // already in place.
                if !purchaseManager.isProUnlocked && activeGoalsCount >= Self.freeActiveGoalLimit {
                    isShowingLimitAlert = true
                    Analytics.send(.limitAlertShown)
                } else {
                    isShowingTemplatePicker = true
                }
            }
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
            List {
                ForEach(visibleGoals) { goal in
                    Button {
                        path.append(goal.id)
                    } label: {
                        GoalRow(goal: goal)
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(.top, 18, for: .scrollContent)
            .tabBarClearance()
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
            // The manual "+" and the empty-state button always open a blank form.
            addGoalConfig = AddGoalConfig()
        }
    }

    /// Runs after the template picker has fully dismissed: opens the Add Goal sheet seeded with
    /// whatever was chosen. A plain Cancel on the picker leaves `pendingAdd` nil and does nothing.
    private func presentPendingAdd() {
        guard let pendingAdd else { return }
        self.pendingAdd = nil

        switch pendingAdd {
        case .blank:
            addGoalConfig = AddGoalConfig()
        case .template(let template):
            addGoalConfig = AddGoalConfig(template: template, category: resolveCategory(template.categoryDefaultKey))
        }
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
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
