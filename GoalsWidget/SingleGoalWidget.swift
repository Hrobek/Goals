//
//  SingleGoalWidget.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import os.log

private let debugLog = Logger(subsystem: "com.hrobek.goals.GoalsWidget", category: "SingleGoal")

// MARK: - Configuration

/// What the picker shown in "Edit Widget" offers: every active goal, by id.
struct GoalPickerEntity: AppEntity {
    let id: UUID
    let title: String
    let emoji: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Goal" }
    static var defaultQuery = GoalPickerQuery()

    var displayRepresentation: DisplayRepresentation {
        if let emoji, !emoji.isEmpty {
            DisplayRepresentation(title: "\(emoji) \(title)")
        } else {
            DisplayRepresentation(title: "\(title)")
        }
    }
}

extension GoalPickerEntity {
    init(goal: Goal) {
        id = goal.id
        title = goal.title
        emoji = goal.emoji
    }
}

struct GoalPickerQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GoalPickerEntity] {
        let ids = Set(identifiers)
        let result = WidgetGoals.fetch { ids.contains($0.id) }.map(GoalPickerEntity.init(goal:))
        debugLog.notice("entities(for:) ids=\(identifiers.map(\.uuidString).joined(separator: ","), privacy: .public) -> \(result.map(\.title).joined(separator: ","), privacy: .public)")
        return result
    }

    /// The list that pops up while editing the widget — every active goal, in the app's usual
    /// priority order.
    @MainActor
    func suggestedEntities() async throws -> [GoalPickerEntity] {
        WidgetGoals.fetch { _ in true }.map(GoalPickerEntity.init(goal:))
    }
}

struct SelectGoalIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose Goal" }
    static var description: IntentDescription { "Pick which goal this widget follows." }

    @Parameter(title: "Goal")
    var goal: GoalPickerEntity?

    init() {}
}

// MARK: - Entry

/// The button the mockup draws as an icon plus a unit-bearing label ("+ 1 km"), distinct from the
/// sign-only label the multi-goal widgets use — there's room here to spell the unit out.
struct SingleGoalAction {
    let icon: String
    let text: String
}

struct SingleGoalEntry: TimelineEntry {
    let date: Date
    let goal: GoalSnapshot?
    let action: SingleGoalAction?
    let doneToday: Int
    let totalToday: Int
    var isSignedIn = true
}

// MARK: - Provider

struct SingleGoalProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleGoalEntry {
        Self.sample
    }

    func snapshot(for configuration: SelectGoalIntent, in context: Context) async -> SingleGoalEntry {
        context.isPreview ? Self.sample : await Self.entry(for: configuration)
    }

    func timeline(for configuration: SelectGoalIntent, in context: Context) async -> Timeline<SingleGoalEntry> {
        // Same as the other widgets: nothing changes on its own until the day rolls over.
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        return Timeline(entries: [await Self.entry(for: configuration)], policy: .after(midnight))
    }

    @MainActor
    private static func entry(for configuration: SelectGoalIntent) -> SingleGoalEntry {
        debugLog.notice("entry(for:) called, configuration.goal = \(configuration.goal?.title ?? "nil", privacy: .public) (id: \(configuration.goal?.id.uuidString ?? "nil", privacy: .public))")

        guard WidgetGoals.isSignedIn else {
            return SingleGoalEntry(date: .now, goal: nil, action: nil, doneToday: 0, totalToday: 0, isSignedIn: false)
        }

        let activeGoals = WidgetGoals.fetch { _ in true }
        debugLog.notice("activeGoals = \(activeGoals.map { "\($0.title):\($0.id.uuidString)" }.joined(separator: ", "), privacy: .public)")
        // Falls back to the top-priority active goal — both for a widget that hasn't been
        // configured yet, and for one whose pinned goal has since been completed or archived.
        let selected = configuration.goal.flatMap { picked in activeGoals.first { $0.id == picked.id } } ?? activeGoals.first
        debugLog.notice("selected = \(selected?.title ?? "nil", privacy: .public)")
        let scheduledToday = GoalsProvider.todaysGoals()

        return SingleGoalEntry(
            date: .now,
            goal: selected.map(GoalSnapshot.init(goal:)),
            action: selected.flatMap(action(for:)),
            doneToday: scheduledToday.filter { $0.hasCheckIn(on: .now) }.count,
            totalToday: scheduledToday.count
        )
    }

    private static func action(for goal: Goal) -> SingleGoalAction? {
        guard goal.widgetAction == .quickAction else { return nil }
        switch goal.trackingMode {
        case .value:
            let formatted = goal.widgetQuickAmount.formatted(.number.precision(.fractionLength(0...1)))
            return SingleGoalAction(
                icon: goal.isLowerBetter ? "minus" : "plus",
                text: goal.valueWithUnit(goal.widgetQuickAmount, formattedValue: formatted)
            )
        case .milestones:
            guard let next = goal.nextMilestone else { return nil }
            return SingleGoalAction(icon: "checkmark", text: next.title)
        }
    }

    private static var sample: SingleGoalEntry {
        SingleGoalEntry(
            date: .now,
            goal: GoalSnapshot(
                id: UUID(),
                title: "Uběhnout 100 km",
                emoji: "🏃",
                colorHex: ColorPalette.defaultHex,
                progress: 0.41,
                detail: "41/100 km",
                actionLabel: "+1",
                isDoneToday: false
            ),
            action: SingleGoalAction(icon: "plus", text: "1 km"),
            doneToday: 2,
            totalToday: 4
        )
    }
}

// MARK: - View

/// One goal, chosen in "Edit Widget", drawn large: a header tallying today's overall progress,
/// then the goal's own title, progress bar, detail and one-tap action.
struct SingleGoalWidgetEntryView: View {
    var entry: SingleGoalEntry

    var body: some View {
        if !entry.isSignedIn {
            WidgetMessageView(message: "widget.notSignedIn", systemImage: "person.crop.circle.badge.questionmark")
        } else if let goal = entry.goal {
            content(for: goal)
                .widgetURL(GoalLink.url(for: goal.id))
        } else {
            WidgetMessageView(message: "widget.empty.noGoals")
        }
    }

    private func content(for goal: GoalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("today.title")
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer(minLength: 4)
                Text("\(entry.doneToday)/\(entry.totalToday)")
                    .foregroundStyle(Theme.textMuted)
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textFaint)
            .accessibilityElement(children: .combine)

            Text(goal.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.top, 12)

            ThinProgressBar(progress: goal.progress)
                .padding(.top, 9)

            Text(goal.detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.top, 7)

            Spacer(minLength: 8)

            actionRow(for: goal)
        }
    }

    @ViewBuilder
    private func actionRow(for goal: GoalSnapshot) -> some View {
        if let action = entry.action {
            Button(intent: QuickActionIntent(goalID: goal.id)) {
                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(action.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(Theme.accentText)
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.widget.quickAction \(goal.title)"))
        } else if goal.isDoneToday {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .accessibilityLabel(Text("a11y.today.done"))
        }
    }
}

// MARK: - Widget

struct SingleGoalWidget: Widget {
    let kind = "GoalsSingleWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectGoalIntent.self, provider: SingleGoalProvider()) { entry in
            SingleGoalWidgetEntryView(entry: entry)
                .containerBackground(Theme.ground, for: .widget)
                .environment(\.locale, AppLanguage.current.locale)
        }
        .configurationDisplayName("widget.single.displayName")
        .description("widget.single.description")
        .supportedFamilies([.systemSmall])
    }
}
