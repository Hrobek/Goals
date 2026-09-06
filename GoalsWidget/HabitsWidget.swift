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
    let isCheckbox: Bool
    /// "+250" style label for a value habit's tap; empty for a checkbox habit.
    let quickAddLabel: String

    let amountToday: Double
    let target: Double

    var isDone: Bool { amountToday >= target }
    var progress: Double { target > 0 ? min(amountToday / target, 1) : 0 }
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
                isCheckbox: habit.isCheckbox,
                quickAddLabel: habit.isCheckbox ? "" : "+\(habit.numberOnly(habit.widgetQuickAmount))",
                amountToday: habit.amount(on: .now),
                target: habit.targetAmount
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
        case .systemSmall: 4
        case .systemMedium: 8
        case .systemLarge: 16
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
            HabitSnapshot(id: UUID(), title: "Pít vodu", emoji: "💧", colorHex: ColorPalette.defaultHex, streak: 4, isCheckbox: false, quickAddLabel: "+250", amountToday: 1500, target: 3000),
            HabitSnapshot(id: UUID(), title: "Číst", emoji: "📖", colorHex: ColorPalette.defaultHex, streak: 12, isCheckbox: true, quickAddLabel: "", amountToday: 1, target: 1),
            HabitSnapshot(id: UUID(), title: "Protáhnout se", emoji: "🧘", colorHex: ColorPalette.defaultHex, streak: 0, isCheckbox: true, quickAddLabel: "", amountToday: 0, target: 1),
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

    // MARK: Home screen — a grid of emoji rings, nothing else

    private var columns: Int {
        family == .systemSmall ? 2 : 4
    }

    @ViewBuilder
    private var homeBody: some View {
        if !entry.isSignedIn {
            WidgetMessageView(message: "widget.notSignedIn", systemImage: "person.crop.circle.badge.questionmark")
        } else if entry.habits.isEmpty {
            WidgetMessageView(message: "habits.empty.title", systemImage: "repeat")
                .widgetURL(GoalLink.habits)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                spacing: 12
            ) {
                ForEach(entry.habits) { habit in
                    ring(for: habit)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func ring(for habit: HabitSnapshot) -> some View {
        let color = Color(hex: habit.colorHex)
        return Button(intent: HabitCheckInIntent(habitID: habit.id)) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle()
                        .fill(color.opacity(habit.isDone ? 0.28 : 0.14))
                    Circle()
                        .stroke(color.opacity(0.22), lineWidth: side * 0.1)
                    Circle()
                        .trim(from: 0, to: max(0.001, habit.progress))
                        .stroke(color, style: StrokeStyle(lineWidth: side * 0.1, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if let emoji = habit.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: side * 0.44))
                    } else {
                        Image(systemName: "repeat")
                            .font(.system(size: side * 0.34, weight: .medium))
                            .foregroundStyle(color)
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(habit.title))
        .accessibilityValue(Text(habit.isDone ? "a11y.today.done" : "a11y.today.notDone"))
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
