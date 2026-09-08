//
//  NotificationScheduler.swift
//  Goals
//

import Foundation
import SwiftData
import UserNotifications

/// All local notifications the app schedules:
/// - per-goal reminders the user configures on the goal itself,
/// - per-habit reminders, same shape as goal reminders,
/// - a single "we haven't seen you in a while" nudge that gets pushed further out every time the
///   app is opened, so it only ever fires if the user actually stops coming back.
enum NotificationScheduler {
    private static let goalPrefix = "goal-reminder."
    private static let habitPrefix = "habit-reminder."
    private static let inactivityPrefix = "inactivity."
    private static let welcomeIdentifier = "welcome.firstGoal"

    /// How many days of silence before each nudge fires.
    private static let inactivityDays = [3, 10]

    // MARK: - Authorization

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Syncing

    /// Rebuilds every scheduled notification from the current data. Cheap for a handful of goals
    /// and habits and idempotent, which beats trying to patch individual requests from a dozen
    /// call sites.
    @MainActor
    static func syncAll(context: ModelContext, userId: UUID) async {
        guard await authorizationStatus() == .authorized else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }

        let goalDescriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId == userId })
        let goals = (try? context.fetch(goalDescriptor)) ?? []
        let habitDescriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId == userId })
        let habits = (try? context.fetch(habitDescriptor)) ?? []
        let center = UNUserNotificationCenter.current()

        // A repeating reminder can't be date-bounded, so a paused item just isn't scheduled while
        // the vacation covers today. `syncAll` runs on every foreground, so the reminder comes
        // back on the first launch after the vacation ends.
        let vacation = Vacation.current(for: userId)

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(goalPrefix) || $0.hasPrefix(habitPrefix) || $0.hasPrefix(inactivityPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for goal in goals where goal.isReminderOn && goal.status == .active && !vacation.pauses(goal.id, on: .now) {
            for request in reminderRequests(
                prefix: goalPrefix,
                id: goal.id,
                title: goal.title,
                body: String(localized: "reminder.body", defaultValue: "Time to check in on this goal.", bundle: AppLanguage.currentBundle),
                frequency: goal.reminderFrequency,
                times: goal.reminderTimes,
                weekdays: goal.reminderWeekdays,
                userInfo: ["goalID": goal.id.uuidString]
            ) {
                try? await center.add(request)
            }
        }

        for habit in habits where habit.isReminderOn && habit.status == .active && !vacation.pauses(habit.id, on: .now) {
            for request in reminderRequests(
                prefix: habitPrefix,
                id: habit.id,
                title: habit.title,
                body: String(localized: "reminder.habit.body", defaultValue: "Time for this habit.", bundle: AppLanguage.currentBundle),
                frequency: habit.reminderFrequency,
                times: habit.reminderTimes,
                weekdays: habit.reminderWeekdays,
                userInfo: ["habitID": habit.id.uuidString]
            ) {
                try? await center.add(request)
            }
        }

        // No "haven't heard from you" guilt trip while the user has told us they're away.
        if !vacation.coversToday {
            for request in inactivityRequests() {
                try? await center.add(request)
            }
        }
    }

    // MARK: - Reminder requests (shared by goals and habits)

    /// One request per time of day, and — when weekly — per (weekday, time) pair. The index in the
    /// identifier keeps them distinct; `syncAll` clears everything under the prefix first, so stale
    /// ids from an earlier layout don't linger.
    private static func reminderRequests(
        prefix: String,
        id: UUID,
        title: String,
        body: String,
        frequency: ReminderFrequency,
        times: [Int],
        weekdays: [Int],
        userInfo: [String: String]
    ) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        switch frequency {
        case .daily:
            return times.enumerated().map { index, minutes in
                var components = DateComponents()
                components.hour = minutes / 60
                components.minute = minutes % 60
                return UNNotificationRequest(
                    identifier: "\(prefix)\(id.uuidString).\(index)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )
            }
        case .weekly:
            return weekdays.flatMap { weekday in
                times.enumerated().map { index, minutes in
                    var components = DateComponents()
                    components.weekday = weekday
                    components.hour = minutes / 60
                    components.minute = minutes % 60
                    return UNNotificationRequest(
                        identifier: "\(prefix)\(id.uuidString).\(weekday).\(index)",
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    )
                }
            }
        }
    }

    // MARK: - First-run nudge

    /// The day-after "how's that first goal going?" nudge, booked from the welcome screen. It sits
    /// outside `syncAll`'s prefixes on purpose: that method rebuilds everything from the goals in
    /// the store, and this one belongs to the sign-up rather than to any goal, so it would be swept
    /// away on the next launch.
    static func scheduleWelcomeNudge(afterDays days: Int = 1, hour: Int = 10, calendar: Calendar = .current) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "reminder.welcome.title", defaultValue: "How's the first goal going?", bundle: AppLanguage.currentBundle)
        content.body = String(localized: "reminder.welcome.body", defaultValue: "One check-in is enough to get a streak started.", bundle: AppLanguage.currentBundle)
        content.sound = .default

        // Fired at a civil hour rather than 24 hours to the minute after signing up, which could
        // land in the middle of the night.
        guard let day = calendar.date(byAdding: .day, value: days, to: .now),
              let fireDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return }

        let request = UNNotificationRequest(
            identifier: welcomeIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(60, fireDate.timeIntervalSinceNow),
                repeats: false
            )
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Inactivity nudge

    private static func inactivityRequests() -> [UNNotificationRequest] {
        inactivityDays.map { days in
            let content = UNMutableNotificationContent()
            content.title = String(localized: "reminder.inactivity.title", defaultValue: "Your goals are waiting", bundle: AppLanguage.currentBundle)
            content.body = String(localized: "reminder.inactivity.body", defaultValue: "It's been a while. A quick check-in is enough to keep the streak alive.", bundle: AppLanguage.currentBundle)
            content.sound = .default

            return UNNotificationRequest(
                identifier: "\(inactivityPrefix)\(days)",
                content: content,
                // Not repeating: every app launch reschedules it, so it only fires after a real
                // stretch of not opening the app.
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(days) * 24 * 60 * 60, repeats: false)
            )
        }
    }
}
