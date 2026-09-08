//
//  Vacation.swift
//  Goals
//

import Foundation

/// A single "I'm away" window with a per-item opt-out. While it's active, the goals and habits
/// the user ticked don't break their streak for days inside the range — those days are skipped
/// the way an unscheduled day is.
///
/// Lives in the App Group (keyed per user), the same place `SharedStore.isCloudSyncEnabled` and
/// the analytics flag live — so the app and the widget compute streaks the same way. It is *not*
/// synced across devices; a vacation set on the phone won't reach the iPad.
struct Vacation: Equatable {
    var isActive = false
    var start = Calendar.current.startOfDay(for: .now)
    var end = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now
    /// Goal and habit ids that pause during the window. Empty means nothing is paused even when
    /// `isActive` — the streak logic then behaves exactly as before.
    var pausedItemIDs: Set<UUID> = []

    // MARK: - Persistence

    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroupID) }

    private static func key(_ part: String, _ userId: UUID) -> String {
        "Goals.vacation.\(part).\(userId.uuidString)"
    }

    static func current(for userId: UUID? = LocalProfile.currentUserId) -> Vacation {
        guard let userId, let defaults else { return Vacation() }
        var vacation = Vacation()
        vacation.isActive = defaults.bool(forKey: key("active", userId))
        if let start = defaults.object(forKey: key("start", userId)) as? Date { vacation.start = start }
        if let end = defaults.object(forKey: key("end", userId)) as? Date { vacation.end = end }
        let ids = (defaults.array(forKey: key("paused", userId)) as? [String]) ?? []
        vacation.pausedItemIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        return vacation
    }

    func save(for userId: UUID? = LocalProfile.currentUserId) {
        guard let userId, let defaults = Self.defaults else { return }
        defaults.set(isActive, forKey: Self.key("active", userId))
        defaults.set(start, forKey: Self.key("start", userId))
        defaults.set(end, forKey: Self.key("end", userId))
        defaults.set(pausedItemIDs.map(\.uuidString), forKey: Self.key("paused", userId))
    }

    // MARK: - Queries

    /// The inclusive day range, normalised to start-of-day. Nil when the vacation is off.
    private func dayRange(_ calendar: Calendar) -> ClosedRange<Date>? {
        guard isActive else { return nil }
        let low = calendar.startOfDay(for: min(start, end))
        let high = calendar.startOfDay(for: max(start, end))
        return low <= high ? low...high : nil
    }

    /// Whether `date` is a paused day for this item: vacation on, item opted in, date in range.
    func pauses(_ itemID: UUID, on date: Date, calendar: Calendar = .current) -> Bool {
        guard pausedItemIDs.contains(itemID), let range = dayRange(calendar) else { return false }
        return range.contains(calendar.startOfDay(for: date))
    }

    /// Whether every day of `interval` is paused for this item — used to skip a whole
    /// weekly/monthly quota period that falls entirely inside the vacation.
    func pausesEntirePeriod(_ itemID: UUID, _ interval: DateInterval, calendar: Calendar = .current) -> Bool {
        guard pausedItemIDs.contains(itemID), let range = dayRange(calendar) else { return false }
        let firstDay = calendar.startOfDay(for: interval.start)
        let lastDay = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        return range.lowerBound <= firstDay && lastDay <= range.upperBound
    }

    /// Vacation is on and today is inside it — for silencing the "haven't heard from you" nudge.
    var coversToday: Bool {
        guard let range = dayRange(.current) else { return false }
        return range.contains(Calendar.current.startOfDay(for: .now))
    }
}
