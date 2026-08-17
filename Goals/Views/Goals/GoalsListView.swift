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
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Picker("goals.filter", selection: $filter) {
                    ForEach(GoalStatus.allCases) { status in
                        Text(status.localizedName).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, 4)

                goalsContent
            }
            .navigationTitle("goals.title")
            .navigationDestination(for: UUID.self) { id in
                if let goal = goals.first(where: { $0.id == id }) {
                    GoalDetailView(goal: goal)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addGoalTapped()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddGoal) {
                AddEditGoalView(goal: nil)
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView(source: .limitAlert)
            }
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
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                if filter == .active {
                    Text("goals.empty.description")
                }
            }
        } else {
            List {
                ForEach(visibleGoals) { goal in
                    NavigationLink(value: goal.id) {
                        GoalRow(goal: goal)
                    }
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
                        .tint(.orange)
                    }
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch filter {
        case .active: "goals.empty.title"
        case .completed: "goals.empty.completed"
        case .archived: "goals.empty.archived"
        }
    }

    private var emptySymbol: String {
        switch filter {
        case .active: "target"
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
