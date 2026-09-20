//
//  HealthSettingsView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// The Apple Health screen: device availability, when it last synced, and every habit/goal
/// currently linked - with a way to unlink one without reopening its own edit screen. Mirrors
/// `SyncSettingsView`'s shape (a status card, then the thing it's a status for).
struct HealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var habits: [Habit]
    @Query private var goals: [Goal]

    @State private var lastSync: Date?
    @State private var isSyncing = false

    private let userId: UUID

    init(userId: UUID) {
        self.userId = userId
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId }, sort: [SortDescriptor(\Habit.sortIndex)])
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
    }

    private struct Item: Identifiable {
        let id: UUID
        let title: String
        let emoji: String?
        let direction: HealthKitDirection
        let metric: HealthKitMetric
        let unlink: () -> Void
    }

    private var linkedItems: [Item] {
        let habitItems = habits.compactMap { habit -> Item? in
            guard let metric = habit.healthKitMetric, let direction = habit.healthKitDirection else { return nil }
            return Item(id: habit.id, title: habit.title, emoji: habit.emoji, direction: direction, metric: metric) {
                habit.healthKitMetric = nil
                habit.healthKitDirection = nil
            }
        }
        let goalItems = goals.compactMap { goal -> Item? in
            guard let metric = goal.healthKitMetric, let direction = goal.healthKitDirection else { return nil }
            return Item(id: goal.id, title: goal.title, emoji: goal.emoji, direction: direction, metric: metric) {
                goal.healthKitMetric = nil
                goal.healthKitDirection = nil
            }
        }
        return habitItems + goalItems
    }

    private var isAvailable: Bool { HealthKitAuthManager.isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                statusCard

                if linkedItems.isEmpty {
                    Text("settings.health.empty")
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                } else {
                    LabeledSection("settings.health.linked") {
                        CardGroup {
                            ForEach(Array(linkedItems.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { RowDivider() }
                                linkedRow(item)
                            }
                        }
                    }
                }

                Text("settings.health.explainer")
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
        .navigationTitle("health.link.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .task { lastSync = HealthSyncStatus.lastSyncDate }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { lastSync = HealthSyncStatus.lastSyncDate }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        CardGroup {
            ValueRow(label: "settings.health.status", icon: isAvailable ? "heart.text.square" : "heart.slash") {
                Text(statusText)
                    .font(Theme.Typo.row)
                    .foregroundStyle(isAvailable ? Theme.text : Theme.accentText)
            }
            if isAvailable {
                RowDivider()
                ValueRow(label: "settings.sync.lastSynced", icon: "clock.arrow.circlepath") {
                    Text(lastSyncedText)
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                }
                RowDivider()
                Button {
                    syncNow()
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                        }
                        Text("settings.health.syncNow")
                            .font(Theme.Typo.rowEmphasis)
                    }
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isSyncing || linkedItems.isEmpty)
            }
        }
    }

    private var statusText: LocalizedStringKey {
        isAvailable ? "settings.health.status.available" : "settings.health.status.unavailable"
    }

    private var lastSyncedText: String {
        guard let lastSync else {
            return String(localized: "settings.sync.never", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
        }
        return lastSync.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale))
    }

    private func syncNow() {
        isSyncing = true
        let context = modelContext
        Task {
            await HealthKitSyncEngine.syncAll(context: context)
            lastSync = HealthSyncStatus.lastSyncDate
            isSyncing = false
        }
    }

    // MARK: - Linked rows

    private func linkedRow(_ item: Item) -> some View {
        HStack(spacing: 11) {
            Text(item.emoji ?? "❤️")
                .font(.system(size: 20))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(item.direction.localizedName) · \(item.metric.localizedName)")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    item.unlink()
                    HealthKitSyncEngine.startObserving(context: modelContext)
                }
            } label: {
                Text("settings.health.unlink")
                    .font(Theme.Typo.captionEmphasis)
                    .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
    }
}

#Preview {
    NavigationStack {
        HealthSettingsView(userId: UUID())
            .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
    }
}
