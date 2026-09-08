//
//  WatchNeedsPhoneView.swift
//  GoalsWatch
//

import SwiftUI

/// Shown before the watch has an identity. Almost always transient — the paired phone pushes its
/// profile id within a second of either app opening. If it lingers, the cause is iCloud sync being
/// off on the phone, so the copy says so.
struct WatchNeedsPhoneView: View {
    var body: some View {
        VStack(spacing: 10) {
            GoalsMark(size: 34, tone: .accent)
            Text("watch.needsPhone.title")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("watch.needsPhone.message")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    WatchNeedsPhoneView()
}
