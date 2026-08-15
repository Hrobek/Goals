//
//  GoalDetailView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Bindable var goal: Goal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var isShowingEdit = false
    @State private var isShowingCheckIn = false
    @State private var isShowingDeleteConfirmation = false
    @State private var newMilestoneTitle = ""
    @State private var activityRange: StatsRange = .month
    @State private var chartRange: StatsRange = .month

    private var sortedMilestones: [Milestone] {
        goal.sortedMilestones
    }

    private var sortedCheckIns: [CheckIn] {
        goal.checkIns.sorted { $0.date > $1.date }
    }

    var body: some View {
        Form {
            Section {
                header
            }

            Section("goalDetail.progress") {
                progressRow
                ProgressView(value: goal.progressFraction)
                paceRow
                if goal.trackingMode == .value {
                    quickAddChips
                }
                Button {
                    isShowingCheckIn = true
                } label: {
                    Label(logButtonTitle, systemImage: goal.trackingMode == .value ? "plus.circle" : "checkmark.circle")
                }
                Toggle("goalDetail.markCompleted", isOn: $goal.isCompleted)
                    .onChange(of: goal.isCompleted) { syncReminders() }
            }

            if goal.trackingMode == .value {
                progressChartSection
            }

            activitySection

            Section("goalDetail.schedule") {
                LabeledContent("goalDetail.schedule", value: Recurrence.localizedSummary(for: goal))
                LabeledContent("goalDetail.streak", value: "\(StreakCalculator.currentStreak(for: goal))")
            }

            reminderSection

            if goal.trackingMode == .milestones {
                Section("goalDetail.milestones") {
                    ForEach(sortedMilestones) { milestone in
                        MilestoneRow(milestone: milestone)
                    }
                    .onDelete(perform: deleteMilestones)

                    HStack {
                        TextField("goalDetail.newMilestone", text: $newMilestoneTitle)
                        Button {
                            addMilestone()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if !sortedCheckIns.isEmpty {
                Section("goalDetail.history") {
                    ForEach(sortedCheckIns.prefix(20)) { checkIn in
                        CheckInRow(checkIn: checkIn)
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isShowingEdit = true
                    } label: {
                        Label("action.edit", systemImage: "pencil")
                    }
                    Button {
                        goal.isArchived.toggle()
                        syncReminders()
                        dismiss()
                    } label: {
                        Label(
                            goal.isArchived ? "action.unarchive" : "action.archive",
                            systemImage: goal.isArchived ? "tray.and.arrow.up" : "archivebox"
                        )
                    }
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            AddEditGoalView(goal: goal)
        }
        .sheet(isPresented: $isShowingCheckIn) {
            CheckInSheetView(goal: goal)
        }
        .confirmationDialog("goalDetail.deleteConfirm.title", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("action.delete", role: .destructive) {
                modelContext.delete(goal)
                syncReminders()
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: goal.colorHex).opacity(0.2))
                    .frame(width: 48, height: 48)
                if let emoji = goal.emoji {
                    Text(emoji).font(.title2)
                } else {
                    Image(systemName: "target").foregroundStyle(Color(hex: goal.colorHex))
                }
            }
            if let categoryName = goal.category?.name {
                Text(categoryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var progressRow: some View {
        switch goal.trackingMode {
        case .value:
            HStack {
                Text(formattedValue(goal.currentValue))
                Text("/")
                    .foregroundStyle(.secondary)
                Text(formattedValue(goal.targetValue))
                Text(goal.unitDisplayText)
                    .foregroundStyle(.secondary)
            }
            .font(.title3.monospacedDigit())
        case .milestones:
            HStack {
                Text("\(goal.completedMilestoneCount)")
                Text("/")
                    .foregroundStyle(.secondary)
                Text("\(goal.milestones.count)")
                Text("milestone.unit")
                    .foregroundStyle(.secondary)
            }
            .font(.title3.monospacedDigit())
        }
    }

    private var logButtonTitle: LocalizedStringKey {
        goal.trackingMode == .value ? "goalDetail.logValue" : "goalDetail.checkInToday"
    }

    /// A plain-language pace readout ("aim for 4 km a day" / "you'll get there around March") —
    /// Pro-only, and only shown at all when there's actually something to say (not for a goal
    /// that's already done, or one with neither a deadline nor any history to project from).
    @ViewBuilder
    private var paceRow: some View {
        if let insight = GoalPaceInsight.compute(for: goal) {
            if purchaseManager.isProUnlocked {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(hex: goal.colorHex))
                    Text(insight.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            } else {
                ProLockedCard(title: "pace.title", message: "pace.locked", systemImage: "sparkles")
            }
        }
    }

    @ViewBuilder
    private var progressChartSection: some View {
        Section("goalDetail.chart.title") {
            if purchaseManager.isProUnlocked {
                Picker("stats.range", selection: $chartRange) {
                    ForEach(StatsRange.allCases) { range in
                        Text(range.localizedName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                GoalProgressChartView(goal: goal, range: chartRange)
            } else {
                ProLockedCard(title: "goalDetail.chart.title", message: "goalDetail.chart.locked", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    /// The check-in calendar grid, moved here from the Statistics tab — that screen is meant for
    /// scanning across goals, this one for a single goal in depth.
    private var activitySection: some View {
        Section("goalDetail.activity") {
            Picker("stats.range", selection: $activityRange) {
                ForEach(StatsRange.allCases) { range in
                    Text(range.localizedName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScheduleActivityView(goal: goal, range: activityRange)
        }
    }

    /// Read-only summary of the reminder — set from Edit, shown here so it doesn't disappear
    /// the moment you leave the edit sheet.
    @ViewBuilder
    private var reminderSection: some View {
        Section("reminder.title") {
            if goal.isReminderOn {
                LabeledContent("reminder.frequency", value: goal.reminderFrequency.localizedName)
                LabeledContent("reminder.time", value: reminderTimeText)
                if goal.reminderFrequency == .weekly {
                    LabeledContent("reminder.weekdays", value: reminderWeekdaysText)
                }
            } else {
                LabeledContent("reminder.title", value: String(localized: "reminder.status.off", bundle: AppLanguage.currentBundle))
            }
        }
    }

    private var reminderTimeText: String {
        let components = DateComponents(hour: goal.reminderHour, minute: goal.reminderMinute)
        let time = Calendar.current.date(from: components) ?? .now
        return time.formatted(date: .omitted, time: .shortened)
    }

    private var reminderWeekdaysText: String {
        goal.reminderWeekdays.sorted().map(Recurrence.weekdayAbbreviation).joined(separator: ", ")
    }

    /// One-tap increments, pointing down for goals where lower is better.
    private var quickAddChips: some View {
        let steps = GoalUnit(rawValue: goal.unitKey)?.quickAddSteps ?? [1, 2, 5, 10]
        return HStack(spacing: 8) {
            ForEach(steps, id: \.self) { step in
                let delta = goal.isLowerBetter ? -step : step
                Button {
                    logDelta(delta)
                } label: {
                    Text(signedLabel(for: delta))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(hex: goal.colorHex).opacity(0.15))
                        .foregroundStyle(Color(hex: goal.colorHex))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func signedLabel(for delta: Double) -> String {
        let sign = delta < 0 ? "−" : "+"
        return sign + formattedValue(abs(delta))
    }

    private func logDelta(_ delta: Double) {
        ProgressLogger.record(value: max(goal.currentValue + delta, 0), for: goal, in: modelContext)
    }

    private func formattedValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// A completed, archived or deleted goal shouldn't keep reminding.
    private func syncReminders() {
        let context = modelContext
        Task { await NotificationScheduler.syncAll(context: context) }
    }

    private func addMilestone() {
        let trimmed = newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let milestone = Milestone(title: trimmed, order: goal.milestones.count, goal: goal)
        modelContext.insert(milestone)
        newMilestoneTitle = ""
    }

    private func deleteMilestones(at offsets: IndexSet) {
        let milestones = sortedMilestones
        for index in offsets {
            modelContext.delete(milestones[index])
        }
    }
}

private struct MilestoneRow: View {
    @Bindable var milestone: Milestone

    var body: some View {
        Button {
            milestone.isCompleted.toggle()
        } label: {
            HStack {
                Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(milestone.isCompleted ? .green : .secondary)
                Text(milestone.title)
                    .strikethrough(milestone.isCompleted)
                    .foregroundStyle(milestone.isCompleted ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CheckInRow: View {
    let checkIn: CheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(checkIn.date, style: .date)
                    .font(.subheadline)
                if let value = checkIn.valueSnapshot {
                    Spacer()
                    Text(value.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let note = checkIn.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        GoalDetailView(goal: Goal(title: "Run 100 km", targetValue: 100, currentValue: 20, unitKey: GoalUnit.km.rawValue))
    }
    .environment(PurchaseManager())
    .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
