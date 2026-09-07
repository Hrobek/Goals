//
//  GoalDetailView.swift
//  Goals
//

import SwiftUI
import SwiftData
import StoreKit

struct GoalDetailView: View {
    @Bindable var goal: Goal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var isShowingEdit = false
    @State private var isShowingCheckIn = false
    @State private var isShowingDeleteConfirmation = false
    @State private var shareImage: Image?
    @State private var newMilestoneTitle = ""
    @State private var activityRange: StatsRange = .month
    @State private var activityOffset = 0
    @State private var chartRange: StatsRange = .month
    @State private var chartOffset = 0
    /// Bumped on every logged amount. The goal's own value can't drive the haptic — editing the
    /// goal changes it too, and that shouldn't feel like progress.
    @State private var logTick = 0
    /// The one-off overlay shown when a check-in finishes the goal or lands on a streak milestone.
    @State private var celebration: GoalCelebration?
    /// Completion + streak state captured when the check-in sheet opens, so its callback can tell
    /// whether the log that just happened crossed a line.
    @State private var checkInSheetSnapshot: (wasCompleted: Bool, streak: Int)?
    /// The amount the most recently tapped quick-add chip actually applied, so "undo" reverses
    /// *that* — not always the widget's own configured step, which is a different number and
    /// would otherwise turn one stray tap on a big chip into a hunt of tiny corrections.
    /// Cleared once used, and by anything that logs progress a different way.
    @State private var lastLoggedDelta: Double?
    /// A long press on "undo" opens this instead of firing the smart default — for correcting by
    /// an amount that's neither the last chip nor the widget's own step.
    @State private var isShowingSubtractPrompt = false
    @State private var subtractAmountText = ""

    /// Runs a check-in mutation and raises the celebration overlay if it finished the goal or hit
    /// a streak milestone. The snapshot has to be taken before `action` runs.
    private func loggingCheckIn(_ action: () -> Void) {
        let wasCompleted = goal.isCompleted
        let previousStreak = StreakCalculator.currentStreak(for: goal)
        action()
        logTick += 1
        if let event = GoalCelebration.afterCheckIn(goal: goal, wasCompleted: wasCompleted, previousStreak: previousStreak) {
            celebration = event
        }
    }

    /// Clears the overlay, then — only for an actual finish, not a streak milestone — asks
    /// `AppReviewPrompt` whether this is one of the rare turns it gets to bring up the rating
    /// prompt. Right after watching the goal you've been working on get checked off is the best
    /// mood the app is ever going to catch someone in; a prompt at random app launch never was.
    private func dismissCelebration() {
        let isCompletion = celebration?.isCompletion ?? false
        celebration = nil
        if isCompletion {
            requestReviewIfEarned()
        }
    }

    private func requestReviewIfEarned() {
        Task {
            let ownerId = goal.ownerId
            let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate<CheckIn> { $0.ownerId == ownerId })
            let checkInCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            guard AppReviewPrompt.shouldRequest(checkInCount: checkInCount) else { return }

            // A beat after the celebration has actually cleared the screen, not on top of it.
            try? await Task.sleep(for: .seconds(0.4))
            AppReviewPrompt.recordRequest()
            requestReview()
        }
    }

    private var sortedMilestones: [Milestone] {
        goal.sortedMilestones
    }

    private var sortedCheckIns: [CheckIn] {
        goal.checkIns.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header

                VStack(alignment: .leading, spacing: Theme.Space.card) {
                    progressPanel
                    if goal.trackingMode == .value {
                        quickAddChips
                    }
                    paceRow
                    logButton
                    completedToggle
                }

                if goal.trackingMode == .value {
                    progressChartSection
                }

                activitySection
                scheduleSection
                reminderSection

                if goal.trackingMode == .milestones {
                    milestonesSection
                }

                if !sortedCheckIns.isEmpty {
                    historySection
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .screenGround()
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { navBar }
        .task(id: shareSignature) {
            shareImage = ShareCard.image(for: shareData)
        }
        // Logging something is a light tap; finishing the goal or hitting a streak milestone gets
        // the celebration overlay (which brings its own success haptic). Both completion and the
        // streak count are watched as transitions, so they fire on the check-in that crosses the
        // line — not every time a finished goal is opened.
        .sensoryFeedback(.impact(weight: .light), trigger: logTick)
        .overlay {
            if let celebration {
                GoalCelebrationView(celebration: celebration) { dismissCelebration() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: celebration)
        .sheet(isPresented: $isShowingEdit) {
            AddEditGoalView(goal: goal, userId: goal.ownerId)
        }
        .sheet(isPresented: $isShowingCheckIn, onDismiss: { checkInSheetSnapshot = nil }) {
            CheckInSheetView(goal: goal) {
                logTick += 1
                // An explicit typed-in value replaces whatever a chip last added — "undo" should
                // go back to correcting the widget's own step, not this now-stale amount.
                lastLoggedDelta = nil
                if let snapshot = checkInSheetSnapshot,
                   let event = GoalCelebration.afterCheckIn(goal: goal, wasCompleted: snapshot.wasCompleted, previousStreak: snapshot.streak) {
                    celebration = event
                }
            }
        }
        .confirmationDialog("goalDetail.deleteConfirm.title", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("action.delete", role: .destructive) {
                modelContext.delete(goal)
                syncReminders()
                dismiss()
            }
        }
    }

    // MARK: - Chrome

    /// The screen draws its own bar: the system one can't carry the ground colour through without
    /// a translucent grey seam appearing over the dark surface.
    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textStrong)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("action.cancel"))

            Spacer()

            Menu {
                Button {
                    isShowingEdit = true
                } label: {
                    Label("action.edit", systemImage: "pencil")
                }
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(Text(verbatim: goal.title), image: shareImage)
                    ) {
                        Label("action.share", systemImage: "square.and.arrow.up")
                    }
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
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.textStrong)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("a11y.goalOptions"))
        }
        .padding(.horizontal, 12)
        .background(Theme.ground)
    }

    private var header: some View {
        HStack(spacing: 14) {
            GoalBadge(emoji: goal.emoji, size: 52)
                .accessibilityHidden(true)
            // The bar carries no title, so the goal's name is spelled out here in full alongside
            // its emoji, category and priority.
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(Theme.Typo.pageTitle)
                    .tracking(Theme.Typo.pageTitleTracking)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitleText)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let categoryName = goal.category?.displayName { parts.append(categoryName) }
        parts.append(goal.priority.localizedName)
        if let deadline = goal.deadline {
            parts.append(deadline.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Progress

    private var progressPanel: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: goal.progressFraction)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("goalDetail.progress")
                progressValue
                    .padding(.top, 6)
                HStack(spacing: 7) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accentBright)
                    Text(streakText)
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

    private var streakText: String {
        let streak = StreakCalculator.currentStreak(for: goal)
        return "\(streak) · \(Recurrence.localizedSummary(for: goal))"
    }

    @ViewBuilder
    private var progressValue: some View {
        switch goal.trackingMode {
        case .value:
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(formattedValue(goal.currentValue))
                    .font(Theme.Typo.statLarge)
                    .foregroundStyle(Theme.text)
                Text(verbatim: "/ \(goal.valueWithUnit(goal.targetValue, formattedValue: formattedValue(goal.targetValue)))")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textFaint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("a11y.progress \(formattedValue(goal.currentValue)) \(goal.valueWithUnit(goal.targetValue, formattedValue: formattedValue(goal.targetValue)))"))
        case .milestones:
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(goal.completedMilestoneCount)")
                    .font(Theme.Typo.statLarge)
                    .foregroundStyle(Theme.text)
                Text("milestone.unit.count \(goal.milestones.count)")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textFaint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("a11y.progress \(goal.completedMilestoneCount.formatted()) \(String(localized: "milestone.unit.count \(goal.milestones.count)", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale))"))
        }
    }

    private var logButton: some View {
        Button {
            checkInSheetSnapshot = (goal.isCompleted, StreakCalculator.currentStreak(for: goal))
            isShowingCheckIn = true
        } label: {
            Label(logButtonTitle, systemImage: goal.trackingMode == .value ? "plus.circle" : "checkmark.circle")
        }
        .buttonStyle(AccentButtonStyle())
    }

    private var logButtonTitle: LocalizedStringKey {
        goal.trackingMode == .value ? "goalDetail.logValue" : "goalDetail.checkInToday"
    }

    private var completedToggle: some View {
        CardGroup {
            SwitchRow(label: "goalDetail.markCompleted", isOn: $goal.isCompleted)
                .onChange(of: goal.isCompleted) { wasCompleted, isCompleted in
                    syncReminders()
                    if !wasCompleted, isCompleted {
                        celebration = .completed(
                            days: Calendar.current.dateComponents(
                                [.day], from: Calendar.current.startOfDay(for: goal.createdAt), to: .now
                            ).day ?? 0,
                            streak: StreakCalculator.currentStreak(for: goal)
                        )
                    }
                }
        }
    }

    /// A plain-language pace readout ("aim for 4 km a day" / "you'll get there around March") —
    /// Pro-only, and with Pro on, only shown when there's actually something to say (not for a
    /// goal that's already done, or one with neither a deadline nor any history to project from).
    /// Without Pro it's the locked teaser instead, which is also the only place a milestone goal
    /// advertises the trend features at all — it has no progress chart section to lock.
    @ViewBuilder
    private var paceRow: some View {
        if purchaseManager.isProUnlocked {
            if let insight = GoalPaceInsight.compute(for: goal) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(insight.message)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.textStrong)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                // The accent edge is what marks this as the app talking rather than reporting.
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 2)
                        .padding(.vertical, 1)
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.card))
            }
        } else {
            // Unconditional for a free user, unlike the unlocked version: whether there's an
            // insight to show is itself something only Pro can answer, so hiding the teaser on a
            // goal that happens to have nothing to say would make the feature look absent.
            ProLockedCard(title: "pace.title", message: "pace.locked")
        }
    }

    @ViewBuilder
    private var progressChartSection: some View {
        LabeledSection("goalDetail.chart.title") {
            if purchaseManager.isProUnlocked {
                VStack(spacing: 12) {
                    SegmentStrip(options: StatsRange.allCases, selection: $chartRange, title: { $0.localizedName })
                        .onChange(of: chartRange) { chartOffset = 0 }
                    PeriodNavigator(range: chartRange, offset: $chartOffset)
                    GoalProgressChartView(goal: goal, range: chartRange, offset: chartOffset)
                }
                .cardSurface()
            } else {
                ProLockedCard(title: "goalDetail.chart.title", message: "goalDetail.chart.locked")
            }
        }
    }

    /// The check-in calendar grid, moved here from the Statistics tab — that screen is meant for
    /// scanning across goals, this one for a single goal in depth.
    private var activitySection: some View {
        LabeledSection("goalDetail.activity") {
            VStack(spacing: 12) {
                SegmentStrip(options: StatsRange.allCases, selection: $activityRange, title: { $0.localizedName })
                    .onChange(of: activityRange) { activityOffset = 0 }
                PeriodNavigator(range: activityRange, offset: $activityOffset)
                ScheduleActivityView(schedule: goal, range: activityRange, offset: activityOffset)
            }
            .cardSurface()
        }
    }

    private var scheduleSection: some View {
        LabeledSection("goalDetail.schedule") {
            CardGroup {
                ValueRow("goalDetail.schedule", value: Recurrence.localizedSummary(for: goal))
                RowDivider()
                ValueRow("goalDetail.streak", value: "\(StreakCalculator.currentStreak(for: goal))")
            }
        }
    }

    /// Read-only summary of the reminder — set from Edit, shown here so it doesn't disappear
    /// the moment you leave the edit sheet.
    private var reminderSection: some View {
        LabeledSection("reminder.title") {
            CardGroup {
                if goal.isReminderOn {
                    ValueRow("reminder.frequency", value: goal.reminderFrequency.localizedName)
                    RowDivider()
                    ValueRow(goal.reminderTimes.count > 1 ? "reminder.times" : "reminder.time", value: reminderTimeText)
                    if goal.reminderFrequency == .weekly {
                        RowDivider()
                        ValueRow("reminder.weekdays", value: reminderWeekdaysText)
                    }
                } else {
                    ValueRow("reminder.title", value: String(localized: "reminder.status.off", bundle: AppLanguage.currentBundle))
                }
            }
        }
    }

    private var reminderTimeText: String {
        goal.reminderTimes
            .map { minutes in
                let date = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now
                return date.formatted(date: .omitted, time: .shortened)
            }
            .joined(separator: ", ")
    }

    private var reminderWeekdaysText: String {
        goal.reminderWeekdays.sorted().map(Recurrence.weekdayAbbreviation).joined(separator: ", ")
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        LabeledSection("goalDetail.milestones") {
            CardGroup {
                ForEach(sortedMilestones) { milestone in
                    MilestoneRow(milestone: milestone, goal: goal, modelContext: modelContext) { celebration = $0 }
                        // The card isn't a List any more, so the swipe that used to remove a
                        // milestone becomes a long press instead.
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(milestone)
                            } label: {
                                Label("action.delete", systemImage: "trash")
                            }
                        }
                    RowDivider()
                }
                HStack(spacing: 11) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    TextField("goalDetail.newMilestone", text: $newMilestoneTitle)
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                        .submitLabel(.done)
                        .onSubmit { addMilestone() }
                    Button {
                        addMilestone()
                    } label: {
                        Text("action.save")
                            .font(Theme.Typo.captionEmphasis)
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                    .disabled(newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
                    .accessibilityLabel(Text("a11y.addMilestone"))
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var historySection: some View {
        LabeledSection("goalDetail.history") {
            CardGroup {
                ForEach(Array(sortedCheckIns.prefix(20).enumerated()), id: \.element.id) { index, checkIn in
                    if index > 0 { RowDivider() }
                    CheckInRow(checkIn: checkIn)
                }
            }
        }
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
                // "+250" spoken aloud is a number with a sign in front of it; what the button
                // actually does — and in what unit — has to be said.
                .accessibilityLabel(quickAddLabel(for: delta))
            }
            undoQuickActionButton
        }
    }

    /// What the next tap of "undo" reverses: whichever quick-add chip was tapped last in this
    /// session, or — before any chip has been, or after a typed-in check-in — the same step the
    /// Today row and widget button apply. Without this, tapping a big chip by mistake meant
    /// undoing it one small `widgetQuickAmount` at a time.
    private var undoQuickActionDelta: Double {
        if let lastLoggedDelta { return -lastLoggedDelta }
        return goal.isLowerBetter ? goal.widgetQuickAmount : -goal.widgetQuickAmount
    }

    /// False once the floor clamp at 0 would swallow the tap — e.g. at 0/50 there's nothing left
    /// to undo, so the button shouldn't pretend it can still act.
    private var canUndoQuickAction: Bool {
        max(goal.currentValue + undoQuickActionDelta, 0) != goal.currentValue
    }

    /// Not a `Button` — a `Button`'s own tap gesture wins a race against `.onLongPressGesture`
    /// bolted onto it, so a hold fired the short-tap action too. Plain tap/long-press gestures on
    /// the image itself keep the two properly distinct: a tap fires the smart default straight
    /// away (the fast path for "oops, wrong chip"), a long press opens a prompt to type the
    /// amount instead, for anything that default doesn't cover.
    private var undoQuickActionButton: some View {
        Image(systemName: "minus")
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(Theme.control, in: .rect(cornerRadius: Theme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(Theme.textGhost, lineWidth: 1)
            }
            .foregroundStyle(canUndoQuickAction ? Theme.textMuted : Theme.textGhost)
            .contentShape(.rect)
            .onTapGesture {
                guard canUndoQuickAction else { return }
                performUndo(delta: undoQuickActionDelta)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                guard canUndoQuickAction else { return }
                openSubtractPrompt()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(quickAddLabel(for: undoQuickActionDelta))
            .accessibilityAction(named: Text("goalDetail.subtractCustom.action")) { openSubtractPrompt() }
            .alert("goalDetail.subtractAmount.title", isPresented: $isShowingSubtractPrompt) {
                TextField("goalDetail.subtractAmount.placeholder", text: $subtractAmountText)
                    .keyboardType(.decimalPad)
                Button("action.cancel", role: .cancel) {}
                Button("goalDetail.subtractAmount.confirm") { confirmSubtractPrompt() }
            } message: {
                Text(goal.unitDisplayText)
            }
    }

    /// Doesn't go through `logDelta`/`record` — a correction shouldn't blindly touch today's
    /// check-in the way a real log does. See `ProgressLogger.undoQuickAction`.
    private func performUndo(delta: Double) {
        if ProgressLogger.undoQuickAction(on: goal, delta: delta, in: modelContext) {
            logTick += 1
            // One correction consumed; the next tap falls back to the widget's own step.
            lastLoggedDelta = nil
        }
    }

    /// Pre-fills with the same amount the quick tap would have used, so confirming without
    /// changing anything behaves exactly like the short-press default.
    private func openSubtractPrompt() {
        subtractAmountText = formattedValue(abs(undoQuickActionDelta))
        isShowingSubtractPrompt = true
    }

    private func confirmSubtractPrompt() {
        guard let magnitude = Double(subtractAmountText.replacingOccurrences(of: ",", with: ".")), magnitude > 0 else { return }
        performUndo(delta: goal.isLowerBetter ? magnitude : -magnitude)
    }

    private func quickAddLabel(for delta: Double) -> Text {
        let amount = goal.valueWithUnit(abs(delta), formattedValue: formattedValue(abs(delta)))
        return Text(delta < 0 ? "a11y.quickSubtract \(amount)" : "a11y.quickAdd \(amount)")
    }

    private func signedLabel(for delta: Double) -> String {
        let sign = delta < 0 ? "-" : "+"
        return sign + formattedValue(abs(delta))
    }

    private func logDelta(_ delta: Double) {
        let previousValue = goal.currentValue
        loggingCheckIn {
            ProgressLogger.record(value: max(goal.currentValue + delta, 0), for: goal, in: modelContext)
        }
        // The floor clamp at 0 can make the applied delta smaller than the chip's own number —
        // recording what actually happened, not what was asked for, keeps undo exact.
        lastLoggedDelta = goal.currentValue - previousValue
    }

    private func formattedValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: - Sharing

    private var shareSignature: String {
        "\(goal.id)|\(goal.currentValue)|\(goal.completedMilestoneCount)|\(goal.isCompleted)|\(goal.title)"
    }

    private var shareData: ProgressShareData {
        let headline: String
        switch goal.trackingMode {
        case .value:
            headline = goal.isCompleted
                ? String(localized: "shareCard.done", bundle: AppLanguage.currentBundle, locale: AppLanguage.current.locale)
                : "\(formattedValue(goal.currentValue)) / \(goal.valueWithUnit(goal.targetValue, formattedValue: formattedValue(goal.targetValue)))"
        case .milestones:
            headline = "\(goal.completedMilestoneCount) / \(goal.milestones.count)"
        }
        return ProgressShareData(
            title: goal.title,
            emoji: goal.emoji,
            tintHex: nil,
            fraction: goal.progressFraction,
            headline: headline,
            caption: goal.progressFraction.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.current.locale)),
            streak: StreakCalculator.currentStreak(for: goal),
            footNote: Recurrence.localizedSummary(for: goal)
        )
    }

    /// A completed, archived or deleted goal shouldn't keep reminding.
    private func syncReminders() {
        let context = modelContext
        let ownerId = goal.ownerId
        Task { await NotificationScheduler.syncAll(context: context, userId: ownerId) }
    }

    private func addMilestone() {
        let trimmed = newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let milestone = Milestone(ownerId: goal.ownerId, title: trimmed, order: goal.milestones.count, goal: goal)
        modelContext.insert(milestone)
        newMilestoneTitle = ""
    }
}

private struct MilestoneRow: View {
    @Bindable var milestone: Milestone
    let goal: Goal
    let modelContext: ModelContext
    /// Called with a celebration to show when ticking this milestone finishes the goal or lands
    /// on a streak milestone.
    var celebrate: (GoalCelebration) -> Void = { _ in }

    var body: some View {
        Button {
            let wasCompleted = goal.isCompleted
            let previousStreak = StreakCalculator.currentStreak(for: goal)
            ProgressLogger.toggleMilestone(milestone, on: goal, in: modelContext)
            if let event = GoalCelebration.afterCheckIn(goal: goal, wasCompleted: wasCompleted, previousStreak: previousStreak) {
                celebrate(event)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(milestone.isCompleted ? Theme.accent : Theme.textGhost)
                Text(milestone.title)
                    .font(Theme.Typo.row)
                    .strikethrough(milestone.isCompleted)
                    .foregroundStyle(milestone.isCompleted ? Theme.textFaint : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Ticked or not is carried by a red circle and a strikethrough — both invisible to
        // VoiceOver. The toggle trait makes it announce the state and say "double tap to toggle".
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(milestone.isCompleted ? "a11y.milestone.done" : "a11y.milestone.todo"))
        .sensoryFeedback(.selection, trigger: milestone.isCompleted)
    }
}

private struct CheckInRow: View {
    let checkIn: CheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(checkIn.date, style: .date)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.text)
                if let value = checkIn.valueSnapshot {
                    Spacer()
                    Text(value.formatted(.number.precision(.fractionLength(0...2))))
                        .font(Theme.Typo.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textFaint)
                }
            }
            if let note = checkIn.note, !note.isEmpty {
                Text(note)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        GoalDetailView(goal: Goal(ownerId: UUID(), title: "Run 100 km", targetValue: 100, currentValue: 20, unitKey: GoalUnit.km.rawValue))
    }
    .environment(PurchaseManager())
    .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
