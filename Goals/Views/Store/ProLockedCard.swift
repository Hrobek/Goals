//
//  ProLockedCard.swift
//  Goals
//

import SwiftUI

/// A locked teaser for a Pro-only section: what it is, and a way to unlock it. Reused wherever a
/// free-tier screen wants to advertise a Pro feature instead of just hiding it outright.
struct ProLockedCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    @State private var isShowingPaywall = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isShowingPaywall = true
            } label: {
                Text("settings.pro.upgrade")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(source: .lockedFeature)
        }
    }
}

#Preview {
    Form {
        Section {
            ProLockedCard(title: "stats.trends.title", message: "stats.trends.locked", systemImage: "chart.xyaxis.line")
        }
    }
    .environment(PurchaseManager())
}
