//
//  HabitsWidget.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Entry

/// A plain value copied out of SwiftData — the timeline outlives the fetch.
struct HabitSnapshot: Identifiable, Hashable {
    let id: UUID
    let title: String
    let emoji: String?
    let colorHex: String
    let streak: Int
    let countToday: Int
    let dailyTarget: Int

    var isDone: Bool { countToday >= dailyTarget }
    var progress: Double { dailyTarget > 0 ? min(Double(countToday) / Double(dailyTarget), 1) : 0 }
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
    let doneToday: Int
    let totalToday: Int
    var isSignedIn = true
}

// MARK: - Provider

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: .now, habits: Self.sample, doneToday: 1, totalToday: 3)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        completion(context.isPreview
            ? HabitsEntry(date: .now, habits: Self.sample, doneToday: 1, totalToday: 3)
            : Self.entry(for: context.family))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [Self.entry(for: context.family)], policy: .after(midnight)))
    }

    @MainActor
    private static func entry(for family: WidgetFamily) -> HabitsEntry {
        guard WidgetGoals.isSignedIn else {
            return HabitsEntry(date: .now, habits: [], doneToday: 0, totalToday: 0, isSignedIn: false)
        }

        let today = todaysHabits()
        let limit = rowLimit(for: family)
        let snapshots = today.prefix(limit).map { habit in
            HabitSnapshot(
                id: habit.id,
                title: habit.title,
                emoji: habit.emoji,
                colorHex: habit.colorHex,
                streak: habit.currentStreak,
                countToday: habit.count(on: .now),
                dailyTarget: max(habit.dailyTarget, 1)
            )
        }
        return HabitsEntry(
            date: .now,
            habits: Array(snapshots),
            doneToday: today.filter { $0.isDone(on: .now) }.count,
            totalToday: today.count
        )
    }

    private static func rowLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        case .systemLarge: 8
        default: 1
        }
    }

    /// Active habits scheduled for today, done ones sinking to the bottom, otherwise the user's
    /// own order.
    @MainActor
    static func todaysHabits() -> [Habit] {
        guard let userId = CurrentUser.currentUserId else { return [] }
        let context = SharedStore.container.mainContext
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId == userId })
        let habits = (try? context.fetch(descriptor)) ?? []

        return habits
            .filter { !$0.isArchived && $0.isScheduledToday() }
            .sorted { lhs, rhs in
                let lhsDone = lhs.isDone(on: .now)
                let rhsDone = rhs.isDone(on: .now)
                if lhsDone != rhsDone { return !lhsDone }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    private static var sample: [HabitSnapshot] {
        [
            HabitSnapshot(id: UUID(), title: "Pít vodu", emoji: "💧", colorHex: ColorPalette.defaultHex, streak: 4, countToday: 1, dailyTarget: 3),
            HabitSnapshot(id: UUID(), title: "Číst", emoji: "📖", colorHex: ColorPalette.defaultHex, streak: 12, countToday: 1, dailyTarget: 1),
            HabitSnapshot(id: UUID(), title: "Protáhnout se", emoji: "🧘", colorHex: ColorPalette.defaultHex, streak: 0, countToday: 0, dailyTarget: 1),
        ]
    }
}

// MARK: - View

struct HabitsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: HabitsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        default:
            homeBody
        }
    }

    // MARK: Home screen

    @ViewBuilder
    private var homeBody: some View {
        if !entry.isSignedIn {
            WidgetMessageView(message: "widget.notSignedIn", systemImage: "person.crop.circle.badge.questionmark")
        } else if entry.habits.isEmpty {
            WidgetMessageView(message: "habits.empty.title", systemImage: "repeat")
                .widgetURL(GoalLink.habits)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("tab.habits")
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer(minLength: 4)
                    Text("\(entry.doneToday)/\(entry.totalToday)")
                        .foregroundStyle(Theme.textMuted)
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textFaint)

                VStack(spacing: 7) {
                    ForEach(entry.habits) { habit in
                        row(for: habit)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 0)
            }
        }
    }

    private func row(for habit: HabitSnapshot) -> some View {
        HStack(spacing: 8) {
            Link(destination: GoalLink.habit(for: habit.id)) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: habit.colorHex).opacity(0.20))
                        if let emoji = habit.emoji, !emoji.isEmpty {
                            Text(emoji).font(.system(size: 13))
                        } else {
                            Image(systemName: "repeat")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: habit.colorHex))
                        }
                    }
                    .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if habit.streak > 0 {
                            Text("\(habit.streak)")
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }

            Button(intent: HabitCheckInIntent(habitID: habit.id)) {
                ZStack {
                    Circle()
                        .fill(habit.isDone ? Color(hex: habit.colorHex) : Color.clear)
                        .overlay {
                            Circle().strokeBorder(habit.isDone ? Color(hex: habit.colorHex) : Theme.textGhost, lineWidth: 1.5)
                        }
                        .frame(width: 24, height: 24)
                    if habit.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    } else if habit.dailyTarget > 1 {
                        Text("\(habit.countToday)")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textStrong)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.habit.toggleToday"))
        }
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var accessoryCircular: some View {
        if let habit = entry.habits.first {
            Gauge(value: habit.progress) {
                EmptyView()
            } currentValueLabel: {
                if let emoji = habit.emoji, !emoji.isEmpty {
                    Text(emoji)
                } else {
                    Image(systemName: "repeat")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(GoalLink.habit(for: habit.id))
            .accessibilityLabel(Text(habit.title))
        } else {
            Image(systemName: "repeat").font(.title3)
        }
    }

    @ViewBuilder
    private var accessoryRectangular: some View {
        if let habit = entry.habits.first {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let emoji = habit.emoji, !emoji.isEmpty { Text(emoji) }
                        Text(habit.title).font(.headline).lineLimit(1)
                    }
                    Gauge(value: habit.progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(habit.title))

                Button(intent: HabitCheckInIntent(habitID: habit.id)) {
                    Image(systemName: habit.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("a11y.habit.toggleToday"))
            }
        } else {
            Text("habits.empty.title").font(.caption)
        }
    }
}

// MARK: - Widget

struct HabitsWidget: Widget {
    let kind = "GoalsHabitsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            HabitsWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetContainerBackground() }
                .environment(\.locale, AppLanguage.current.locale)
        }
        .configurationDisplayName("widget.habits.displayName")
        .description("widget.habits.description")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
