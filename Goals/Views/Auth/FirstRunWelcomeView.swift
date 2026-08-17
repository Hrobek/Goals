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
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("firstRun.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("firstRun.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 18) {
                point(icon: "target", title: "firstRun.point.goal.title", body: "firstRun.point.goal.body")
                point(icon: "checkmark.circle.fill", title: "firstRun.point.checkIn.title", body: "firstRun.point.checkIn.body")
                point(icon: "chart.line.uptrend.xyaxis", title: "firstRun.point.progress.title", body: "firstRun.point.progress.body")
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button {
                    start()
                } label: {
                    Text("firstRun.cta")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing)

                // Spelled out before the system prompt appears, so the permission sheet isn't the
                // first the user hears of it.
                Text("firstRun.reminderNote")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("firstRun.skip") { dismiss() }
                    .font(.subheadline)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 24)
        .presentationDragIndicator(.visible)
    }

    private func point(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
