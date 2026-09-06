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
        Self.sampleEntry(for: context.family)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        completion(context.isPreview ? Self.sampleEntry(for: context.family) : Self.entry(for: context.family))
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
        case .systemSmall: 4     // 2 per row, 2 rows
        case .systemMedium: 10   // 5 per row, 2 rows
        case .systemLarge: 25    // 5 per row, ~5 rows
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
        func s(_ title: String, _ emoji: String, _ hex: String, _ amt: Double, _ tgt: Double) -> HabitSnapshot {
            HabitSnapshot(id: UUID(), title: title, emoji: emoji, colorHex: hex, streak: 3,
                          isCheckbox: tgt == 1, quickAddLabel: "", amountToday: amt, target: tgt)
        }
        return [
            s("Voda", "💧", "#54A0FF", 1500, 3000),
            s("Číst", "📖", "#1DD1A1", 1, 1),
            s("Meditace", "🧘", "#FECA57", 0, 1),
            s("Kroky", "🚶", "#FF9F43", 7000, 10000),
            s("Vitamíny", "💊", "#EE5A9E", 1, 1),
            s("Kliky", "💪", "#5F27CD", 20, 50),
        ]
    }

    /// Gallery/placeholder entry — the sample list trimmed to what the family actually shows,
    /// so the small preview isn't crammed with more rings than a placed widget would hold.
    private static func sampleEntry(for family: WidgetFamily) -> HabitsEntry {
        let capped = Array(sample.prefix(rowLimit(for: family)))
        return HabitsEntry(
            date: .now,
            habits: capped,
            doneToday: capped.filter(\.isDone).count,
            totalToday: capped.count
        )
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

    /// Rings-per-row: 2 on the small, 5 on the medium. They flex to fill the width; on the medium
    /// they land proportionally smaller, which is fine.
    private var columnCount: Int { family == .systemSmall ? 2 : 5 }

    /// One value used for the outer inset AND the gaps between rings, so every margin — top,
    /// bottom, left, right, and between — reads the same. A touch tighter on the small.
    private var gap: CGFloat { family == .systemSmall ? 12 : 14 }

    @ViewBuilder
    private var homeBody: some View {
        if !entry.isSignedIn {
            WidgetMessageView(message: "widget.notSignedIn", systemImage: "person.crop.circle.badge.questionmark")
        } else if entry.habits.isEmpty {
            WidgetMessageView(message: "habits.empty.title", systemImage: "repeat")
                .widgetURL(GoalLink.habits)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columnCount),
                spacing: gap
            ) {
                ForEach(entry.habits) { habit in
                    ring(for: habit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(gap)
        }
    }

    private func ring(for habit: HabitSnapshot) -> some View {
        Button(intent: HabitCheckInIntent(habitID: habit.id)) {
            RingShape(habit: habit, family: family)
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

/// One emoji ring. A plain, fixed-shape view with no `GeometryReader` — that combination as a
/// `Button` label was swallowing taps in the widget.
private struct RingShape: View {
    let habit: HabitSnapshot
    let family: WidgetFamily

    private var color: Color { Color(hex: habit.colorHex) }
    private var lineWidth: CGFloat { family == .systemSmall ? 6 : 5 }
    private var glyphSize: CGFloat { family == .systemSmall ? 24 : 20 }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(habit.isDone ? 0.28 : 0.14))
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, habit.progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let emoji = habit.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: glyphSize))
            } else {
                Image(systemName: "repeat")
                    .font(.system(size: glyphSize * 0.8, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(.circle)
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
        // The grid runs to the edges; the default ~16pt content margin would waste that space.
        .contentMarginsDisabled()
    }
}
