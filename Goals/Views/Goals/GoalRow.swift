//
//  GoalRow.swift
//  Goals
//

import SwiftUI
import SwiftData

/// The goal summary used by both the Today screen and the goals overview — a card rather than a
/// list row, so the two screens can be plain scrolling stacks on the app's own ground.
struct GoalRow: View {
    let goal: Goal
    /// Today's screen marks off what's already been logged; the overview shows the deadline instead.
    var showsTodayState = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped on every quick action, to trigger the confirming haptic — the goal's own state can't
    /// drive it, since navigating here also touches properties that shouldn't feel like progress.
    @State private var actionTick = 0
    /// The icon circle grows with the text, but only so far: left unbounded it triples at
    /// accessibility sizes and squeezes the title into a column narrow enough to break words
    /// in half. Decoration yields to the words.
    @ScaledMetric(relativeTo: .headline) private var scaledIconSize: CGFloat = 40
    private var iconSize: CGFloat { min(scaledIconSize, 52) }

    private var isDoneToday: Bool {
        goal.hasCheckIn(on: .now)
    }

    /// A goal that's finished with — done for today, or done altogether — steps back towards the
    /// ground instead of competing with what still needs doing.
    private var isSettled: Bool {
        showsTodayState ? isDoneToday : goal.isCompleted
    }

    /// At accessibility text sizes the caption line stops fitting side by side — "Every day"
    /// truncates to "Ev…" — so it stacks instead.
    private var captionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GoalBadge(emoji: goal.emoji, size: iconSize, muted: isSettled)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(goal.title)
                        .font(Theme.Typo.rowTitle)
                        .foregroundStyle(Theme.text)
                        .strikethrough(isSettled, color: Theme.textGhost)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    Spacer(minLength: 4)
                    trailingMark
                }

                ThinBar(progress: goal.progressFraction, color: isSettled ? Theme.accentSpent : Theme.accent)
                    .padding(.top, 9)
                    .padding(.bottom, 8)

                captionLayout {
                    Text(valueText)
                        .font(Theme.Typo.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textStrong)
                    if showsTodayState {
                        Text(Recurrence.localizedSummary(for: goal))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    } else {
                        if let deadline = goal.deadline {
                            // A Spacer would push vertically once the layout stacks, tearing the
                            // two captions apart down the row.
                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer(minLength: 8)
                            }
                            Text(deadline, style: .date)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                }

                if showsTodayState {
                    todayQuickContent
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(isSettled ? Theme.surfaceMuted : Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isSettled ? Theme.hairlineSoft : Theme.hairline, lineWidth: 1)
        }
        .opacity(isSettled ? 0.72 : 1)
        .sensoryFeedback(.selection, trigger: actionTick)
        // Read as one sentence. Left to itself VoiceOver walks the row piece by piece — emoji,
        // title, "56 percent", the bare "12/30 km" — and the state icon, being decoration, says
        // nothing at all about whether today is done.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Today: whether it's ticked off. Overview: how much it matters, or that it's finished.
    @ViewBuilder
    private var trailingMark: some View {
        if showsTodayState {
            Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isDoneToday ? Theme.accent : Theme.textGhost)
        } else if goal.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
        } else if goal.priority == .high {
            AccentPill(text: goal.priority.localizedName)
        } else {
            NeutralPill(text: goal.priority.localizedName)
        }
    }

    private var accessibilityLabel: Text {
        var parts = [goal.title, spokenValueText]
        if showsTodayState {
            parts.append(String(localized: isDoneToday ? "a11y.today.done" : "a11y.today.notDone",
                                bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale))
            parts.append(Recurrence.localizedSummary(for: goal))
        } else {
            if goal.isCompleted {
                parts.append(String(localized: "a11y.goal.completed", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale))
            }
            parts.append(goal.priority.localizedName)
            if let deadline = goal.deadline {
                parts.append(deadline.formatted(date: .abbreviated, time: .omitted))
            }
        }
        return Text(parts.joined(separator: ", "))
    }

    /// The row's own way to make progress without leaving Today — a quick-add chip for value
    /// goals, or the next couple of open milestones as plain checkboxes for milestone goals.
    @ViewBuilder
    private var todayQuickContent: some View {
        switch goal.trackingMode {
        case .value:
            // Stays put even once today is checked off — logging more water past the target is
            // still a normal thing to want to do.
            quickAddButton
        case .milestones:
            if !upcomingMilestones.isEmpty {
                milestoneChecklist
            }
        }
    }

    private var quickAddButton: some View {
        Button {
            ProgressLogger.performQuickAction(on: goal, in: modelContext)
            actionTick += 1
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(goal.valueWithUnit(goal.widgetQuickAmount, formattedValue: formatted(goal.widgetQuickAmount)))
                    .font(Theme.Typo.captionEmphasis)
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Theme.accentWell, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.accentWellBorder, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .accessibilityLabel(Text("a11y.quickAdd \(goal.valueWithUnit(goal.widgetQuickAmount, formattedValue: formatted(goal.widgetQuickAmount)))"))
    }

    /// Up to two nearest open milestones — just the one left, if only one remains.
    private var upcomingMilestones: [Milestone] {
        Array(goal.sortedMilestones.filter { !$0.isCompleted }.prefix(2))
    }

    private var milestoneChecklist: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(upcomingMilestones) { milestone in
                Button {
                    ProgressLogger.toggleMilestone(milestone, on: goal, in: modelContext)
                    actionTick += 1
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textGhost)
                        Text(milestone.title)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.textStrong)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(milestone.title))
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(Text("a11y.milestone.todo"))
            }
        }
        .padding(.top, 8)
    }

    /// "12/30 km" is the right shape for the eye and the wrong one for the ear — the slash comes
    /// out as punctuation. Spoken, it becomes "12 of 30 km".
    private var spokenValueText: String {
        let current: String
        let target: String
        switch goal.trackingMode {
        case .value:
            current = formatted(goal.currentValue)
            target = goal.valueWithUnit(goal.targetValue, formattedValue: formatted(goal.targetValue))
        case .milestones:
            current = "\(goal.completedMilestoneCount)"
            target = String(localized: "milestone.unit.count \(goal.milestones.count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        }
        return String(localized: "a11y.progress \(current) \(target)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
    }

    private var valueText: String {
        switch goal.trackingMode {
        case .value:
            "\(formatted(goal.currentValue))/\(goal.valueWithUnit(goal.targetValue, formattedValue: formatted(goal.targetValue)))"
        case .milestones:
            "\(goal.completedMilestoneCount)/"
                + String(localized: "milestone.unit.count \(goal.milestones.count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
