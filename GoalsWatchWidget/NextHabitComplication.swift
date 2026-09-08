//
//  NextHabitComplication.swift
//  GoalsWatchWidget
//
//  The next habit not yet done today, with a check-off button right on the watch face.
//

import WidgetKit
import SwiftUI
import AppIntents

struct NextHabitComplication: Widget {
    let kind = "GoalsWatchNextHabit"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayComplicationProvider()) { entry in
            NextHabitView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("watch.complication.next.name")
        .description("watch.complication.next.description")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct NextHabitView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayComplicationEntry

    private var tint: Color { Color(hex: entry.nextColorHex) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let id = entry.nextHabitID {
            Button(intent: HabitCheckInIntent(habitID: id)) {
                ZStack {
                    AccessoryWidgetBackground()
                    Gauge(value: entry.nextFraction) {
                        glyph
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.allDone ? "checkmark" : "repeat")
            }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let id = entry.nextHabitID, let title = entry.nextTitle {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("watch.complication.next.label")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(entry.nextEmoji ?? "") \(title)")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(intent: HabitCheckInIntent(habitID: id)) {
                    Image(systemName: "circle")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.plain)
                .tint(tint)
            }
        } else {
            Label(entry.total == 0 ? "today.empty.title" : "watch.complication.allDone",
                  systemImage: entry.total == 0 ? "moon.stars" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if let emoji = entry.nextEmoji, !emoji.isEmpty {
            Text(emoji)
        } else {
            Image(systemName: "repeat")
        }
    }
}
