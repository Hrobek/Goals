//
//  NotificationDelegate.swift
//  Goals
//

import UIKit
import UserNotifications

/// Routes a tapped reminder to the goal or habit it was about, by reopening the same `goals://`
/// deep link a widget tap already uses - `RootView.onOpenURL` is the one place that knows how to
/// turn an id into a pushed detail screen, so this hands it the URL instead of duplicating that
/// navigation.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let url = Self.deepLink(for: response.notification.request.content.userInfo) else { return }
        Task { @MainActor in
            UIApplication.shared.open(url)
        }
    }

    /// Without this, a reminder that fires while the app is already open lands silently in
    /// Notification Center instead of showing anything.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    private static func deepLink(for userInfo: [AnyHashable: Any]) -> URL? {
        if let raw = userInfo["goalID"] as? String, let id = UUID(uuidString: raw) {
            return URL(string: "goals://goal/\(id.uuidString)")
        }
        if let raw = userInfo["habitID"] as? String, let id = UUID(uuidString: raw) {
            return URL(string: "goals://habit/\(id.uuidString)")
        }
        return nil
    }
}
