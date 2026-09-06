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
    @State private var isShowingLogPrompt = false
    @State private var logAmountText = ""
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
                todayControl
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
        .alert("habit.log.title", isPresented: $isShowingLogPrompt) {
            TextField(habit.targetText, text: $logAmountText)
                .keyboardType(.decimalPad)
            Button("action.save") {
                if let value = Double(logAmountText.replacingOccurrences(of: ",", with: ".")) {
                    HabitLogger.setAmount(habit, to: value, in: modelContext)
                    checkTick += 1
                }
            }
            Button("action.cancel", role: .cancel) {}
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
                Text(Recurrence.localizedSummary(for: habit))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - Today (mirrors the value-goal detail layout)

    @ViewBuilder
    private var todayControl: some View {
        if habit.isCheckbox {
            checkboxButton
        } else {
            VStack(spacing: Theme.Space.card) {
                progressPanel
                quickAddChips
                logValueButton
            }
        }
    }

    private var checkboxButton: some View {
        Button {
            HabitLogger.toggleToday(habit, in: modelContext)
            checkTick += 1
        } label: {
            HStack(spacing: 9) {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                Text(doneToday ? "habit.doneToday" : "habit.markToday")
                    .font(Theme.Typo.button)
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(tint.opacity(doneToday ? 1 : 0.9), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// The ring + progress readout + streak, in a panel — the same shape as `GoalDetailView`'s
    /// `progressPanel`, just tinted in the habit's colour.
    private var progressPanel: some View {
        HStack(spacing: 18) {
            ProgressRingTinted(progress: habit.progressFraction(), tint: tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("goalDetail.progress")
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(habit.numberOnly(habit.amount(on: .now)))
                        .font(Theme.Typo.statLarge)
                        .foregroundStyle(Theme.text)
                    Text(verbatim: "/ \(habit.targetText)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textFaint)
                }
                .monospacedDigit()
                .padding(.top, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("a11y.progress \(habit.numberOnly(habit.amount(on: .now))) \(habit.targetText)"))

                HStack(spacing: 7) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accentBright)
                    Text("\(habit.currentStreak) · \(Recurrence.localizedSummary(for: habit))")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textStrong)
                        .lineLimit(2)
                }
                .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .cardSurface(radius: Theme.Radius.panel, padding: 18)
    }

    /// Bare row of `+N` steps and a `−`, exactly like `GoalDetailView.quickAddChips`.
    private var quickAddChips: some View {
        HStack(spacing: 8) {
            ForEach(quickSteps, id: \.self) { step in
                Button {
                    HabitLogger.adjust(habit, by: step, in: modelContext)
                    checkTick += 1
                } label: {
                    Text("+\(habit.numberOnly(step))")
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.control, in: .rect(cornerRadius: Theme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control)
                                .strokeBorder(Theme.textGhost, lineWidth: 1)
                        }
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("a11y.quickAdd \(habit.quickAddLabel(step))"))
            }

            Button {
                HabitLogger.adjust(habit, by: -habit.widgetQuickAmount, in: modelContext)
                checkTick += 1
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.control, in: .rect(cornerRadius: Theme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(Theme.textGhost, lineWidth: 1)
                    }
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("a11y.removeTime"))
        }
    }

    /// Full-width primary button, like the goal detail's "Log Value".
    private var logValueButton: some View {
        Button {
            logAmountText = ""
            isShowingLogPrompt = true
        } label: {
            Label("goalDetail.logValue", systemImage: "plus.circle")
                .font(Theme.Typo.button)
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(tint, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var quickSteps: [Double] {
        GoalUnit(rawValue: habit.unitKey)?.quickAddSteps ?? [1, 2, 5, 10]
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

/// `ProgressRing` from DesignKit, but stroked in an arbitrary colour so a habit's ring can wear
/// its own colour instead of the app accent.
private struct ProgressRingTinted: View {
    let progress: Double
    let tint: Color
    var size: CGFloat = 96
    var lineWidth: CGFloat = 7

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: size * 0.2, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: clamped)
    }
}
