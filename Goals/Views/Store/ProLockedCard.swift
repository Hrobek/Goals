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

    @State private var isShowingPaywall = false

    var body: some View {
        Button {
            isShowingPaywall = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accentSpent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typo.captionEmphasis)
                        .foregroundStyle(Theme.text)
                    Text(message)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // "Pro" is the tier's name, not a word to translate.
                AccentPill(text: "Pro")
            }
            .cardSurface()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("settings.pro.upgrade"))
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(source: .lockedFeature)
        }
    }
}

#Preview {
    ProLockedCard(title: "stats.trends.title", message: "stats.trends.locked")
        .padding()
        .screenGround()
        .environment(PurchaseManager())
}
