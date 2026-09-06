//
//  HabitRow.swift
//  Goals
//

import SwiftUI
import SwiftData

/// A habit as a card: emoji, name, schedule, running streak, and a check-off control for today.
/// Tapping the card opens the detail; tapping the control on the right logs today without leaving
/// the list.
struct HabitRow: View {
    let habit: Habit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped on every check-off so the confirming haptic has a trigger the habit's own state
    /// can't accidentally supply.
    @State private var actionTick = 0

    @ScaledMetric(relativeTo: .headline) private var scaledIconSize: CGFloat = 40
    private var iconSize: CGFloat { min(scaledIconSize, 52) }

    private var doneToday: Bool { habit.isDone(on: .now) }
    private var streak: Int { habit.currentStreak }
    private var tint: Color { Color(hex: habit.colorHex) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            badge

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(Theme.Typo.rowTitle)
                    .foregroundStyle(Theme.text)
                    .strikethrough(doneToday, color: Theme.textGhost)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

                HStack(spacing: 8) {
                    if !habit.isCheckbox {
                        Text(habit.progressText())
                            .font(Theme.Typo.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textStrong)
                    }
                    Text(Recurrence.localizedSummary(for: habit))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                    if streak > 0 {
                        Label {
                            Text("\(streak)")
                                .font(Theme.Typo.caption)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "flame.fill").font(.system(size: 10))
                        }
                        .foregroundStyle(tint)
                    }
                }
            }

            Spacer(minLength: 8)

            checkControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        // The card carries the habit's colour — a faint wash on the surface and a matching hairline.
        .background(tint.opacity(doneToday ? 0.06 : 0.12), in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(tint.opacity(doneToday ? 0.16 : 0.3), lineWidth: 1)
        }
        .opacity(doneToday ? 0.82 : 1)
        .sensoryFeedback(.success, trigger: actionTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(doneToday ? "a11y.today.done" : "a11y.today.notDone"))
        .accessibilityAction(named: Text("a11y.habit.toggleToday")) {
            if habit.widgetAction == .complete {
                HabitLogger.completeOccurrence(habit, in: modelContext)
            } else if habit.isCheckbox {
                HabitLogger.toggleToday(habit, in: modelContext)
            } else if habit.hasUnit {
                HabitLogger.addQuick(habit, in: modelContext)
            } else {
                HabitLogger.adjust(habit, by: 1, in: modelContext)
            }
            actionTick += 1
        }
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(doneToday ? 0.14 : 0.20))
                .overlay { Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1) }
            if let emoji = habit.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: iconSize * 0.47))
            } else {
                Image(systemName: "repeat")
                    .font(.system(size: iconSize * 0.4, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: iconSize, height: iconSize)
    }

    /// Shapes: a "complete" tick that finishes the occurrence, a tick circle (checkbox), an "n/N"
    /// counter that +1s per tap (a "times" habit done several times a day), or a "+step" chip
    /// (a unit habit).
    @ViewBuilder
    private var checkControl: some View {
        if habit.widgetAction == .complete {
            Button {
                HabitLogger.completeOccurrence(habit, in: modelContext)
                actionTick += 1
            } label: {
                circle {
                    if doneToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.habit.toggleToday"))
        } else if habit.isCheckbox {
            Button { toggle() } label: {
                circle {
                    if doneToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if !habit.hasUnit {
            Button {
                HabitLogger.adjust(habit, by: 1, in: modelContext)
                actionTick += 1
            } label: {
                circle {
                    if doneToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    } else {
                        Text(habit.progressText())
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textStrong)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.habit.toggleToday"))
        } else {
            Button {
                HabitLogger.addQuick(habit, in: modelContext)
                actionTick += 1
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: doneToday ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(habit.numberOnly(habit.widgetQuickAmount))
                        .font(Theme.Typo.captionEmphasis)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .foregroundStyle(doneToday ? Theme.onAccent : tint)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(doneToday ? tint : tint.opacity(0.14), in: .capsule)
                .overlay { Capsule().strokeBorder(tint.opacity(doneToday ? 0 : 0.4), lineWidth: 1) }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.quickAdd \(habit.quickAddLabel(habit.widgetQuickAmount))"))
        }
    }

    private func circle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Circle()
                .fill(doneToday ? tint : Color.clear)
                .overlay { Circle().strokeBorder(doneToday ? tint : Theme.textGhost, lineWidth: 1.5) }
                .frame(width: 30, height: 30)
            content()
        }
        .frame(width: 44, height: 44)
        .contentShape(.rect)
    }

    private func toggle() {
        HabitLogger.toggleToday(habit, in: modelContext)
        actionTick += 1
    }

    private var accessibilityLabel: Text {
        var parts = [habit.title, Recurrence.localizedSummary(for: habit)]
        if streak > 0 {
            parts.append(String(localized: "a11y.streak.days \(streak)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale))
        }
        return Text(parts.joined(separator: ", "))
    }
}
