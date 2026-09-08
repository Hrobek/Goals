//
//  ShareCardView.swift
//  Goals
//

import SwiftUI

/// The image the share sheet hands off — a 4:5 card summarising a week. Drawn from fixed dark
/// palette stops (not the adaptive `Theme` tokens) so it renders the same whoever's looking and
/// whatever their appearance setting.
struct ShareCardView: View {
    let review: WeekReview
    var locale: Locale = .current
    /// The sharer's nickname, shown next to the wordmark in the footer. Empty hides it.
    var nickname: String = ""

    /// Logical size; the renderer scales this up. 4:5 suits a feed or a story crop.
    static let logicalSize = CGSize(width: 540, height: 675)

    private var percentText: String {
        review.adherence.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private var rangeText: String {
        StatsRange.week.label(for: review.interval, locale: locale)
    }

    private var maxDaily: Int { max(review.dailyCounts.max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rangeText)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Ramp.grey500)

            Spacer(minLength: 0)

            Text(percentText)
                .font(.system(size: 132, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Ramp.white)

            Text(checkInsText)
                .font(.system(size: 24, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Ramp.grey400)
                .padding(.top, 2)

            activityStrip
                .padding(.top, 40)

            if let streak = review.longestStreak, streak.streak > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Ramp.red300)
                    Text(verbatim: "\(streak.streak)")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Ramp.white)
                    Text(streak.title)
                        .font(.system(size: 20))
                        .foregroundStyle(Ramp.grey400)
                        .lineLimit(1)
                }
                .padding(.top, 28)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(44)
        .frame(width: Self.logicalSize.width, height: Self.logicalSize.height, alignment: .topLeading)
        .background(Ramp.black)
        .environment(\.colorScheme, .dark)
    }

    private var activityStrip: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(review.dailyCounts.enumerated()), id: \.offset) { _, count in
                RoundedRectangle(cornerRadius: 5)
                    .fill(count > 0 ? Ramp.red400 : Ramp.grey800)
                    .frame(height: 10 + 78 * CGFloat(count) / CGFloat(maxDaily))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 88, alignment: .bottom)
    }

    private var footer: some View {
        ShareCardFooter(nickname: nickname, trailing: movedStalledText)
    }

    private var checkInsText: String {
        String(
            format: String(localized: "shareCard.checkIns %lld %lld", defaultValue: "%1$lld / %2$lld check-ins", bundle: AppLanguage.currentBundle, locale: locale),
            review.done, review.planned
        )
    }

    private var movedStalledText: String {
        String(
            format: String(localized: "shareCard.movedStalled %lld %lld", defaultValue: "%1$lld moved · %2$lld stalled", bundle: AppLanguage.currentBundle, locale: locale),
            review.moved.count, review.stalled.count
        )
    }
}

// MARK: - Single goal / habit

/// What a progress card needs, pulled out of a `Goal` or `Habit` at the call site where all the
/// formatting helpers already live.
struct ProgressShareData {
    let title: String
    let emoji: String?
    /// A habit's own colour; goals pass nil and take the app accent.
    let tintHex: String?
    /// 0…1 fill for the bar. Pass 0 to hide it (a plain streak card).
    let fraction: Double
    /// The one big line — "68%", "42 / 100 km", "12".
    let headline: String
    /// The line under it — a percentage, "current streak", "Done".
    let caption: String
    let streak: Int
    /// Schedule summary or deadline, shown small in the footer.
    let footNote: String
}

/// A goal's or habit's progress as the same 4:5 dark card the weekly one uses. A habit brings its
/// own colour (`tintHex`) — it rings the badge, marks the header, and carries the hero number and
/// the flame — the same one-saturated-colour rule the app follows everywhere else. A goal passes
/// no tint and stays mono, the accent showing only on the progress bar.
struct ProgressShareCardView: View {
    let data: ProgressShareData
    /// The sharer's nickname, shown next to the wordmark in the footer. Empty hides it.
    var nickname: String = ""

    private var tinted: Bool { data.tintHex != nil }
    private var tint: Color { data.tintHex.map(Color.init(hex:)) ?? Ramp.red400 }
    private var headlineColor: Color { tinted ? tint : Ramp.white }
    private var flameColor: Color { tinted ? tint : Ramp.red300 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tinted ? tint.opacity(0.22) : Ramp.grey900)
                        .overlay {
                            if tinted { Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1.5) }
                        }
                    if let emoji = data.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: 30))
                    } else {
                        GoalsMark(size: 32, tone: .mono, color: tinted ? tint : Ramp.white)
                    }
                }
                .frame(width: 60, height: 60)

                Text(data.title)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Ramp.white)
                    .lineLimit(2)
            }

            if tinted {
                Capsule()
                    .fill(tint.opacity(0.6))
                    .frame(width: 56, height: 4)
                    .padding(.top, 22)
            }

            Spacer(minLength: 0)

            Text(data.headline)
                .font(.system(size: 108, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(headlineColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(data.caption)
                .font(.system(size: 24))
                .foregroundStyle(Ramp.grey400)
                .padding(.top, 2)

            if data.fraction > 0 {
                Capsule()
                    .fill(Ramp.grey800)
                    .frame(height: 12)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(tint)
                                .frame(width: geo.size.width * min(max(data.fraction, 0), 1))
                        }
                    }
                    .padding(.top, 32)
            }

            if data.streak > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.system(size: 20)).foregroundStyle(flameColor)
                    Text(verbatim: "\(data.streak)")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Ramp.white)
                }
                .padding(.top, 28)
            }

            Spacer(minLength: 0)

            ShareCardFooter(nickname: nickname, trailing: data.footNote)
        }
        .padding(44)
        .frame(width: ShareCardView.logicalSize.width, height: ShareCardView.logicalSize.height, alignment: .topLeading)
        .background(Ramp.black)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Footer

/// The strip along the bottom of every share card: the app mark, the wordmark carrying the
/// sharer's nickname when they've set one, and a small trailing detail. Fixed dark palette, same
/// as the cards it sits in.
private struct ShareCardFooter: View {
    var nickname: String = ""
    let trailing: String

    private var brand: String {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Goals" : "Goals · \(name)"
    }

    var body: some View {
        HStack(spacing: 10) {
            GoalsMark(size: 30, tone: .mono, color: Ramp.white)
            Text(verbatim: brand)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Ramp.grey400)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(trailing)
                .font(.system(size: 18))
                .monospacedDigit()
                .foregroundStyle(Ramp.grey600)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

// MARK: - Rendering

enum ShareCard {
    /// Renders the weekly card to an `Image` ready for `ShareLink`. Main-actor because
    /// `ImageRenderer` is.
    @MainActor
    static func image(for review: WeekReview, locale: Locale = AppLanguage.current.locale, nickname: String? = nil, scale: CGFloat = 2) -> Image? {
        render(ShareCardView(review: review, locale: locale, nickname: nickname ?? LocalProfile.nickname), scale: scale)
    }

    /// Renders a single goal's / habit's progress card.
    @MainActor
    static func image(for data: ProgressShareData, nickname: String? = nil, scale: CGFloat = 2) -> Image? {
        render(ProgressShareCardView(data: data, nickname: nickname ?? LocalProfile.nickname), scale: scale)
    }

    @MainActor
    private static func render(_ view: some View, scale: CGFloat) -> Image? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        #if canImport(UIKit)
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}

#Preview {
    ShareCardView(review: WeekReview(
        interval: Calendar.current.dateInterval(of: .weekOfYear, for: .now)!,
        weekOffset: 0,
        lines: [],
        dailyCounts: [2, 0, 3, 1, 0, 4, 1],
        milestones: []
    ))
}
