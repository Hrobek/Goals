//
//  GoalRow.swift
//  Goals
//

import SwiftUI

/// The goal summary used by both the Today screen and the goals overview — a card rather than a
/// list row, so the two screens can be plain scrolling stacks on the app's own ground.
struct GoalRow: View {
    let goal: Goal
    /// Today's screen marks off what's already been logged; the overview shows the deadline instead.
    var showsTodayState = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
