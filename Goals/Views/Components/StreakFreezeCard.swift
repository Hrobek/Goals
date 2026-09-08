//
//  StreakFreezeCard.swift
//  Goals
//

import SwiftUI
import SwiftData

/// The streak-freeze affordance on a habit or goal detail screen. It shows one of:
/// - **Protect**: a freeze is available and the streak is one missed day from breaking — tap to
///   spend it (this is how the free tier applies a freeze; Pro normally gets here automatically).
/// - **Used**: a freeze was applied recently — tap to undo and let the streak break after all.
/// - nothing, the rest of the time.
///
/// It re-evaluates whenever `refreshKey` changes (the host bumps it on every check-in) and after
/// its own actions.
struct StreakFreezeCard<S: Scheduled>: View {
    let schedule: S
    let isHabit: Bool
    let userId: UUID
    var tint: Color = Theme.accent
    /// Bumped by the host after a check-in so the card recomputes.
    let refreshKey: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var mode: Mode = .hidden
    @State private var usedFreeze: StreakFreeze?
    @State private var actionTick = 0

    private enum Mode: Equatable { case hidden, protectStreak, used }

    private var isPro: Bool { purchaseManager.isProUnlocked }

    var body: some View {
        Group {
            switch mode {
            case .hidden:
                EmptyView()
            case .protectStreak:
                panel {
                    copy(title: "streakFreeze.protect.title", subtitle: "streakFreeze.protect.subtitle")
                    Spacer(minLength: 10)
                    actionButton("streakFreeze.protect.action", filled: true) {
                        StreakFreezeEngine.applyManualFreeze(
                            to: schedule, isHabit: isHabit, userId: userId,
                            context: modelContext, isPro: isPro
                        )
                        actionTick += 1
                        evaluate()
                    }
                }
            case .used:
                panel {
                    copy(title: "streakFreeze.used.title", subtitle: nil, detail: usedFreezeDateText)
                    Spacer(minLength: 10)
                    actionButton("streakFreeze.used.undo", filled: false) {
                        if let usedFreeze {
                            StreakFreezeEngine.undoFreeze(
                                usedFreeze, userId: userId, context: modelContext, isPro: isPro
                            )
                        }
                        actionTick += 1
                        evaluate()
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: actionTick)
        .task(id: "\(schedule.id)|\(refreshKey)") { evaluate() }
        .onReceive(NotificationCenter.default.publisher(for: .streakFreezesDidChange)) { _ in
            evaluate()
        }
    }

    // MARK: - Pieces

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "snowflake")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.Radius.panel, padding: 16)
    }

    private func copy(title: LocalizedStringKey, subtitle: LocalizedStringKey?, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail {
                Text(detail)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }

    private func actionButton(_ label: LocalizedStringKey, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typo.captionEmphasis)
                .foregroundStyle(filled ? Theme.onAccent : Theme.textMuted)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    filled ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.control),
                    in: .rect(cornerRadius: Theme.Radius.control)
                )
                .overlay {
                    if !filled {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(Theme.textGhost, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var usedFreezeDateText: String? {
        usedFreeze.map { $0.day.formatted(date: .abbreviated, time: .omitted) }
    }

    // MARK: - Logic

    private func evaluate() {
        guard !schedule.isAvoid else { mode = .hidden; return }
        let bank = FreezeBank.current(for: userId)
        guard bank.isEnabled else { mode = .hidden; return }

        if StreakFreezeEngine.spendable(bank, isPro: isPro) > 0,
           StreakCalculator.repairableGap(for: schedule) != nil {
            mode = .protectStreak
            return
        }
        if let recent = StreakFreezeEngine.recentFreeze(for: schedule, userId: userId, context: modelContext) {
            usedFreeze = recent
            mode = .used
            return
        }
        mode = .hidden
    }
}
