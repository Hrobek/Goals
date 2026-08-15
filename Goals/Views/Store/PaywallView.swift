//
//  PaywallView.swift
//  Goals
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "infinity.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("paywall.title")
                        .font(.title2.bold())
                    Text("paywall.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                purchaseControl

                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    Text("paywall.restore")
                        .font(.footnote)
                }
                .disabled(isPurchasing)

                if let message = purchaseManager.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .onChange(of: purchaseManager.isProUnlocked) { _, isUnlocked in
                if isUnlocked { dismiss() }
            }
            .task {
                await purchaseManager.loadProduct()
            }
        }
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
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("paywall.purchase \(product.displayPrice)")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPurchasing)
        } else if purchaseManager.isLoadingProduct {
            ProgressView()
        } else {
            Text("paywall.unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PaywallView()
        .environment(PurchaseManager())
}
