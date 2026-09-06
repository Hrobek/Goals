//
//  HabitDetailView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct HabitDetailView: View {
    @Bindable var habit: Habit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var isShowingEdit = false
    @State private var isShowingDeleteConfirmation = false
    @State private var activityRange: StatsRange = .month
    @State private var activityOffset = 0
    @State private var checkTick = 0

    private var tint: Color { Color(hex: habit.colorHex) }
    private var doneToday: Bool { habit.isDone(on: .now) }

    /// Free tier gets week + month; the year grid is Pro.
    private var availableRanges: [StatsRange] {
        purchaseManager.isProUnlocked ? StatsRange.allCases : [.week, .month]
    }

    private var bestStreak: Int {
        // Walk back day by day, tracking the longest run of done scheduled days.
        let calendar = Calendar.current
        let doneDays = Set(habit.scheduleDates.map { calendar.startOfDay(for: $0) })
        guard let earliest = doneDays.min() else { return 0 }
        var best = 0
        var run = 0
        var cursor = calendar.startOfDay(for: .now)
        while cursor >= earliest {
            if Recurrence.isDayScheduled(cursor, for: habit, calendar: calendar) {
                if doneDays.contains(cursor) {
                    run += 1
                    best = max(best, run)
                } else {
                    run = 0
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return best
    }

    private var totalDone: Int {
        habit.scheduleDates.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header
                checkTodayButton
                activitySection
                if purchaseManager.isProUnlocked {
                    statsSection
                } else {
                    ProLockedCard(title: "habits.stats.title", message: "habits.stats.locked")
                }
                reminderSection
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .screenGround()
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { navBar }
        .sensoryFeedback(.success, trigger: checkTick)
        .sheet(isPresented: $isShowingEdit) {
            AddEditHabitView(habit: habit, userId: habit.ownerId)
        }
        .confirmationDialog("habits.delete.title", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("action.delete", role: .destructive) {
                modelContext.delete(habit)
                syncReminders()
                dismiss()
            }
        }
    }

    // MARK: - Chrome

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textStrong)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }

            Spacer()

            Menu {
                Button { isShowingEdit = true } label: {
                    Label("action.edit", systemImage: "pencil")
                }
                Button {
                    habit.isArchived.toggle()
                    syncReminders()
                    dismiss()
                } label: {
                    Label(
                        habit.isArchived ? "action.unarchive" : "action.archive",
                        systemImage: habit.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                }
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("action.delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.textStrong)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("a11y.habitOptions"))
        }
        .padding(.horizontal, 12)
        .background(Theme.ground)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.20))
                    .overlay { Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1) }
                if let emoji = habit.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 26))
                } else {
                    Image(systemName: "repeat").font(.system(size: 22)).foregroundStyle(tint)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title)
                    .font(Theme.Typo.pageTitle)
                    .tracking(Theme.Typo.pageTitleTracking)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accentBright)
                    Text("\(habit.currentStreak) · \(Recurrence.localizedSummary(for: habit))")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textStrong)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var checkTodayButton: some View {
        Button {
            HabitLogger.toggleToday(habit, in: modelContext)
            checkTick += 1
        } label: {
            HStack(spacing: 9) {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                Text(doneToday ? "habit.doneToday" : "habit.markToday")
                    .font(Theme.Typo.buttonSmall)
                if habit.dailyTarget > 1 {
                    Spacer(minLength: 0)
                    Text("\(habit.count(on: .now))/\(habit.dailyTarget)")
                        .font(Theme.Typo.captionEmphasis)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(doneToday ? Theme.onAccent : Theme.accentText)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .padding(.horizontal, 16)
            .background(doneToday ? tint : Theme.accentWell, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(doneToday ? Color.clear : Theme.accentWellBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var activitySection: some View {
        LabeledSection("goalDetail.activity") {
            VStack(spacing: 12) {
                SegmentStrip(options: availableRanges, selection: $activityRange, title: { $0.localizedName })
                    .onChange(of: activityRange) { activityOffset = 0 }
                PeriodNavigator(range: activityRange, offset: $activityOffset)
                ScheduleActivityView(schedule: habit, range: activityRange, offset: activityOffset)
            }
            .cardSurface()
        }
    }

    private var statsSection: some View {
        LabeledSection("habits.stats.title") {
            CardGroup {
                ValueRow("stats.currentStreak", value: "\(habit.currentStreak)")
                RowDivider()
                ValueRow("habits.stats.bestStreak", value: "\(bestStreak)")
                RowDivider()
                ValueRow("habits.stats.total", value: "\(totalDone)")
            }
        }
    }

    @ViewBuilder
    private var reminderSection: some View {
        if habit.isReminderOn {
            LabeledSection("reminder.title") {
                CardGroup {
                    ValueRow("reminder.time", value: reminderSummary)
                }
            }
        }
    }

    private var reminderSummary: String {
        habit.reminderTimes.map { minutes in
            String(format: "%d:%02d", minutes / 60, minutes % 60)
        }.joined(separator: ", ")
    }

    private func syncReminders() {
        let context = modelContext
        let userId = habit.ownerId
        Task { await NotificationScheduler.syncAll(context: context, userId: userId) }
    }
}
