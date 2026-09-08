//
//  HabitsView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct HabitsView: View {
    /// Same shape as `GoalsListView.freeActiveGoalLimit`: the free tier gets a handful, Pro lifts
    /// the cap.
    static let freeHabitLimit = 3

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query private var habits: [Habit]

    let userId: UUID
    /// Owned by `RootView` so a habit-widget tap can push a habit's detail here.
    @Binding private var path: [UUID]

    @State private var editMode: EditMode = .inactive
    @State private var isShowingLimitAlert = false
    @State private var isShowingPaywall = false
    @State private var isShowingTemplatePicker = false
    @State private var pendingAdd: PendingAdd?
    @State private var addHabitConfig: AddHabitConfig?

    private enum PendingAdd {
        case blank
        case template(HabitTemplate)
    }

    private struct AddHabitConfig: Identifiable {
        let id = UUID()
        var template: HabitTemplate?
    }

    init(userId: UUID, path: Binding<[UUID]> = .constant([])) {
        self.userId = userId
        self._path = path
        _habits = Query(
            filter: #Predicate<Habit> { $0.ownerId == userId },
            sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]
        )
    }

    private var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("habits.title") {
                    IconButton(systemImage: "plus") { addHabitTapped() }
                        .accessibilityLabel(Text("a11y.addHabit"))
                }

                content
            }
            .screenGround()
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.editMode, $editMode)
            .navigationDestination(for: UUID.self) { id in
                if let habit = habits.first(where: { $0.id == id }) {
                    HabitDetailView(habit: habit)
                }
            }
            .sheet(item: $addHabitConfig) { config in
                AddEditHabitView(habit: nil, userId: userId, template: config.template)
            }
            .sheet(isPresented: $isShowingTemplatePicker, onDismiss: presentPendingAdd) {
                TemplatePickerView(mode: .habitsOnly) { selection in
                    if case .habit(let template) = selection {
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
            .alert("habits.limit.title", isPresented: $isShowingLimitAlert) {
                Button("goals.limit.upgrade") { isShowingPaywall = true }
                Button("action.ok", role: .cancel) {}
            } message: {
                Text("habits.limit.message")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if activeHabits.isEmpty {
            VStack {
                Spacer(minLength: 40)
                EmptyStateView(
                    systemImage: "repeat",
                    title: "habits.empty.title",
                    message: "habits.empty.description"
                ) {
                    Button { addHabitTapped() } label: {
                        Label("a11y.addHabit", systemImage: "plus")
                    }
                    .buttonStyle(AccentOutlineButtonStyle(height: 42))
                    .fixedSize()
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .tabBarClearance()
        } else {
            List {
                ForEach(activeHabits) { habit in
                    Button {
                        path.append(habit.id)
                    } label: {
                        HabitRow(habit: habit)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 5, leading: Theme.Space.screen, bottom: 5, trailing: Theme.Space.screen))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(habit)
                            syncReminders()
                        } label: {
                            Label("action.delete", systemImage: "trash")
                        }
                        Button {
                            habit.isArchived.toggle()
                            syncReminders()
                        } label: {
                            Label("action.archive", systemImage: "archivebox")
                        }
                        .tint(Theme.control)
                    }
                }
                .onMove(perform: move)

                if !purchaseManager.isProUnlocked {
                    ProLockedCard(title: "habits.pro.title", message: "habits.pro.locked")
                        .listRowInsets(EdgeInsets(top: 12, leading: Theme.Space.screen, bottom: 5, trailing: Theme.Space.screen))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                        .deleteDisabled(true)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(.top, 18, for: .scrollContent)
            .tabBarClearance()
        }
    }

    /// Rewrites `sortIndex` across every active habit so the new order sticks and stays dense.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = activeHabits
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortIndex = index
        }
    }

    private func addHabitTapped() {
        if !purchaseManager.isProUnlocked && activeHabits.count >= Self.freeHabitLimit {
            isShowingLimitAlert = true
            Analytics.send(.limitAlertShown)
        } else {
            isShowingTemplatePicker = true
        }
    }

    /// Runs after the template picker has fully dismissed: opens Add Habit seeded with the choice.
    /// A plain Cancel leaves `pendingAdd` nil and does nothing.
    private func presentPendingAdd() {
        guard let pendingAdd else { return }
        self.pendingAdd = nil
        switch pendingAdd {
        case .blank:
            addHabitConfig = AddHabitConfig()
        case .template(let template):
            addHabitConfig = AddHabitConfig(template: template)
        }
    }

    private func syncReminders() {
        let context = modelContext
        let userId = userId
        Task { await NotificationScheduler.syncAll(context: context, userId: userId) }
    }
}

#Preview {
    HabitsView(userId: UUID())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
