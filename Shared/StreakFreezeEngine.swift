//
//  StreakFreezeEngine.swift
//  Goals
//

import Foundation
import SwiftData
import WidgetKit

/// The rules of streak freeze in one place: how freezes are earned, when Pro spends one
/// automatically, and the manual spend / undo the UI drives.
///
/// - **Earn** (`reconcile`): every `earnStep` consecutive done days in a run pays one freeze into
///   a single per-account bank. Free earns one per 7 days and can hold 1; Pro earns one per 5 and
///   can hold 3. Anything over the cap is lost.
/// - **Spend**: Pro auto-spends one freeze on any streak sitting exactly one missed day from
///   breaking, longest streak first, one day per lapse. Free taps "Protect your streak" instead.
/// - **Undo**: a recent freeze can be handed back to the bank, letting the streak break after all.
///
/// `@MainActor` to match `StreakCalculator` / `Recurrence`, which the app target treats as
/// main-actor.
@MainActor
enum StreakFreezeEngine {
    static func cap(isPro: Bool) -> Int { isPro ? 3 : 1 }
    static func earnStep(isPro: Bool) -> Int { isPro ? 5 : 7 }
    /// How long after it was applied a freeze is still offered for undo.
    static let undoWindowDays = 10

    /// Freezes spendable right now: the stored balance clamped to the current cap, which drops
    /// if Pro lapses (the stored number is kept, just not usable, in case Pro comes back).
    static func spendable(_ bank: FreezeBank, isPro: Bool) -> Int {
        max(0, min(bank.balance, cap(isPro: isPro)))
    }

    // MARK: - Reconcile

    /// Pays out freezes for runs that grew and — for Pro — auto-spends on any streak one missed
    /// day from breaking. Cheap to call on every scene-active and after every in-app check-in;
    /// it only writes to the store when it actually freezes a day.
    @discardableResult
    static func reconcile(
        context: ModelContext,
        userId: UUID,
        isPro: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        var bank = FreezeBank.current(for: userId)
        let balanceBefore = bank.balance
        guard bank.isEnabled else {
            FreezeLedger.rebuild(from: context, userId: userId)
            return false
        }

        let cap = cap(isPro: isPro)
        let step = earnStep(isPro: isPro)
        let windowFloor = calendar.date(
            byAdding: .day, value: -StreakCalculator.freezeWindowDays,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast

        let goals = (try? context.fetch(
            FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId == userId })
        )) ?? []
        let habits = (try? context.fetch(
            FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId == userId })
        )) ?? []

        struct Runner { let id: UUID; let isHabit: Bool; let schedule: any Scheduled }
        var runners: [Runner] = []
        for goal in goals where goal.status == .active {
            runners.append(Runner(id: goal.id, isHabit: false, schedule: goal))
        }
        for habit in habits where !habit.isArchived && !habit.isAvoid {
            runners.append(Runner(id: habit.id, isHabit: true, schedule: habit))
        }

        // Compute every current streak once, off a fresh day cache.
        FreezeLedger.rebuild(from: context, userId: userId)
        var streakOf: [UUID: Int] = [:]
        for runner in runners {
            streakOf[runner.id] = StreakCalculator.currentStreak(
                for: runner.schedule, calendar: calendar, referenceDate: now
            )
        }

        // First ever run on this device: seed the balance from pre-existing streaks minus the
        // freezes already on the books, so we don't hand out the whole pre-feature backlog but
        // still land on a number that matches what's been spent.
        if !bank.didSeed {
            let deservedTotal = runners.reduce(0) { $0 + (streakOf[$1.id] ?? 0) / step }
            let spent = (try? context.fetchCount(
                FetchDescriptor<StreakFreeze>(predicate: #Predicate { $0.ownerId == userId })
            )) ?? 0
            bank.balance = max(0, min(cap, deservedTotal - spent))
            for runner in runners { bank.awardedForRun[runner.id] = (streakOf[runner.id] ?? 0) / step }
            bank.didSeed = true
        }

        // Earn: pay the bank for every step-sized chunk a run has reached that hasn't been paid
        // yet. `awardedForRun` also shrinks here when a run was lost, so the next rebuild earns
        // afresh.
        for runner in runners {
            let deserved = (streakOf[runner.id] ?? 0) / step
            let already = bank.awardedForRun[runner.id] ?? 0
            if deserved > already {
                bank.balance = min(cap, bank.balance + (deserved - already))
            }
            bank.awardedForRun[runner.id] = deserved
        }
        let liveIDs = Set(runners.map(\.id))
        bank.awardedForRun = bank.awardedForRun.filter { liveIDs.contains($0.key) }
        // Drop declined markers for dead items or gaps that have aged out of the freeze window.
        bank.declined = bank.declined
            .filter { liveIDs.contains($0.key) }
            .mapValues { $0.filter { $0 >= windowFloor } }
            .filter { !$0.value.isEmpty }

        // Pro auto-spend: longest streak first, one day per lapse. A day the user undid a freeze
        // on is left alone so the undo sticks.
        var didFreeze = false
        if isPro {
            for runner in runners.sorted(by: { (streakOf[$0.id] ?? 0) > (streakOf[$1.id] ?? 0) }) {
                guard spendable(bank, isPro: isPro) > 0 else { break }
                guard let gap = StreakCalculator.repairableGap(
                    for: runner.schedule, calendar: calendar, referenceDate: now
                ) else { continue }
                if bank.declined[runner.id]?.contains(gap) == true { continue }
                context.insert(StreakFreeze(
                    ownerId: userId, itemID: runner.id, isHabit: runner.isHabit,
                    day: gap, appliedAt: now, wasAutomatic: true
                ))
                bank.balance -= 1
                didFreeze = true
                try? context.save()
                FreezeLedger.rebuild(from: context, userId: userId)
            }
        }

        bank.save(for: userId)
        FreezeLedger.rebuild(from: context, userId: userId)
        if didFreeze {
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Tell the detail card / Settings row to re-read whenever the spendable balance moved,
        // whether that was an auto-spend or just an earn from a check-in.
        if didFreeze || bank.balance != balanceBefore {
            NotificationCenter.default.post(name: .streakFreezesDidChange, object: nil)
        }
        return didFreeze
    }

    // MARK: - Manual spend / undo

    /// Free tier: spend one freeze on the tip gap of `schedule`. Returns the rescued day, or nil
    /// when there's nothing to rescue or no freeze to spend.
    @discardableResult
    static func applyManualFreeze(
        to schedule: some Scheduled,
        isHabit: Bool,
        userId: UUID,
        context: ModelContext,
        isPro: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        var bank = FreezeBank.current(for: userId)
        guard bank.isEnabled, spendable(bank, isPro: isPro) > 0 else { return nil }
        guard let gap = StreakCalculator.repairableGap(
            for: schedule, calendar: calendar, referenceDate: now
        ) else { return nil }

        context.insert(StreakFreeze(
            ownerId: userId, itemID: schedule.id, isHabit: isHabit,
            day: gap, appliedAt: now, wasAutomatic: false
        ))
        bank.balance -= 1
        bank.declined[schedule.id]?.remove(gap)   // user changed their mind about this day
        bank.save(for: userId)
        try? context.save()
        FreezeLedger.rebuild(from: context, userId: userId)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .streakFreezesDidChange, object: nil)
        return gap
    }

    /// Hand a freeze back to the bank and let the streak break after all.
    static func undoFreeze(
        _ freeze: StreakFreeze,
        userId: UUID,
        context: ModelContext,
        isPro: Bool
    ) {
        var bank = FreezeBank.current(for: userId)
        let day = freeze.day
        let itemID = freeze.itemID
        context.delete(freeze)
        bank.balance = min(cap(isPro: isPro), bank.balance + 1)
        // Remember the day so the Pro auto-reconcile doesn't just put the freeze straight back.
        bank.declined[itemID, default: []].insert(day)
        bank.save(for: userId)
        try? context.save()
        FreezeLedger.rebuild(from: context, userId: userId)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .streakFreezesDidChange, object: nil)
    }

    /// The most recent freeze on `schedule` still inside the undo window — what the detail screen
    /// offers to take back.
    static func recentFreeze(
        for schedule: some Scheduled,
        userId: UUID,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StreakFreeze? {
        let itemID = schedule.id
        let rows = (try? context.fetch(FetchDescriptor<StreakFreeze>(
            predicate: #Predicate { $0.ownerId == userId && $0.itemID == itemID }
        ))) ?? []
        let cutoff = calendar.date(byAdding: .day, value: -undoWindowDays, to: now) ?? now
        return rows.filter { $0.appliedAt >= cutoff }.max { $0.appliedAt < $1.appliedAt }
    }
}
