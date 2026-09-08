//
//  WatchTodayRow.swift
//  GoalsWatch
//

import SwiftUI

/// One goal or habit due today. Emoji (or the app mark) on the left, title and streak in the
/// middle, a progress ring on the right that fills as the day gets done.
struct WatchTodayRow: View {
    let item: TodaySchedule.Item

    private var color: Color { Color(hex: item.colorHex) }

    var body: some View {
        HStack(spacing: 10) {
            identity
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                if item.streak > 0 {
                    Label("\(item.streak)", systemImage: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.faint)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer(minLength: 4)

            WatchProgressRing(fraction: item.fraction, isDone: item.isDone, color: color)
                .frame(width: 24, height: 24)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(item.isDone ? 0.05 : 0.10), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text(item.isDone ? "a11y.today.done" : "a11y.today.notDone"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var identity: some View {
        if let emoji = item.emoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 19))
        } else {
            GoalsMark(size: 22, tone: .mono, color: color)
        }
    }
}

/// A thin circular progress indicator. A filled check when the day is done.
struct WatchProgressRing: View {
    let fraction: Double
    let isDone: Bool
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
            }
        }
    }
}
