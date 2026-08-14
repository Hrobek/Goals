//
//  TodayView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// Home screen: only the goals that are actually due today. A Mondays-only goal stays out of
/// the way for the rest of the week.
struct TodayView: View {
    @Binding var path: NavigationPath

    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    private var todaysGoals: [Goal] {
        goals
            .filter { $0.status == .active && $0.isScheduledToday() }
            .sorted { lhs, rhs in
                let lhsDone = lhs.hasCheckIn(on: .now)
                let rhsDone = rhs.hasCheckIn(on: .now)
                if lhsDone != rhsDone { return !lhsDone }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var doneCount: Int {
        todaysGoals.filter { $0.hasCheckIn(on: .now) }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if todaysGoals.isEmpty {
                    ContentUnavailableView {
                        Label("today.empty.title", systemImage: "checkmark.circle")
                    } description: {
                        Text("today.empty.description")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("today.progress \(doneCount) \(todaysGoals.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 4)

                        List {
                            ForEach(todaysGoals) { goal in
                                NavigationLink(value: goal.id) {
                                    GoalRow(goal: goal, showsTodayState: true)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("today.title")
            .navigationDestination(for: UUID.self) { id in
                if let goal = goals.first(where: { $0.id == id }) {
                    GoalDetailView(goal: goal)
                }
            }
        }
    }
}

#Preview {
    TodayView(path: .constant(NavigationPath()))
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
