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
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    /// Pushing is driven by the path rather than by a `NavigationLink` inside each row: a link in a
    /// List row brings a disclosure chevron the design doesn't have, and hiding it behind the card
    /// leaves two overlapping tap targets that can push the wrong goal.
    @State private var path: [UUID] = []
    @State private var filter: GoalStatus = .active
    @State private var isShowingAddGoal = false
    @State private var isShowingLimitAlert = false
    @State private var isShowingPaywall = false

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
            .sheet(isPresented: $isShowingAddGoal) {
                AddEditGoalView(goal: nil)
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
        Task { await NotificationScheduler.syncAll(context: context) }
    }

    private func addGoalTapped() {
        if !purchaseManager.isProUnlocked && activeGoalsCount >= Self.freeActiveGoalLimit {
            isShowingLimitAlert = true
            Analytics.send(.limitAlertShown)
        } else {
            isShowingAddGoal = true
        }
    }
}

#Preview {
    GoalsListView()
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
