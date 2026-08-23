//
//  WidgetSupport.swift
//  GoalsWidget
//

import SwiftUI
import WidgetKit
import SwiftData
import AppIntents

// MARK: - Kinds

enum WidgetKind {
    static let goals = "GoalsWidget"
    static let activity = "GoalsActivityWidget"
    static let progressChart = "GoalsProgressChartWidget"
}

extension WidgetFamily {
    /// Size-specific name for the page store, so two widgets of different sizes don't share a
    /// page — a small one showing three goals and a large one showing nine page at different rates.
    var pageScopeName: String {
        switch self {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        case .systemExtraLarge: "extraLarge"
        default: "other"
        }
    }
}

// MARK: - Goal fetching

/// The goal lists the widgets page through. Timelines outlive the fetch, so everything here hands
/// back plain values — never SwiftData models.
@MainActor
enum WidgetGoals {
    /// `false` right after an update, before the main app has run once to migrate the signed-in
    /// identity into the App Group — distinct from a signed-in user who simply has no goals, so
    /// widgets can show "open the app" instead of a plain empty state.
    static var isSignedIn: Bool { CurrentUser.currentUserId != nil }

    static func fetch(_ include: (Goal) -> Bool) -> [Goal] {
        guard let userId = CurrentUser.currentUserId else { return [] }
        let context = SharedStore.container.mainContext
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId == userId })
        let goals = (try? context.fetch(descriptor)) ?? []
        return goals
            .filter { $0.status == .active && include($0) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// The slice of goals a widget is currently parked on, together with how many slices there are.
    /// The stored page is wrapped rather than trusted: goals get completed and archived between
    /// redraws, and an index off the end would otherwise blank the widget out.
    static func page<T>(_ goals: [Goal], perPage: Int, scope: String, transform: (Goal) -> T?) -> (items: [T], page: Int, count: Int) {
        guard !goals.isEmpty, perPage > 0 else { return ([], 0, 0) }
        let count = Int(ceil(Double(goals.count) / Double(perPage)))
        let page = WidgetPageStore.wrapped(WidgetPageStore.page(forKey: scope), count: count)
        return (goals.dropFirst(page * perPage).prefix(perPage).compactMap(transform), page, count)
    }
}

// MARK: - Paging

/// The ‹ 2/3 › strip along the bottom of a widget. Shown only when there's something to page to,
/// so a single-goal home screen doesn't carry two dead arrows around.
struct WidgetPager: View {
    let kind: String
    let scope: String
    let page: Int
    let pageCount: Int
    var compact = false

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: 4) {
                button(step: -1, systemImage: "chevron.left")
                Spacer(minLength: 2)
                Text("\(page + 1)/\(pageCount)")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 2)
                button(step: 1, systemImage: "chevron.right")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func button(step: Int, systemImage: String) -> some View {
        Button(intent: PageIntent(kind: kind, scope: scope, step: step, pageCount: pageCount)) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: compact ? 20 : 26, height: compact ? 14 : 18)
                .background(Theme.control, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(step < 0 ? "a11y.widget.previousPage" : "a11y.widget.nextPage"))
    }
}

// MARK: - States

/// What a free user sees instead of a Pro widget: what it would show, and a tap that lands on the
/// paywall — the same trade the in-app locked cards make.
struct ProLockedWidgetView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(Theme.accentSpent)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("widget.pro.locked")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(GoalLink.paywall)
    }
}

struct WidgetMessageView: View {
    let message: LocalizedStringKey
    /// `nil` draws the app's own mark — the right glyph for "nothing here yet".
    var systemImage: String?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                } else {
                    GoalsMark(size: 22, tone: .mono, color: Theme.accentSpent)
                }
            }
            .foregroundStyle(Theme.accentSpent)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Emoji, title and a trailing detail — the top line of both single-goal widgets, tapping through
/// to the goal itself.
struct WidgetGoalHeader: View {
    let id: UUID
    let title: String
    let emoji: String?
    let detail: String?
    var compact = false

    var body: some View {
        Link(destination: GoalLink.url(for: id)) {
            HStack(spacing: 5) {
                GoalIdentity(emoji: emoji, size: compact ? 12 : 14)
                Text(title)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .lineLimit(1)
                if let detail {
                    Spacer(minLength: 4)
                    Text(detail)
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .contentShape(.rect)
        }
    }
}

// MARK: - Periods

/// The week or month a widget is showing, plus the label naming it. Deliberately a separate,
/// smaller thing than the app's `StatsRange`: widgets only ever show the current period, and the
/// app-side type lives in a view file the extension can't see.
enum WidgetPeriod {
    case week, month

    func interval(calendar: Calendar, now: Date = .now) -> DateInterval? {
        calendar.dateInterval(of: self == .week ? .weekOfYear : .month, for: now)
    }

    func label(for interval: DateInterval, calendar: Calendar, locale: Locale) -> String {
        switch self {
        case .week:
            let lastDay = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            let start = interval.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            let end = lastDay.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            return "\(start) – \(end)"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year().locale(locale))
        }
    }
}
