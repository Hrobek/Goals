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
}

struct PaywallView: View {
    let source: PaywallSource

    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

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
                        benefitList
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                footer
            }
            // A red bloom at the top, thinning into the ground — the one place in the app that
            // gets to be a little theatrical.
            .background {
                LinearGradient(
                    colors: [Theme.accentWell, Theme.ground],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            }
            .screenGround()
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
                await purchaseManager.loadProduct()
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
        if let product = purchaseManager.product {
            Button {
                Task {
                    isPurchasing = true
                    await purchaseManager.purchase()
                    isPurchasing = false
                }
            } label: {
                if isPurchasing {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("paywall.purchase \(product.displayPrice)")
                }
            }
            .buttonStyle(AccentButtonStyle(height: 54))
            .disabled(isPurchasing)
        } else if purchaseManager.isLoadingProduct {
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
