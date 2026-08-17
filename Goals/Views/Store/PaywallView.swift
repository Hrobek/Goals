//
//  PaywallView.swift
//  Goals
//

import SwiftUI
import StoreKit

/// Where a paywall was opened from. The whole point of the purchase funnel is knowing which of
/// these actually converts, so every presentation names itself.
enum PaywallSource: String {
    case limitAlert = "limit_alert"
    case settings
    case lockedFeature = "locked_feature"
    case widget
    /// The one nobody asked for: the periodic nudge a free user gets every couple of weeks.
    case promo
}

struct PaywallView: View {
    let source: PaywallSource

    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    /// Yearly is the one the paywall argues for, so it starts selected and wears the savings badge.
    @State private var selectedPlan: ProPlan = .yearly

    /// What Pro actually buys. Unlimited goals is the headline's own promise, so the list picks up
    /// where the subtitle leaves off — each row reusing the copy the locked feature already shows.
    private let benefits: [(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("chart.line.uptrend.xyaxis", "stats.trends.title", "stats.trends.locked"),
        ("sparkles", "pace.title", "pace.locked"),
        ("chart.xyaxis.line", "goalDetail.chart.title", "goalDetail.chart.locked"),
        ("square.grid.2x2", "widget.activity.displayName", "widget.activity.description")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        headline
                        planPicker
                        benefitList
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                footer
            }
            // The one screen in the app allowed to be a little theatrical.
            .background { BloomBackground.paywall }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .onChange(of: purchaseManager.isProUnlocked) { _, isUnlocked in
                if isUnlocked { dismiss() }
            }
            .sensoryFeedback(trigger: purchaseManager.isProUnlocked) { wasUnlocked, isUnlocked in
                !wasUnlocked && isUnlocked ? .success : nil
            }
            .task {
                Analytics.send(.paywallOpened, [.source: source.rawValue])
                await purchaseManager.loadProducts()
                // Yearly is the default, but never leave the selection pointing at a plan the
                // store didn't hand back.
                if purchaseManager.product(for: selectedPlan) == nil,
                   let firstAvailable = ProPlan.displayOrder.first(where: { purchaseManager.product(for: $0) != nil }) {
                    selectedPlan = firstAvailable
                }
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 12) {
            GoalsMark(size: 52)
            Text("paywall.title")
                .font(.system(size: 30, weight: .medium))
                .tracking(-0.8)
                .foregroundStyle(Theme.text)
            Text("paywall.subtitle")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefitList: some View {
        VStack(spacing: 1) {
            ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: benefit.symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(benefit.title)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text(benefit.body)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Theme.surface)
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var planPicker: some View {
        let available = ProPlan.displayOrder.compactMap { plan in
            purchaseManager.product(for: plan).map { (plan: plan, product: $0) }
        }
        if !available.isEmpty {
            VStack(spacing: 8) {
                ForEach(available, id: \.plan) { entry in
                    planRow(entry.plan, product: entry.product)
                }
            }
        }
    }

    private func planRow(_ plan: ProPlan, product: Product) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textGhost)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(plan.titleKey))
                            .font(Theme.Typo.rowTitle)
                            .foregroundStyle(Theme.text)
                        if plan == .yearly, let savings = purchaseManager.yearlySavingsPercent {
                            savingsBadge(savings)
                        }
                    }
                    if let caption = caption(for: plan, product: product) {
                        caption
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.textFaint)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(Theme.Typo.rowEmphasis)
                        .foregroundStyle(Theme.text)
                    if let periodKey = plan.periodKey {
                        Text(LocalizedStringKey(periodKey))
                            .font(Theme.Typo.footnote)
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .padding(14)
            .background(isSelected ? Theme.accentWell : Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isSelected ? Theme.accentWellBorder : Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func savingsBadge(_ percent: Int) -> some View {
        Text("paywall.save \(percent)")
            .font(Theme.Typo.footnote.weight(.medium))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.pill))
    }

    /// The line under a plan's name: what a year of it works out to per month, or — for the
    /// non-consumable — that there's nothing to renew.
    private func caption(for plan: ProPlan, product: Product) -> Text? {
        switch plan {
        case .yearly:
            let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
            return Text("paywall.plan.perMonth \(perMonth)")
        case .lifetime:
            return Text("paywall.plan.lifetime.caption")
        case .monthly:
            return nil
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            purchaseControl

            Button {
                Task { await purchaseManager.restorePurchases() }
            } label: {
                Text("paywall.restore")
                    .font(Theme.Typo.captionEmphasis)
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)

            if selectedPlan != .lifetime, purchaseManager.product(for: selectedPlan) != nil {
                Text("paywall.legal")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = purchaseManager.lastErrorMessage {
                Text(message)
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.accentText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Theme.ground)
    }

    @ViewBuilder
    private var purchaseControl: some View {
        if purchaseManager.product(for: selectedPlan) != nil {
            Button {
                Task {
                    isPurchasing = true
                    await purchaseManager.purchase(selectedPlan)
                    isPurchasing = false
                }
            } label: {
                if isPurchasing {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("paywall.continue")
                }
            }
            .buttonStyle(AccentButtonStyle(height: 54))
            .disabled(isPurchasing)
        } else if purchaseManager.isLoadingProducts {
            ProgressView()
                .tint(Theme.textMuted)
                .frame(height: 54)
        } else {
            Text("paywall.unavailable")
                .font(Theme.Typo.footnote)
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
                .frame(height: 54)
        }
    }
}

#Preview {
    PaywallView(source: .settings)
        .environment(PurchaseManager())
}
