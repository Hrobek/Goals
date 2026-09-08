//
//  FreezeLedger.swift
//  Goals
//

import Foundation
import SwiftData

/// The device-local half of streak freeze, mirrored into the App Group so the widgets and the
/// watch compute streaks the same way the app does — the same split `Vacation` uses.
///
/// Two things live here:
/// - **`FreezeLedger`**: a flat cache of which days are frozen for which item, rebuilt from the
///   synced `StreakFreeze` rows. `StreakCalculator` reads this (it has no `ModelContext`), so it
///   has to be refreshed from the store whenever a target starts up or a freeze is spent.
/// - **`FreezeBank`**: the feature toggle, how many freezes are left to spend, and how much of
///   each item's current run has already been paid out as an earned freeze. The balance is
///   device-local (it can drift by one across devices until the next reconcile settles it); the
///   `StreakFreeze` rows it spends are what actually sync.
nonisolated enum FreezeLedger {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroupID) }

    private static func cacheKey(_ userId: UUID) -> String {
        "Goals.streakFreeze.days.\(userId.uuidString)"
    }

    /// Rebuilds the day cache for `userId` from the `StreakFreeze` rows in `context`. Call on
    /// launch / scene-active in every target, and right after a freeze is spent or undone.
    static func rebuild(from context: ModelContext, userId: UUID) {
        let rows = (try? context.fetch(
            FetchDescriptor<StreakFreeze>(predicate: #Predicate { $0.ownerId == userId })
        )) ?? []

        var byItem: [String: [Double]] = [:]
        let calendar = Calendar.current
        for row in rows {
            let key = row.itemID.uuidString
            byItem[key, default: []].append(calendar.startOfDay(for: row.day).timeIntervalSince1970)
        }
        defaults?.set(byItem, forKey: cacheKey(userId))
    }

    /// The frozen days for one item, as start-of-day dates. Empty when nothing is frozen — or when
    /// the cache has never been built on this device yet.
    static func frozenDays(for itemID: UUID, userId: UUID? = LocalProfile.currentUserId) -> Set<Date> {
        guard let userId, let defaults else { return [] }
        guard let byItem = defaults.dictionary(forKey: cacheKey(userId)) as? [String: [Double]],
              let epochs = byItem[itemID.uuidString] else { return [] }
        return Set(epochs.map { Date(timeIntervalSince1970: $0) })
    }

    /// Every frozen day across every item, for callers that want a lookup keyed by item id
    /// (the activity heatmap, mainly).
    static func allFrozenDays(userId: UUID? = LocalProfile.currentUserId) -> [UUID: Set<Date>] {
        guard let userId, let defaults,
              let byItem = defaults.dictionary(forKey: cacheKey(userId)) as? [String: [Double]] else { return [:] }
        var result: [UUID: Set<Date>] = [:]
        for (key, epochs) in byItem {
            guard let id = UUID(uuidString: key) else { continue }
            result[id] = Set(epochs.map { Date(timeIntervalSince1970: $0) })
        }
        return result
    }
}

/// The freeze bank for one user: the toggle, the spendable balance, and per-run earn bookkeeping.
/// Persisted in the App Group, keyed per user, exactly like `Vacation`.
struct FreezeBank: Equatable {
    /// The single Settings switch. Off stops new earning and spending; days already frozen stay
    /// frozen (turning it off shouldn't retroactively snap a streak).
    var isEnabled = true
    /// Freezes available to spend, `0...cap`. `cap` depends on Pro, so it's clamped on read.
    var balance = 0
    /// itemID → how many earned freezes this item's *current* run has already added to the bank.
    /// Reset down when the run shrinks, so a broken-then-rebuilt streak earns again.
    var awardedForRun: [UUID: Int] = [:]
    /// itemID → days the user undid a freeze on. The Pro auto-reconcile won't re-freeze these, so
    /// an undo sticks; applying a manual freeze on the day clears it again.
    var declined: [UUID: Set<Date>] = [:]
    /// Set once the first reconcile has seeded `balance` from pre-existing streaks + spent rows,
    /// so later reconciles only ever apply increments.
    var didSeed = false

    // MARK: - Persistence

    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroupID) }

    private static func key(_ part: String, _ userId: UUID) -> String {
        "Goals.streakFreeze.\(part).\(userId.uuidString)"
    }

    static func current(for userId: UUID? = LocalProfile.currentUserId) -> FreezeBank {
        guard let userId, let defaults else { return FreezeBank() }
        var bank = FreezeBank()
        // `isEnabled` defaults to true, so store the *disabled* flag instead of relying on a
        // missing key reading back as false.
        bank.isEnabled = !defaults.bool(forKey: key("disabled", userId))
        bank.balance = defaults.integer(forKey: key("balance", userId))
        bank.didSeed = defaults.bool(forKey: key("didSeed", userId))
        if let raw = defaults.dictionary(forKey: key("awarded", userId)) as? [String: Int] {
            bank.awardedForRun = Dictionary(uniqueKeysWithValues: raw.compactMap { pair in
                UUID(uuidString: pair.key).map { ($0, pair.value) }
            })
        }
        if let raw = defaults.dictionary(forKey: key("declined", userId)) as? [String: [Double]] {
            bank.declined = Dictionary(uniqueKeysWithValues: raw.compactMap { pair in
                UUID(uuidString: pair.key).map { ($0, Set(pair.value.map { Date(timeIntervalSince1970: $0) })) }
            })
        }
        return bank
    }

    func save(for userId: UUID? = LocalProfile.currentUserId) {
        guard let userId, let defaults = Self.defaults else { return }
        defaults.set(!isEnabled, forKey: Self.key("disabled", userId))
        defaults.set(balance, forKey: Self.key("balance", userId))
        defaults.set(didSeed, forKey: Self.key("didSeed", userId))
        let raw = Dictionary(uniqueKeysWithValues: awardedForRun.map { ($0.key.uuidString, $0.value) })
        defaults.set(raw, forKey: Self.key("awarded", userId))
        let declinedRaw = Dictionary(uniqueKeysWithValues: declined.map { pair in
            (pair.key.uuidString, pair.value.map { $0.timeIntervalSince1970 })
        })
        defaults.set(declinedRaw, forKey: Self.key("declined", userId))
    }
}
