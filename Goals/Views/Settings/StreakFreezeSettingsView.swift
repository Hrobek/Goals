//
//  StreakFreezeSettingsView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// The streak-freeze switch and how many freezes are banked. Pushed from its own row in the
/// Settings "Breaks" section, next to Vacation.
struct StreakFreezeSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager

    let userId: UUID
    /// Owned by `SettingsView` so its row status stays in sync when this screen is dismissed.
    @Binding var bank: FreezeBank

    private var cap: Int { StreakFreezeEngine.cap(isPro: purchaseManager.isProUnlocked) }
    private var balance: Int { max(0, min(bank.balance, cap)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                CardGroup {
                    SwitchRow(label: "streakFreeze.settings.toggle", icon: "snowflake", isOn: Binding(
                        get: { bank.isEnabled },
                        set: { isOn in
                            bank.isEnabled = isOn
                            bank.save(for: userId)
                            // Turning it back on: earn straight away off the running streaks so
                            // the bank isn't empty until the next check-in.
                            if isOn {
                                StreakFreezeEngine.reconcile(
                                    context: modelContext,
                                    userId: userId,
                                    isPro: purchaseManager.isProUnlocked
                                )
                                bank = FreezeBank.current(for: userId)
                            }
                        }
                    ))
                    if bank.isEnabled {
                        RowDivider()
                        ValueRow("streakFreeze.settings.balance", value: "\(balance) / \(cap)")
                    }
                }

                Text("streakFreeze.settings.explainer")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .screenGround()
        .navigationTitle("streakFreeze.settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .streakFreezesDidChange)) { _ in
            bank = FreezeBank.current(for: userId)
        }
    }
}

#Preview {
    NavigationStack {
        StreakFreezeSettingsView(userId: UUID(), bank: .constant(FreezeBank()))
            .environment(PurchaseManager())
            .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self, StreakFreeze.self], inMemory: true)
    }
}
