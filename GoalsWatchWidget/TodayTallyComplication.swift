//
//  TodayTallyComplication.swift
//  GoalsWatchWidget
//
//  "3 / 7" — how much of today is done. The morning/evening glance the backlog asked for.
//

import WidgetKit
import SwiftUI

struct TodayTallyComplication: Widget {
    let kind = "GoalsWatchTodayTally"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayComplicationProvider()) { entry in
            TodayTallyView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("watch.complication.tally.name")
        .description("watch.complication.tally.description")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private struct TodayTallyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayComplicationEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if entry.isSignedIn {
                Label("watch.complication.tally.inline \(entry.done) \(entry.total)", systemImage: "checklist")
            } else {
                Text("watch.needsPhone.title")
            }
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    private var circular: some View {
        Gauge(value: entry.fraction) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            Text("\(entry.done)")
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var corner: some View {
        Text("\(entry.done)/\(entry.total)")
            .font(.system(size: 15, weight: .semibold))
            .widgetLabel {
                Gauge(value: entry.fraction) { Text(verbatim: "") }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Gauge(value: entry.fraction) {
                Text(verbatim: "")
            } currentValueLabel: {
                Text("\(entry.done)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("watch.complication.tally.inline \(entry.done) \(entry.total)")
                    .font(.system(size: 15, weight: .semibold))
                if let next = entry.nextTitle, !entry.allDone {
                    Text(verbatim: "\(entry.nextEmoji ?? "→") \(next)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if entry.allDone {
                    Text("watch.complication.allDone")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
