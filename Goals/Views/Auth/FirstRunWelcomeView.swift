//
//  FirstRunWelcomeView.swift
//  Goals
//

import SwiftUI

/// The "you're in" moment, shown once after the first sign-in on a device. It stands in for the
/// welcome email a server-backed app would send: what the app is for, what to do first, and — with
/// permission — a nudge tomorrow asking how that first goal is going.
struct FirstRunWelcomeView: View {
    /// Called when the user takes the primary action, so the caller can land them on the goals list.
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPreparing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("firstRun.title")
                    .font(.system(size: 32, weight: .medium))
                    .tracking(-0.9)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("firstRun.subtitle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Space.card) {
                markPoint(title: "firstRun.point.goal.title", body: "firstRun.point.goal.body")
                point(icon: "checkmark.circle", title: "firstRun.point.checkIn.title", body: "firstRun.point.checkIn.body")
                point(icon: "chart.line.uptrend.xyaxis", title: "firstRun.point.progress.title", body: "firstRun.point.progress.body")
            }
            .padding(.top, 32)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    start()
                } label: {
                    Text("firstRun.cta")
                }
                .buttonStyle(AccentButtonStyle(height: 52))
                .disabled(isPreparing)

                // Spelled out before the system prompt appears, so the permission sheet isn't the
                // first the user hears of it.
                Text("firstRun.reminderNote")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("firstRun.skip") { dismiss() }
                    .font(Theme.Typo.rowEmphasis)
                    .foregroundStyle(Theme.textMuted)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .screenGround()
        .presentationDragIndicator(.visible)
    }

    /// "Name one goal" is the app's own subject, so it gets the app's own mark.
    private func markPoint(title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        pointCard(title: title, body: body) {
            GoalsMark(size: 22, tone: .mono, color: Theme.accent)
        }
    }

    private func point(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        pointCard(title: title, body: body) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
        }
    }

    private func pointCard<Glyph: View>(
        title: LocalizedStringKey,
        body: LocalizedStringKey,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            glyph()
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(body)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardSurface()
    }

    /// Asks for notifications and books tomorrow's nudge before handing over. A refusal isn't worth
    /// blocking on — the rest of the app works fine without it.
    private func start() {
        isPreparing = true
        Task {
            if await NotificationScheduler.requestAuthorization() {
                await NotificationScheduler.scheduleWelcomeNudge()
            }
            isPreparing = false
            dismiss()
            onStart()
        }
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            FirstRunWelcomeView {}
        }
}
