//
//  VacationSettingsView.swift
//  Goals
//

import SwiftUI
import SwiftData

/// One "I'm away" window. While it's on, the ticked goals and habits don't break their streak for
/// days inside the range. Pushed from its own section in Settings.
struct VacationSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var goals: [Goal]
    @Query private var habits: [Habit]

    /// Owned by `SettingsView` so its row label stays in sync when this screen is dismissed.
    @Binding var vacation: Vacation

    private let userId: UUID

    init(userId: UUID, vacation: Binding<Vacation>) {
        self.userId = userId
        _vacation = vacation
        _goals = Query(filter: #Predicate<Goal> { $0.ownerId == userId }, sort: \Goal.createdAt, order: .reverse)
        _habits = Query(filter: #Predicate<Habit> { $0.ownerId == userId }, sort: [SortDescriptor(\Habit.sortIndex)])
    }

    private struct Item: Identifiable {
        let id: UUID
        let title: String
        let emoji: String?
        let colorHex: String?
        let isHabit: Bool
    }

    private var rows: [Item] {
        goals.filter { $0.status == .active }.map {
            Item(id: $0.id, title: $0.title, emoji: $0.emoji, colorHex: nil, isHabit: false)
        }
        + habits.filter { !$0.isArchived }.map {
            Item(id: $0.id, title: $0.title, emoji: $0.emoji, colorHex: $0.colorHex, isHabit: true)
        }
    }

    private var allItemIDs: Set<UUID> { Set(rows.map(\.id)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                CardGroup {
                    SwitchRow(label: "settings.vacation.toggle", icon: "beach.umbrella", isOn: Binding(
                        get: { vacation.isActive },
                        set: { isOn in
                            vacation.isActive = isOn
                            // First time on: pause everything, then let the user un-tick what they
                            // still want to keep up.
                            if isOn, vacation.pausedItemIDs.isEmpty {
                                vacation.pausedItemIDs = allItemIDs
                            }
                            persist()
                        }
                    ))
                }

                if vacation.isActive {
                    CardGroup {
                        datePickerRow("settings.vacation.from", selection: Binding(
                            get: { vacation.start },
                            set: {
                                vacation.start = $0
                                if vacation.end < $0 { vacation.end = $0 }
                                persist()
                            }
                        ))
                        RowDivider()
                        datePickerRow("settings.vacation.to", selection: Binding(
                            get: { vacation.end },
                            set: { vacation.end = max($0, vacation.start); persist() }
                        ), lowerBound: vacation.start)
                    }

                    LabeledSection("settings.vacation.items") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                Button("settings.vacation.all") { vacation.pausedItemIDs = allItemIDs; persist() }
                                Button("settings.vacation.none") { vacation.pausedItemIDs = []; persist() }
                                Spacer(minLength: 0)
                            }
                            .font(Theme.Typo.captionEmphasis)
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 4)

                            if rows.isEmpty {
                                Text("settings.vacation.noItems")
                                    .font(Theme.Typo.footnote)
                                    .foregroundStyle(Theme.textFaint)
                                    .padding(.horizontal, 4)
                            } else {
                                CardGroup {
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 { RowDivider() }
                                        itemRow(item)
                                    }
                                }
                            }
                        }
                    }
                }

                Text("settings.vacation.explainer")
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
        .navigationTitle("settings.vacation.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
    }

    private func persist() {
        vacation.save(for: userId)
        // Re-run the notification schedule so a now-paused item's reminders stop (and a
        // just-unpaused one's come back) without waiting for the next app launch.
        let context = modelContext
        let userId = userId
        Task { await NotificationScheduler.syncAll(context: context, userId: userId) }
    }

    private func datePickerRow(_ label: LocalizedStringKey, selection: Binding<Date>, lowerBound: Date? = nil) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 10)
            if let lowerBound {
                DatePicker(label, selection: selection, in: lowerBound..., displayedComponents: .date)
                    .labelsHidden()
            } else {
                DatePicker(label, selection: selection, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 9)
    }

    private func itemRow(_ item: Item) -> some View {
        let isPaused = vacation.pausedItemIDs.contains(item.id)
        return Button {
            if isPaused { vacation.pausedItemIDs.remove(item.id) } else { vacation.pausedItemIDs.insert(item.id) }
            persist()
        } label: {
            HStack(spacing: 11) {
                badge(for: item)
                Text(item.title)
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Image(systemName: isPaused ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isPaused ? Theme.accent : Theme.textGhost)
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isPaused ? "a11y.today.done" : "a11y.today.notDone"))
    }

    @ViewBuilder
    private func badge(for item: Item) -> some View {
        if item.isHabit {
            let tint = Color(hex: item.colorHex ?? ColorPalette.defaultHex)
            ZStack {
                Circle().fill(tint.opacity(0.20))
                if let emoji = item.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 13))
                } else {
                    Image(systemName: "repeat").font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
                }
            }
            .frame(width: 28, height: 28)
        } else {
            GoalBadge(emoji: item.emoji, size: 28)
        }
    }
}

#Preview {
    NavigationStack {
        VacationSettingsView(userId: UUID(), vacation: .constant(Vacation()))
            .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
    }
}
