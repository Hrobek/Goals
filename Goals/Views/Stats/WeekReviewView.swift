//
//  WeekReviewView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// The week in one screen: how much of what you planned got done, which goals and habits moved,
/// which stalled, and any streak that crossed a milestone. Pages back through earlier weeks.
struct WeekReviewView: View {
    @Query private var goals: [Goal]
    @Query private var habits: [Habit]

    @State private var weekOffset = 0
    @State private var shareImage: Image?

    private let calendar = Calendar.current

    init(userId: UUID) {
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId }, sort: [SortDescriptor(\Habit.sortIndex)])
    }

    private var review: WeekReview {
        WeekReview.make(goals: goals, habits: habits, weekOffset: weekOffset, calendar: calendar)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                PeriodNavigator(range: .week, offset: $weekOffset)

                if review.hasActivity {
                    adherenceCard
                    activityStrip
                    if !review.milestones.isEmpty { milestonesSection }
                    if !review.moved.isEmpty { movedSection }
                    if !review.stalled.isEmpty { stalledSection }
                } else {
                    EmptyStateView(
                        systemImage: "calendar",
                        title: "weekReview.empty.title",
                        message: "weekReview.empty.message"
                    )
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(.snappy, value: weekOffset)
        }
        .scrollIndicators(.hidden)
        .screenGround()
        .navigationTitle(Text("weekReview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .toolbar {
            if review.hasActivity, let shareImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(Text("weekReview.title"), image: shareImage)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: shareSignature) {
            shareImage = ShareCard.image(for: review)
        }
    }

    /// Re-render the share card whenever the week or its totals change.
    private var shareSignature: String {
        "\(weekOffset)|\(review.done)|\(review.planned)|\(review.lines.count)"
    }

    // MARK: - Adherence

    private var adherenceCard: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: review.adherence, size: 88, lineWidth: 7)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(review.done)")
                        .font(Theme.Typo.statMedium)
                        .foregroundStyle(Theme.text)
                    Text(verbatim: "/ \(review.planned)")
                        .font(Theme.Typo.statSmall)
                        .foregroundStyle(Theme.textFaint)
                }
                Text("weekReview.adherence.caption")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .cardSurface(padding: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("weekReview.adherence.caption"))
        .accessibilityValue(Text("today.progress \(review.done) \(review.planned)"))
    }

    // MARK: - Activity strip

    private var activityStrip: some View {
        let maxCount = max(review.dailyCounts.max() ?? 0, 1)
        return LabeledSection("weekReview.activity") {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(review.dailyCounts.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(count > 0 ? Theme.accent : Theme.track)
                            .frame(height: 8 + 64 * CGFloat(count) / CGFloat(maxCount))
                        Text(Recurrence.weekdayAbbreviation(weekday(forColumn: index)))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textGhost)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .cardSurface(padding: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("weekReview.activity"))
        .accessibilityValue(Text("today.progress \(review.done) \(review.planned)"))
    }

    /// Calendar weekday number (1 = Sunday) for the Nth column, honouring `firstWeekday`.
    private func weekday(forColumn index: Int) -> Int {
        (calendar.firstWeekday - 1 + index) % 7 + 1
    }

    // MARK: - Sections

    private var milestonesSection: some View {
        LabeledSection("weekReview.section.milestones") {
            CardGroup {
                ForEach(Array(review.milestones.enumerated()), id: \.offset) { index, milestone in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 11) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accentBright)
                        Text(milestone.title)
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(milestone.days)")
                            .font(Theme.Typo.rowEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(Theme.accentBright)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var movedSection: some View {
        LabeledSection("weekReview.section.moved") {
            CardGroup {
                ForEach(Array(review.moved.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { RowDivider() }
                    WeekLineRow(line: line)
                }
            }
        }
    }

    private var stalledSection: some View {
        LabeledSection("weekReview.section.stalled") {
            CardGroup(muted: true) {
                ForEach(Array(review.stalled.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { RowDivider() }
                    WeekLineRow(line: line)
                }
            }
        }
    }
}

/// One goal or habit's row in the review: identity on the left, "3 / 5" and a thin bar on the
/// right. Shared by the moved and stalled lists.
private struct WeekLineRow: View {
    let line: WeekReview.Line

    private var tint: Color { line.isHabit ? Color(hex: line.colorHex) : Theme.accent }

    var body: some View {
        HStack(spacing: 11) {
            badge

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(line.title)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(line.done) / \(line.planned)")
                        .font(Theme.Typo.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textStrong)
                }
                ThinBar(progress: line.fraction, color: tint)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.title))
        .accessibilityValue(Text("today.progress \(line.done) \(line.planned)"))
    }

    @ViewBuilder
    private var badge: some View {
        if line.isHabit {
            ZStack {
                Circle().fill(tint.opacity(0.20))
                if let emoji = line.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 14))
                } else {
                    Image(systemName: "repeat").font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                }
            }
            .frame(width: 30, height: 30)
        } else {
            GoalBadge(emoji: line.emoji, size: 30)
        }
    }
}

#Preview {
    NavigationStack {
        WeekReviewView(userId: UUID())
            .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
    }
}
