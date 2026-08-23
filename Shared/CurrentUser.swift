//
//  CurrentUser.swift
//  Goals
//

import Foundation

/// Reads and writes the signed-in identity in the App Group, so the widget extension — which
/// can't see the app's in-memory `AuthSession` — knows whose goals to show.
enum CurrentUser {
    private static let storageKey = "Goals.currentUser"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    static var current: AuthenticatedUser? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AuthenticatedUser.self, from: data)
    }

    static var currentUserId: UUID? {
        current?.id
    }

    static func set(_ user: AuthenticatedUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        defaults?.set(data, forKey: storageKey)
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }
}
