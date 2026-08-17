//
//  ProPromoPrompt.swift
//  Goals
//

import Foundation

/// Decides when the paywall shows up on its own, for someone who hasn't bought Pro.
///
/// The rules are the same shape as `AppReviewPrompt`'s, and for the same reason: an unasked-for
/// sheet is only tolerable if it's rare and lands on someone who has used the app enough to know
/// what Pro would be worth. A fresh install gets a few days of quiet first, and after that the
/// promo comes round no more than once a fortnight — a "not now" is a no for two weeks.
@MainActor
enum ProPromoPrompt {
    private static let lastShownKey = "Goals.proPromo.lastShownDate"
    private static let firstLaunchKey = "Goals.review.firstLaunchDate"

    /// Long enough to have set up a few goals and hit the free limit on their own terms.
    private static let minimumDaysInstalled = 4
    /// How long a dismissal buys before the promo comes back.
    private static let minimumDaysBetweenPrompts = 14
    /// Someone who logged nothing has no use for unlimited goals yet.
    private static let minimumCheckIns = 3

    static func shouldShow(isProUnlocked: Bool, checkInCount: Int, now: Date = .now) -> Bool {
        guard !isProUnlocked else { return false }
        guard checkInCount >= minimumCheckIns else { return false }

        let defaults = UserDefaults.standard

        // Shares the review prompt's stamp: both want "how long has this app been in use", and
        // it's already written on every launch.
        guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date,
              days(from: firstLaunch, to: now) >= minimumDaysInstalled else { return false }

        if let lastShown = defaults.object(forKey: lastShownKey) as? Date,
           days(from: lastShown, to: now) < minimumDaysBetweenPrompts {
            return false
        }

        return true
    }

    static func recordShown(now: Date = .now) {
        UserDefaults.standard.set(now, forKey: lastShownKey)
    }

    private static func days(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
