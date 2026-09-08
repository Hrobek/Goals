//
//  WatchDiagnosticsFooter.swift
//  GoalsWatch
//

import SwiftUI
import SwiftData

/// A tiny status line shown only when the watch has nothing to show. It answers the questions you
/// would otherwise need a debugger for: did an identity arrive, is the store on CloudKit or did it
/// fall back to local, and how many rows has CloudKit actually mirrored down.
struct WatchDiagnosticsFooter: View {
    @Environment(\.modelContext) private var modelContext

    private var line: String {
        let id = LocalProfile.currentUserId?.uuidString.prefix(8).lowercased() ?? "none"
        let sync = SharedStore.isCloudSyncEnabled ? "on" : "off"
        let mode = SharedStore.storeMode.rawValue
        let goals = (try? modelContext.fetchCount(FetchDescriptor<Goal>())) ?? -1
        let habits = (try? modelContext.fetchCount(FetchDescriptor<Habit>())) ?? -1
        return "id \(id) · sync \(sync) · store \(mode) · G\(goals) H\(habits)"
    }

    var body: some View {
        Text(line)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 10)
    }
}
