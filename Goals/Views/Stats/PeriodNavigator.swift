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
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }

            Spacer(minLength: 8)

            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)

            Spacer(minLength: 8)

            Button {
                withAnimation(.snappy) { offset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .disabled(offset >= 0)
            .opacity(offset >= 0 ? 0.3 : 1)
        }
        // Not `.plain`: inside a Form row that style hands the whole row to a single tap target,
        // so neither chevron ever fires. `.borderless` keeps the two buttons independently
        // hit-testable — and it tints its labels, hence the explicit `.tint` to keep the chevrons
        // the same muted grey as the label between them.
        .buttonStyle(.borderless)
        .tint(.secondary)
        .foregroundStyle(.secondary)
        // Left alone, the separator under this row starts at the centred label — a stub of a line,
        // nothing like the full-width one above it. Pin it to the row's own leading edge, which is
        // where every other separator in the Form begins.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
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
