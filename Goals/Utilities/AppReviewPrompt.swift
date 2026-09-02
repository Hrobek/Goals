//
//  AppReviewPrompt.swift
//  Goals
//

import Foundation
import SwiftUI

/// Decides when the system rating prompt gets its turn, and where the manual "rate the app"
/// button in Settings goes.
///
/// StoreKit already caps the prompt at three per year and silently swallows the rest, so the
/// rules here aren't about squeezing out more prompts — they're about spending the few we get on
/// someone who has used the app long enough to have an opinion.
@MainActor
enum AppReviewPrompt {
    /// The app's App Store ID, used to build the review and listing URLs.
    static let appStoreID = "6804143515"

    /// `action=write-review` opens the listing with the review sheet already up, which is the
    /// point of the button — the plain listing URL would just show the product page.
    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    private static let firstLaunchKey = "Goals.review.firstLaunchDate"
    private static let lastPromptKey = "Goals.review.lastPromptDate"
    private static let lastPromptVersionKey = "Goals.review.lastPromptVersion"

    /// Long enough that the app has been through a few days of real use, short enough that the
    /// first impression is still fresh.
    private static let minimumDaysInstalled = 3
    /// Number of logged check-ins before we ask: someone who never logged anything has nothing
    /// to rate.
    private static let minimumCheckIns = 5
    /// Roughly a third of the yearly allowance, so a "not now" isn't followed up next week.
    private static let minimumDaysBetweenPrompts = 120

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Stamped on the first run rather than derived from the install date, which iOS doesn't hand
    /// out. Call it on every launch; only the first one writes.
    static func recordFirstLaunchIfNeeded(now: Date = .now) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: firstLaunchKey) == nil else { return }
        defaults.set(now, forKey: firstLaunchKey)
    }

    static func shouldRequest(checkInCount: Int, now: Date = .now) -> Bool {
        let defaults = UserDefaults.standard

        guard checkInCount >= minimumCheckIns else { return false }

        guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date,
              days(from: firstLaunch, to: now) >= minimumDaysInstalled else { return false }

        // One ask per version: whoever declined on 1.0 shouldn't be asked again until there is
        // something new to have an opinion about.
        if defaults.string(forKey: lastPromptVersionKey) == currentVersion { return false }

        if let lastPrompt = defaults.object(forKey: lastPromptKey) as? Date,
           days(from: lastPrompt, to: now) < minimumDaysBetweenPrompts {
            return false
        }

        return true
    }

    /// Recorded when we *ask*, not when a review is written — StoreKit never tells us which
    /// happened, and asking again is the thing we're trying to avoid either way.
    static func recordRequest(now: Date = .now) {
        let defaults = UserDefaults.standard
        defaults.set(now, forKey: lastPromptKey)
        defaults.set(currentVersion, forKey: lastPromptVersionKey)
    }

    private static func days(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
