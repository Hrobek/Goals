//
//  PurchaseManager.swift
//  Goals
//

import Foundation
import StoreKit
import Observation
import WidgetKit

/// The Pro unlock: a single non-consumable that removes the active-goal limit. No subscriptions,
/// no consumables — one product keeps the whole purchase flow small and the entitlement check
/// simple (it's either owned or it isn't).
@MainActor
@Observable
final class PurchaseManager {
    static let proProductID = "Hrobek.Goals.pro"

    private(set) var product: Product?
    private(set) var isProUnlocked = false
    private(set) var isLoadingProduct = false
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
            await self?.loadProduct()
            await self?.refreshEntitlements()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [Self.proProductID]).first
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func purchase() async {
        guard let product else { return }
        lastErrorMessage = nil
        Analytics.send(.purchaseAttempted)
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
                Analytics.send(.purchaseCompleted)
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
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.proProductID else { continue }
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
