//
//  TodayView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// Home screen: only the goals that are actually due today. A Mondays-only goal stays out of
/// the way for the rest of the week.
/// Wraps a habit id for navigation, kept distinct from a bare `UUID` so the Today stack can carry
/// both goal and habit destinations without them colliding.
struct HabitDestination: Hashable {
    let id: UUID
}

struct TodayView: View {
    @Binding var path: NavigationPath

    @Query private var goals: [Goal]
    @Query private var habits: [Habit]

    /// Which day the screen is showing. Defaults to today; the day strip pages it back so a
    /// check-off forgotten yesterday can still be logged on the right date. Never goes past today.
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    /// How far back the day strip reaches. Enough to catch up after a trip, not so far it turns
    /// into a data-entry sheet.
    private let daysBack = 90

    private let calendar = Calendar.current

    init(userId: UUID, path: Binding<NavigationPath>) {
        self._path = path
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId }, sort: [SortDescriptor(\Habit.sortIndex)])
    }

    private var isViewingToday: Bool { calendar.isDateInToday(selectedDate) }

    /// Read once per render — paused goals and habits drop off Today for days inside the window.
    private var vacation: Vacation { Vacation.current() }

    private var todaysGoals: [Goal] {
        goals
            .filter { $0.status == .active && $0.isScheduledToday(date: selectedDate) && !vacation.pauses($0.id, on: selectedDate) }
            .sorted { lhs, rhs in
                let lhsDone = lhs.hasCheckIn(on: selectedDate)
                let rhsDone = rhs.hasCheckIn(on: selectedDate)
                if lhsDone != rhsDone { return !lhsDone }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var todaysHabits: [Habit] {
        habits
            .filter { !$0.isArchived && $0.isScheduledToday(date: selectedDate) && !vacation.pauses($0.id, on: selectedDate) }
            .sorted { lhs, rhs in
                let lhsDone = lhs.isDone(on: selectedDate)
                let rhsDone = rhs.isDone(on: selectedDate)
                if lhsDone != rhsDone { return !lhsDone }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    private var isEmpty: Bool { todaysGoals.isEmpty && todaysHabits.isEmpty }

    private var totalCount: Int { todaysGoals.count + todaysHabits.count }

    private var doneCount: Int {
        todaysGoals.filter { $0.hasCheckIn(on: selectedDate) }.count
            + todaysHabits.filter { $0.isDone(on: selectedDate) }.count
    }

    /// The longest run going right now across every active goal and habit — the one number worth
    /// carrying in the header, since it's what a missed day costs.
    private var bestStreak: Int {
        let goalStreaks = goals.filter { $0.status == .active }.map { StreakCalculator.currentStreak(for: $0) }
        let habitStreaks = habits.filter { !$0.isArchived }.map(\.currentStreak)
        return (goalStreaks + habitStreaks).max() ?? 0
    }

    private var todayText: String {
        selectedDate.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.current.locale)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    DayStrip(selection: $selectedDate, daysBack: daysBack)
                        .padding(.top, 16)

                    if isEmpty {
                        EmptyStateView(
                            systemImage: "moon.stars",
                            title: "today.empty.title",
                            message: "today.empty.description"
                        )
                        .padding(.top, 70)
                    } else {
                        summary
                        if !todaysGoals.isEmpty {
                            section(title: "tab.goals") {
                                // The heading mirrors the tab bar, where Goals carries the app's
                                // own mark rather than an SF Symbol.
                                GoalsMark(size: 13, tone: .mono, color: Theme.textFaint)
                            } content: {
                                goalList
                            }
                        }
                        if !todaysHabits.isEmpty {
                            section(title: "tab.habits") {
                                Image(systemName: "repeat")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textFaint)
                            } content: {
                                habitList
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .tabBarClearance()
            .screenGround()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let goal = goals.first(where: { $0.id == id }) {
                    GoalDetailView(goal: goal)
                }
            }
            .navigationDestination(for: HabitDestination.self) { destination in
                if let habit = habits.first(where: { $0.id == destination.id }) {
                    HabitDetailView(habit: habit)
                }
            }
        }
    }

    /// A group heading — the one visual cue that separates "goals due today" from "habits due
    /// today" on a screen that otherwise stacks both as cards.
    @ViewBuilder
    private func section<Icon: View, Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            icon()
            Text(title)
                .font(Theme.Typo.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 26)

        content()
    }

    private var header: some View {
        ScreenTitle("today.title", subtitle: todayText) {
            if isViewingToday {
                if bestStreak > 0 {
                    streakPill
                }
            } else {
                backToTodayButton
            }
        }
    }

    /// Shown only while the strip is parked on an earlier day — the one tap back to the default.
    private var backToTodayButton: some View {
        Button {
            withAnimation { selectedDate = calendar.startOfDay(for: .now) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .semibold))
                Text("today.jumpToToday")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Theme.accentWell, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.accentWellBorder, lineWidth: 1) }
            .foregroundStyle(Theme.accentWellText)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var streakPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill").font(.system(size: 13))
            Text("\(bestStreak)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Theme.accentWell, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.accentWellBorder, lineWidth: 1) }
        .foregroundStyle(Theme.accentWellText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.currentStreak"))
        .accessibilityValue(Text("\(bestStreak)"))
    }

    /// How much of today is behind you: the count, then one segment per goal due.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(doneCount)")
                    .font(.system(size: 40, weight: .medium))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(verbatim: "/ \(totalCount)")
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textFaint)
            }

            HStack(spacing: 6) {
                ForEach(0..<max(totalCount, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < doneCount ? Theme.accent : Theme.track)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("today.progress \(doneCount) \(totalCount)"))
    }

    private var goalList: some View {
        LazyVStack(spacing: Theme.Space.card) {
            ForEach(todaysGoals) { goal in
                NavigationLink(value: goal.id) {
                    GoalRow(goal: goal, showsTodayState: true, referenceDate: selectedDate)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 14)
    }

    private var habitList: some View {
        LazyVStack(spacing: Theme.Space.card) {
            ForEach(todaysHabits) { habit in
                NavigationLink(value: HabitDestination(id: habit.id)) {
                    HabitRow(habit: habit, referenceDate: selectedDate)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 14)
    }
}

/// A horizontal run of day pills ending on today, scrolled to the right. Tapping one moves the
/// Today screen to that date so a forgotten check-off lands on the day it actually happened;
/// there's nothing past today to tap.
private struct DayStrip: View {
    @Binding var selection: Date
    let daysBack: Int

    private let calendar = Calendar.current

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (0...daysBack)
            .reversed()
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        pill(for: day).id(day)
                    }
                }
            }
            // A scroll-content margin rather than plain padding, so the resting position at the
            // trailing end leaves the selected day the same gap you see when you drag the strip
            // past its end — instead of pinning it flush against the edge.
            .contentMargins(.horizontal, Theme.Space.screen, for: .scrollContent)
            .defaultScrollAnchor(.trailing)
            .onChange(of: selection) { _, new in
                withAnimation { proxy.scrollTo(calendar.startOfDay(for: new), anchor: .center) }
            }
        }
    }

    private func pill(for day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        return Button {
            withAnimation { selection = day }
        } label: {
            VStack(spacing: 3) {
                Text(Recurrence.weekdayAbbreviation(calendar.component(.weekday, from: day)))
                    .font(.system(size: 10, weight: .medium))
                    .textCase(.uppercase)
                Text(day.formatted(.dateTime.day().locale(AppLanguage.current.locale)))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Theme.onAccent : (isToday ? Theme.accent : Theme.textFaint))
            .frame(width: 44, height: 52)
            .background(isSelected ? Theme.accent : Theme.surface, in: .rect(cornerRadius: Theme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(
                        isToday && !isSelected ? Theme.accent.opacity(0.5) : Theme.hairline,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.current.locale)
        )))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    TodayView(userId: UUID(), path: .constant(NavigationPath()))
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
