//
//  GoalsWidget.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Entry

/// A plain value copied out of SwiftData: the timeline outlives the fetch, so the views must not
/// hold on to model objects.
struct GoalSnapshot: Identifiable, Hashable {
    let id: UUID
    let title: String
    let emoji: String?
    let colorHex: String
    let progress: Double
    let detail: String
    /// `nil` when the goal is set to just open in the app.
    let actionLabel: String?
    let isDoneToday: Bool
}

struct GoalsEntry: TimelineEntry {
    let date: Date
    let goals: [GoalSnapshot]
}

// MARK: - Provider

struct GoalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalsEntry {
        GoalsEntry(date: .now, goals: [Self.sample])
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (GoalsEntry) -> Void) {
        let limit = Self.limit(for: context.family)
        completion(GoalsEntry(date: .now, goals: context.isPreview ? [Self.sample] : Self.todaysGoals(limit: limit)))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalsEntry>) -> Void) {
        let entry = GoalsEntry(date: .now, goals: Self.todaysGoals(limit: Self.limit(for: context.family)))
        // Nothing changes on its own until the day rolls over — the app and the button push
        // updates themselves.
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    /// How many rows fit each widget size, tuned to the compact row height used below.
    private static func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        case .systemLarge: 9
        default: 3
        }
    }

    @MainActor
    private static func todaysGoals(limit: Int) -> [GoalSnapshot] {
        let context = SharedStore.container.mainContext
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []

        return goals
            .filter { $0.status == .active && $0.isScheduledToday() }
            .sorted { lhs, rhs in
                let lhsDone = lhs.hasCheckIn(on: .now)
                let rhsDone = rhs.hasCheckIn(on: .now)
                if lhsDone != rhsDone { return !lhsDone }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map(GoalSnapshot.init(goal:))
    }

    private static var sample: GoalSnapshot {
        GoalSnapshot(
            id: UUID(),
            title: "Uběhnout 100 km",
            emoji: "🏃",
            colorHex: ColorPalette.defaultHex,
            progress: 0.4,
            detail: "40/100 km",
            actionLabel: "+5",
            isDoneToday: false
        )
    }
}

extension GoalSnapshot {
    @MainActor
    init(goal: Goal) {
        let showsAction = goal.widgetAction == .quickAction

        switch goal.trackingMode {
        case .value:
            let sign = goal.isLowerBetter ? "−" : "+"
            detail = "\(Self.formatted(goal.currentValue))/\(Self.formatted(goal.targetValue)) \(goal.unitDisplayText)"
            actionLabel = showsAction ? sign + Self.formatted(goal.widgetQuickAmount) : nil
        case .milestones:
            let unit = String(localized: "milestone.unit", defaultValue: "milestones", bundle: AppLanguage.currentBundle)
            detail = "\(goal.completedMilestoneCount)/\(goal.milestones.count) \(unit)"
            actionLabel = showsAction ? goal.nextMilestone?.title : nil
        }

        id = goal.id
        title = goal.title
        emoji = goal.emoji
        colorHex = goal.colorHex
        progress = goal.progressFraction
        isDoneToday = goal.hasCheckIn(on: .now)
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Views

/// One compact row per goal at every widget size — a big single-goal card looks nice but shows
/// only one goal even where a small widget has room for two or three.
struct GoalsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GoalsEntry

    var body: some View {
        if entry.goals.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: family == .systemSmall ? 4 : 6) {
                ForEach(entry.goals) { goal in
                    GoalRowView(goal: goal)
                    // Skipped on the small widget: every point of height there goes to fitting
                    // one more goal instead.
                    if family != .systemSmall, goal.id != entry.goals.last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(entry.goals.count == 1 ? GoalLink.url(for: entry.goals[0].id) : nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("today.empty.title")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// One line per goal — title, thin progress bar and detail stacked tightly so the medium and
/// large widgets can fit several goals instead of two or three.
///
/// The small widget is narrow enough that title and detail sharing a line truncates the title
/// almost immediately, so there it drops to two lines instead: title on its own, detail and the
/// progress bar together underneath. Slightly taller per row, but nothing gets cut off.
private struct GoalRowView: View {
    @Environment(\.widgetFamily) private var family
    let goal: GoalSnapshot

    private var isCompact: Bool { family == .systemSmall }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Link(destination: GoalLink.url(for: goal.id)) {
                HStack(spacing: isCompact ? 5 : 6) {
                    Text(goal.emoji ?? "🎯")
                        .font(isCompact ? .caption2 : .caption)
                    if isCompact {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                ThinProgressBar(progress: goal.progress, color: Color(hex: goal.colorHex))
                                Text(goal.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(goal.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(goal.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            ThinProgressBar(progress: goal.progress, color: Color(hex: goal.colorHex))
                        }
                    }
                }
                .contentShape(.rect)
            }

            if let label = goal.actionLabel {
                QuickActionButton(goalID: goal.id, label: label, colorHex: goal.colorHex, width: isCompact ? 32 : 42)
            } else if goal.isDoneToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }
}

/// A hand-drawn bar instead of `ProgressView`, which won't go below its platform-defined
/// minimum height — this one can be as thin as the compact row needs.
private struct ThinProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.2))
                Capsule().fill(color).frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

private struct QuickActionButton: View {
    let goalID: UUID
    let label: String
    let colorHex: String
    let width: CGFloat

    var body: some View {
        Button(intent: QuickActionIntent(goalID: goalID)) {
            Text(label)
                .font(.system(size: width < 40 ? 9 : 11).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: width)
                .padding(.vertical, 4)
                .background(Color(hex: colorHex).opacity(0.2))
                .foregroundStyle(Color(hex: colorHex))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

enum GoalLink {
    static func url(for id: UUID) -> URL {
        URL(string: "goals://goal/\(id.uuidString)") ?? URL(string: "goals://")!
    }
}

// MARK: - Widget

struct GoalsWidget: Widget {
    let kind = "GoalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoalsProvider()) { entry in
            GoalsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.displayName")
        .description("widget.description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
