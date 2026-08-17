//
//  PeriodNavigator.swift
//  Goals
//

import SwiftUI

/// Prev/next paging through weeks, months or years, with a label naming the one on screen — so
/// "this week's grid" becomes "any week's grid, and which one you're looking at".
struct PeriodNavigator: View {
    let range: StatsRange
    @Binding var offset: Int

    private var interval: DateInterval? {
        range.interval(offset: offset)
    }

    var body: some View {
        HStack {
            Button {
                withAnimation(.snappy) { offset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 32, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.period.previous"))

            Spacer(minLength: 8)

            Text(label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)

            Spacer(minLength: 8)

            Button {
                withAnimation(.snappy) { offset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(offset >= 0 ? Theme.textGhost : Theme.textMuted)
                    .frame(width: 32, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(offset >= 0)
            .accessibilityLabel(Text("a11y.period.next"))
        }
        // Paging is a change of what's on screen rather than an achievement, so it gets the same
        // light tick a picker gives — enough to feel the step, not enough to become noise while
        // scrubbing back through months.
        .sensoryFeedback(.selection, trigger: offset)
    }

    private var label: String {
        guard let interval else { return "" }
        return range.label(for: interval, locale: AppLanguage.current.locale)
    }
}

#Preview {
    PeriodNavigator(range: .month, offset: .constant(0))
        .padding()
}
