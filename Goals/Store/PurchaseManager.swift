//
//  PurchaseManager.swift
//  Goals
//

import Foundation
import StoreKit
import Observation
import WidgetKit

/// The three ways to buy Pro: a monthly and a yearly subscription in one group, plus the
/// non-consumable that unlocks it for good. The lifetime product keeps its original ID so anyone
/// who bought it before the subscriptions existed stays unlocked.
enum ProPlan: String, CaseIterable, Identifiable, Sendable {
    case monthly = "Hrobek.Goals.pro.monthly"
    case yearly = "Hrobek.Goals.pro.yearly"
    case lifetime = "Hrobek.Goals.pro"

    var id: String { rawValue }

    /// The order the paywall lists them in: the recommended one first.
    static let displayOrder: [ProPlan] = [.yearly, .monthly, .lifetime]

    var titleKey: String {
        switch self {
        case .monthly: "paywall.plan.monthly"
        case .yearly: "paywall.plan.yearly"
        case .lifetime: "paywall.plan.lifetime"
        }
    }

    /// What the price is per — "per month", "per year", or nothing at all for the one-off.
    var periodKey: String? {
        switch self {
        case .monthly: "paywall.period.month"
        case .yearly: "paywall.period.year"
        case .lifetime: nil
        }
    }
}

/// The Pro unlock. Any of the three products grants the same entitlement — the app never asks
/// *which* one is owned, only whether one is.
@MainActor
@Observable
final class PurchaseManager {
    private(set) var products: [ProPlan: Product] = [:]
    private(set) var isProUnlocked = false
    private(set) var isLoadingProducts = false
    var lastErrorMessage: String?

    /// Runs for the app's lifetime, picking up purchases completed outside this launch —
    /// Ask to Buy approvals, purchases made on another device, StoreKit Testing edits.
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    func product(for plan: ProPlan) -> Product? { products[plan] }

    /// How much cheaper a year of Pro is bought yearly than paid for month by month, rounded to a
    /// whole percent. Derived from the live prices rather than written down, so it stays honest in
    /// every storefront. Nil until both subscriptions have loaded.
    var yearlySavingsPercent: Int? {
        guard let monthly = products[.monthly]?.price,
              let yearly = products[.yearly]?.price,
              monthly > 0 else { return nil }
        let twelveMonths = monthly * 12
        guard yearly < twelveMonths else { return nil }
        let saved = (twelveMonths - yearly) / twelveMonths * 100
        return NSDecimalNumber(decimal: saved).rounding(accordingToBehavior: nil).intValue
    }

    func loadProducts() async {
        guard products.count < ProPlan.allCases.count else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: ProPlan.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                ProPlan(rawValue: product.id).map { ($0, product) }
            })
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func purchase(_ plan: ProPlan) async {
        guard let product = products[plan] else { return }
        lastErrorMessage = nil
        Analytics.send(.purchaseAttempted, [.plan: plan.analyticsValue])
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastErrorMessage = String(localized: "paywall.error.unverified", defaultValue: "Purchase couldn't be verified.", bundle: AppLanguage.currentBundle)
                    return
                }
                await transaction.finish()
                // Only this branch counts as a conversion. Restores and entitlements picked up from
                // `Transaction.updates` unlock Pro just the same, but nobody bought anything there.
                Analytics.send(.purchaseCompleted, [.plan: plan.analyticsValue])
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        let proProductIDs = Set(ProPlan.allCases.map(\.rawValue))
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, proProductIDs.contains(transaction.productID) else { continue }
            apply(isUnlocked: true)
            return
        }
        apply(isUnlocked: false)
    }

    /// The widget extension can't run an entitlement check of its own — StoreKit is async and a
    /// timeline provider has to answer immediately — so the answer is written into the App Group
    /// and the Pro-only widgets are redrawn against it.
    private func apply(isUnlocked: Bool) {
        isProUnlocked = isUnlocked
        guard ProEntitlement.isUnlocked != isUnlocked else { return }
        ProEntitlement.isUnlocked = isUnlocked
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension ProPlan {
    /// The product ID is fine to report — it names a price tier, not a person.
    var analyticsValue: String {
        switch self {
        case .monthly: "monthly"
        case .yearly: "yearly"
        case .lifetime: "lifetime"
        }
    }
}
