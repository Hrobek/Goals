//
//  AddEditGoalView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct AddEditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let goal: Goal?

    @State private var title: String
    @State private var category: Category?
    @State private var priority: GoalPriority
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var trackingMode: GoalTrackingMode
    @State private var startValueText: String
    @State private var targetValueText: String
    @State private var isLowerBetter: Bool
    @State private var unitSelection: UnitSelection
    @State private var milestoneDrafts: [MilestoneDraft]
    @State private var newMilestoneTitle = ""
    @State private var emoji: String?
    /// Kept even though the scheme is mono and nothing paints with it any more: the model still
    /// carries a colour per goal, and dropping it here would rewrite every edited goal's stored
    /// value. It rides through untouched.
    @State private var colorHex: String
    @State private var recurrenceType: RecurrenceType
    @State private var recurrenceWeekdays: Set<Int>
    @State private var recurrenceDaysOfMonth: Set<Int>
    @State private var recurrenceCount: Int
    @State private var isReminderOn: Bool
    @State private var reminderFrequency: ReminderFrequency
    @State private var reminderTime: Date
    @State private var reminderWeekdays: Set<Int>
    @State private var widgetAction: WidgetAction
    @State private var widgetAmountText: String

    @State private var isShowingPermissionAlert = false
    @State private var isShowingEmojiPicker = false
    @State private var isShowingCategoryPicker = false
    @State private var isShowingUnitPicker = false

    init(goal: Goal?) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _category = State(initialValue: goal?.category)
        _priority = State(initialValue: goal?.priority ?? .medium)
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline ?? Date().addingTimeInterval(7 * 24 * 3600))
        _trackingMode = State(initialValue: goal?.trackingMode ?? .value)
        // The literal fallbacks are written as `0.0`/`1.0`, not `0`/`1`: an Int literal defaulting
        // to Double through `??` still triggers Foundation's runtime format-string checker to
        // flag "%g" as expecting "%lld" — a spurious but noisy Fault log. Writing them as Double
        // literals from the start avoids it.
        _startValueText = State(initialValue: String(format: "%g", goal?.startValue ?? 0.0))
        _targetValueText = State(initialValue: goal.map { String(format: "%g", $0.targetValue) } ?? "")
        _isLowerBetter = State(initialValue: goal?.isLowerBetter ?? false)
        _unitSelection = State(initialValue: UnitSelection(
            unitKey: goal?.unitKey ?? GoalUnit.times.rawValue,
            customUnitText: goal?.customUnitText
        ))
        _milestoneDrafts = State(initialValue: (goal?.sortedMilestones ?? []).map {
            MilestoneDraft(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
        })
        _emoji = State(initialValue: goal?.emoji)
        _colorHex = State(initialValue: goal?.colorHex ?? ColorPalette.defaultHex)
        _recurrenceType = State(initialValue: goal?.recurrenceType ?? .daily)
        _recurrenceWeekdays = State(initialValue: Set(goal?.recurrenceWeekdays ?? []))
        _recurrenceDaysOfMonth = State(initialValue: Set(goal?.recurrenceDaysOfMonth ?? []))
        _recurrenceCount = State(initialValue: goal?.recurrenceCount ?? 3)
        _isReminderOn = State(initialValue: goal?.isReminderOn ?? false)
        _reminderFrequency = State(initialValue: goal?.reminderFrequency ?? .daily)
        _reminderTime = State(initialValue: Calendar.current.date(
            bySettingHour: goal?.reminderHour ?? 9,
            minute: goal?.reminderMinute ?? 0,
            second: 0,
            of: .now
        ) ?? .now)
        _reminderWeekdays = State(initialValue: Set(goal?.reminderWeekdays ?? []))
        _widgetAction = State(initialValue: goal?.widgetAction ?? .quickAction)
        _widgetAmountText = State(initialValue: String(format: "%g", goal?.widgetQuickAmount
            ?? GoalUnit(rawValue: goal?.unitKey ?? GoalUnit.times.rawValue)?.quickAddSteps.first
            ?? 1.0))
    }

    private var parsedStartValue: Double {
        Double(startValueText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var parsedTargetValue: Double? {
        guard let value = Double(targetValueText.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return nil }
        return value
    }

    /// The target has to sit on the far side of the starting value, or there's nothing to track.
    private var isRangeValid: Bool {
        guard let target = parsedTargetValue else { return false }
        return isLowerBetter ? parsedStartValue > target : target > parsedStartValue
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard trackingMode == .value else { return true }
        return isRangeValid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    identityRow
                    basicsSection
                    trackingSection
                    recurrenceSection
                    reminderSection
                    widgetSection
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .screenGround()
            .navigationTitle(goal == nil
                ? String(localized: "goal.new.title", bundle: AppLanguage.currentBundle)
                : String(localized: "goal.edit.title", bundle: AppLanguage.currentBundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Theme.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .foregroundStyle(isValid ? Theme.accentText : Theme.textGhost)
                        .disabled(!isValid)
                }
            }
            .onChange(of: isReminderOn) { _, isOn in
                guard isOn else { return }
                // Weekly with nothing selected would schedule nothing at all, so start from today.
                if reminderWeekdays.isEmpty {
                    reminderWeekdays = [Calendar.current.component(.weekday, from: .now)]
                }
                Task {
                    if await NotificationScheduler.requestAuthorization() == false {
                        isReminderOn = false
                        isShowingPermissionAlert = true
                    }
                }
            }
            .alert("reminder.permission.title", isPresented: $isShowingPermissionAlert) {
                Button("reminder.permission.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("reminder.permission.message")
            }
            .sheet(isPresented: $isShowingEmojiPicker) {
                EmojiPickerSheet(selection: $emoji)
            }
            .sheet(isPresented: $isShowingCategoryPicker) {
                CategoryPickerSheet(selection: $category)
            }
            .sheet(isPresented: $isShowingUnitPicker) {
                UnitPickerSheet(selection: $unitSelection)
            }
        }
    }

    // MARK: - Identity

    /// The two things that make a goal recognisable: its emoji and its name. The dashed ring says
    /// the emoji is a thing you pick, not decoration the app chose.
    private var identityRow: some View {
        HStack(spacing: 14) {
            Button {
                isShowingEmojiPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.control)
                        .overlay {
                            Circle().strokeBorder(
                                Theme.textFaint,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                        }
                    if let emoji {
                        Text(emoji).font(.system(size: 26))
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("goal.field.emoji"))

            VStack(alignment: .leading, spacing: 9) {
                TextField("goal.field.title", text: $title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                Rectangle()
                    .fill(Theme.textGhost)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        CardGroup {
            DisclosureRow(label: "goal.field.category", value: category?.name) {
                isShowingCategoryPicker = true
            }
            RowDivider()
            MenuRow(
                label: "goal.field.priority",
                options: GoalPriority.allCases,
                selection: $priority,
                title: { $0.localizedName }
            )
            RowDivider()
            SwitchRow(label: "goal.field.hasDeadline", isOn: $hasDeadline.animation())
            if hasDeadline {
                RowDivider()
                HStack {
                    Text("goal.field.deadline")
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.textMuted)
                    Spacer(minLength: 10)
                    DatePicker("goal.field.deadline", selection: $deadline, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.vertical, 9)
            }
        }
    }

    @ViewBuilder
    private var trackingSection: some View {
        LabeledSection("goal.field.trackingMode") {
            VStack(alignment: .leading, spacing: Theme.Space.card) {
                SegmentStrip(
                    options: GoalTrackingMode.allCases,
                    selection: $trackingMode.animation(),
                    title: { $0.localizedName }
                )

                switch trackingMode {
                case .value:
                    CardGroup {
                        SwitchRow(label: "goal.field.lowerIsBetter", isOn: $isLowerBetter)
                        RowDivider()
                        TextFieldRow(label: "goal.field.startValue", text: $startValueText, keyboard: .decimalPad)
                        RowDivider()
                        TextFieldRow(label: "goal.field.targetValue", text: $targetValueText, keyboard: .decimalPad)
                        RowDivider()
                        DisclosureRow(label: "goal.field.unit", value: unitSelection.displayText) {
                            isShowingUnitPicker = true
                        }
                    }
                    if !targetValueText.isEmpty, !isRangeValid {
                        Text(isLowerBetter ? "goal.field.range.lower" : "goal.field.range.higher")
                            .font(Theme.Typo.footnote)
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 4)
                    }
                case .milestones:
                    milestonesCard
                }
            }
        }
    }

    private var milestonesCard: some View {
        CardGroup {
            ForEach($milestoneDrafts) { $draft in
                HStack(spacing: 11) {
                    Image(systemName: draft.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(draft.isCompleted ? Theme.accent : Theme.textGhost)
                        .accessibilityHidden(true)
                    TextField("goalDetail.newMilestone", text: $draft.title)
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                    Button {
                        milestoneDrafts.removeAll { $0.id == draft.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.textGhost)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("action.delete"))
                }
                .padding(.vertical, 11)
                RowDivider()
            }

            HStack(spacing: 11) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                TextField("goalDetail.newMilestone", text: $newMilestoneTitle)
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.text)
                    .submitLabel(.done)
                    .onSubmit { addMilestoneDraft() }
                Button {
                    addMilestoneDraft()
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
            .padding(.vertical, 11)
        }
    }

    private var recurrenceSection: some View {
        LabeledSection("goal.field.recurrence") {
            CardGroup {
                MenuRow(
                    label: "goal.field.recurrence",
                    options: RecurrenceType.allCases,
                    selection: $recurrenceType.animation(),
                    title: { $0.localizedName }
                )

                switch recurrenceType {
                case .daily:
                    EmptyView()
                case .specificWeekdays:
                    RowDivider()
                    weekdayChips(selection: $recurrenceWeekdays)
                        .padding(.vertical, 14)
                case .timesPerWeek:
                    RowDivider()
                    Stepper(value: $recurrenceCount, in: 1...7) {
                        Text("recurrence.timesPerWeek.count \(recurrenceCount)")
                            .font(Theme.Typo.row)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 9)
                case .specificDaysOfMonth:
                    RowDivider()
                    daysOfMonthGrid
                        .padding(.vertical, 14)
                case .timesPerMonth:
                    RowDivider()
                    Stepper(value: $recurrenceCount, in: 1...31) {
                        Text("recurrence.timesPerMonth.count \(recurrenceCount)")
                            .font(Theme.Typo.row)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 9)
                }
            }
        }
    }

    private var reminderSection: some View {
        LabeledSection("reminder.title") {
            VStack(alignment: .leading, spacing: 8) {
                CardGroup {
                    SwitchRow(label: "reminder.enabled", isOn: $isReminderOn.animation())

                    if isReminderOn {
                        RowDivider()
                        MenuRow(
                            label: "reminder.frequency",
                            options: ReminderFrequency.allCases,
                            selection: $reminderFrequency.animation(),
                            title: { $0.localizedName }
                        )
                        RowDivider()
                        HStack {
                            Text("reminder.time")
                                .font(Theme.Typo.row)
                                .foregroundStyle(Theme.textMuted)
                            Spacer(minLength: 10)
                            DatePicker("reminder.time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.vertical, 9)

                        if reminderFrequency == .weekly {
                            RowDivider()
                            weekdayChips(selection: $reminderWeekdays)
                                .padding(.vertical, 14)
                        }
                    }
                }

                if isReminderOn, reminderFrequency == .weekly, reminderWeekdays.isEmpty {
                    Text("reminder.pickDays")
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var widgetSection: some View {
        LabeledSection("widget.title") {
            VStack(alignment: .leading, spacing: 8) {
                SegmentStrip(
                    options: WidgetAction.allCases,
                    selection: $widgetAction.animation(),
                    title: { $0.localizedName }
                )

                if widgetAction == .quickAction, trackingMode == .value {
                    CardGroup {
                        TextFieldRow(
                            label: "widget.amount",
                            text: $widgetAmountText,
                            keyboard: .decimalPad,
                            suffix: unitSelection.displayText
                        )
                    }
                }

                if widgetAction == .quickAction, trackingMode == .milestones {
                    Text("widget.milestoneHint")
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.textGhost)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Day pickers

    private func weekdayChips(selection: Binding<Set<Int>>) -> some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selection.wrappedValue.contains(day)
                Button {
                    if isSelected {
                        selection.wrappedValue.remove(day)
                    } else {
                        selection.wrappedValue.insert(day)
                    }
                } label: {
                    Text(Recurrence.weekdayAbbreviation(day))
                        .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(isSelected ? Theme.accent : Theme.control, in: .capsule)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var daysOfMonthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(1...31, id: \.self) { day in
                let isSelected = recurrenceDaysOfMonth.contains(day)
                Button {
                    if isSelected {
                        recurrenceDaysOfMonth.remove(day)
                    } else {
                        recurrenceDaysOfMonth.insert(day)
                    }
                } label: {
                    Text("\(day)")
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .monospacedDigit()
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Theme.accent : Theme.control, in: .circle)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func addMilestoneDraft() {
        let trimmed = newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        milestoneDrafts.append(MilestoneDraft(id: UUID(), title: trimmed, isCompleted: false))
        newMilestoneTitle = ""
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = parsedStartValue
        let target = parsedTargetValue ?? 1
        let sortedWeekdays = recurrenceWeekdays.sorted()
        let sortedDaysOfMonth = recurrenceDaysOfMonth.sorted()

        let saved: Goal
        if let goal {
            goal.title = trimmedTitle
            goal.category = category
            goal.priority = priority
            goal.deadline = hasDeadline ? deadline : nil
            // Flipping the direction puts the value on a different scale (a counted-up 1.25 kg is
            // not a weigh-in), so the current value goes back to the starting point — as it does
            // while nothing has been logged yet.
            let directionChanged = goal.isLowerBetter != isLowerBetter
            goal.trackingMode = trackingMode
            goal.startValue = start
            goal.targetValue = target
            goal.isLowerBetter = isLowerBetter
            if goal.checkIns.isEmpty || directionChanged {
                goal.currentValue = start
            }
            goal.unitKey = unitSelection.unitKey
            goal.customUnitText = unitSelection.customUnitText
            goal.colorHex = colorHex
            goal.emoji = emoji
            goal.recurrenceType = recurrenceType
            goal.recurrenceWeekdays = sortedWeekdays
            goal.recurrenceDaysOfMonth = sortedDaysOfMonth
            goal.recurrenceCount = recurrenceCount
            saved = goal
        } else {
            let newGoal = Goal(
                title: trimmedTitle,
                category: category,
                deadline: hasDeadline ? deadline : nil,
                priority: priority,
                trackingMode: trackingMode,
                startValue: start,
                targetValue: target,
                currentValue: start,
                isLowerBetter: isLowerBetter,
                unitKey: unitSelection.unitKey,
                customUnitText: unitSelection.customUnitText,
                colorHex: colorHex,
                emoji: emoji,
                recurrenceType: recurrenceType,
                recurrenceWeekdays: sortedWeekdays,
                recurrenceDaysOfMonth: sortedDaysOfMonth,
                recurrenceCount: recurrenceCount
            )
            modelContext.insert(newGoal)
            saved = newGoal
            Analytics.send(.goalCreated, [
                .trackingMode: trackingMode.rawValue,
                .priority: priority.rawValue,
                .hasDeadline: String(hasDeadline)
            ])
        }

        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        saved.isReminderOn = isReminderOn
        saved.reminderFrequency = reminderFrequency
        saved.reminderHour = time.hour ?? 9
        saved.reminderMinute = time.minute ?? 0
        saved.reminderWeekdays = Array(reminderWeekdays)
        saved.widgetAction = widgetAction
        if let amount = Double(widgetAmountText.replacingOccurrences(of: ",", with: ".")), amount > 0 {
            saved.widgetQuickAmount = amount
        }

        if trackingMode == .milestones {
            syncMilestones(for: saved)
        }

        let context = modelContext
        Task { await NotificationScheduler.syncAll(context: context) }
        dismiss()
    }

    /// Applies the edited drafts onto the goal: drops removed milestones, renames the kept ones
    /// and inserts the new ones, keeping list order.
    private func syncMilestones(for goal: Goal) {
        let drafts = milestoneDrafts
            .map { MilestoneDraft(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), isCompleted: $0.isCompleted) }
            .filter { !$0.title.isEmpty }
        let draftIDs = Set(drafts.map(\.id))

        let existing = goal.milestones
        for milestone in existing where !draftIDs.contains(milestone.id) {
            modelContext.delete(milestone)
        }

        var existingByID: [UUID: Milestone] = [:]
        for milestone in existing {
            existingByID[milestone.id] = milestone
        }

        for (index, draft) in drafts.enumerated() {
            if let milestone = existingByID[draft.id] {
                milestone.title = draft.title
                milestone.order = index
            } else {
                modelContext.insert(Milestone(id: draft.id, title: draft.title, order: index, goal: goal))
            }
        }
    }
}

private struct MilestoneDraft: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

#Preview {
    AddEditGoalView(goal: nil)
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self], inMemory: true)
}
