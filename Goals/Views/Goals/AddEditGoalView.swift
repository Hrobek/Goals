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
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button {
                            isShowingEmojiPicker = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: colorHex).opacity(0.2))
                                    .frame(width: 56, height: 56)
                                if let emoji {
                                    Text(emoji).font(.title)
                                } else {
                                    Image(systemName: "target")
                                        .foregroundStyle(Color(hex: colorHex))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        TextField("goal.field.title", text: $title)
                    }

                    HStack(spacing: 10) {
                        ForEach(ColorPalette.hexValues, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if hex == colorHex {
                                        Circle().stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }

                Section {
                    disclosureRow(title: "goal.field.category", value: category?.name) {
                        isShowingCategoryPicker = true
                    }
                    Picker("goal.field.priority", selection: $priority) {
                        ForEach(GoalPriority.allCases) { priority in
                            Text(priority.localizedName).tag(priority)
                        }
                    }
                }

                Section {
                    Toggle("goal.field.hasDeadline", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("goal.field.deadline", selection: $deadline, displayedComponents: .date)
                    }
                }

                Section("goal.field.trackingMode") {
                    Picker("goal.field.trackingMode", selection: $trackingMode.animation()) {
                        ForEach(GoalTrackingMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                switch trackingMode {
                case .value:
                    Section {
                        Toggle("goal.field.lowerIsBetter", isOn: $isLowerBetter)
                        TextField("goal.field.startValue", text: $startValueText)
                            .keyboardType(.decimalPad)
                        TextField("goal.field.targetValue", text: $targetValueText)
                            .keyboardType(.decimalPad)
                        disclosureRow(title: "goal.field.unit", value: unitSelection.displayText) {
                            isShowingUnitPicker = true
                        }
                    } footer: {
                        if !targetValueText.isEmpty, !isRangeValid {
                            Text(isLowerBetter ? "goal.field.range.lower" : "goal.field.range.higher")
                                .foregroundStyle(.red)
                        }
                    }
                case .milestones:
                    Section("goalDetail.milestones") {
                        ForEach($milestoneDrafts) { $draft in
                            TextField("goalDetail.newMilestone", text: $draft.title)
                        }
                        .onDelete { milestoneDrafts.remove(atOffsets: $0) }
                        .onMove { milestoneDrafts.move(fromOffsets: $0, toOffset: $1) }

                        HStack {
                            TextField("goalDetail.newMilestone", text: $newMilestoneTitle)
                            Button {
                                addMilestoneDraft()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .disabled(newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                Section("goal.field.recurrence") {
                    Picker("goal.field.recurrence", selection: $recurrenceType.animation()) {
                        ForEach(RecurrenceType.allCases) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }

                    switch recurrenceType {
                    case .daily:
                        EmptyView()
                    case .specificWeekdays:
                        weekdayChips
                    case .timesPerWeek:
                        Stepper(
                            "recurrence.timesPerWeek.count \(recurrenceCount)",
                            value: $recurrenceCount, in: 1...7
                        )
                    case .specificDaysOfMonth:
                        daysOfMonthGrid
                    case .timesPerMonth:
                        Stepper(
                            "recurrence.timesPerMonth.count \(recurrenceCount)",
                            value: $recurrenceCount, in: 1...31
                        )
                    }
                }

                reminderSection
                widgetSection
            }
            .navigationTitle(goal == nil
                ? String(localized: "goal.new.title", bundle: AppLanguage.currentBundle)
                : String(localized: "goal.edit.title", bundle: AppLanguage.currentBundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
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

    private func disclosureRow(
        title: LocalizedStringKey,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value ?? "—")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var reminderSection: some View {
        Section {
            Toggle("reminder.enabled", isOn: $isReminderOn.animation())

            if isReminderOn {
                Picker("reminder.frequency", selection: $reminderFrequency.animation()) {
                    ForEach(ReminderFrequency.allCases) { frequency in
                        Text(frequency.localizedName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                DatePicker("reminder.time", selection: $reminderTime, displayedComponents: .hourAndMinute)

                if reminderFrequency == .weekly {
                    weekdayChips(selection: $reminderWeekdays)
                }
            }
        } header: {
            Text("reminder.title")
        } footer: {
            if isReminderOn, reminderFrequency == .weekly, reminderWeekdays.isEmpty {
                Text("reminder.pickDays")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var widgetSection: some View {
        Section {
            Picker("widget.action", selection: $widgetAction.animation()) {
                ForEach(WidgetAction.allCases) { action in
                    Text(action.localizedName).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if widgetAction == .quickAction, trackingMode == .value {
                HStack {
                    Text("widget.amount")
                    Spacer()
                    TextField("widget.amount", text: $widgetAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Text(unitSelection.displayText)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("widget.title")
        } footer: {
            if widgetAction == .quickAction, trackingMode == .milestones {
                Text("widget.milestoneHint")
            }
        }
    }

    private var weekdayChips: some View {
        weekdayChips(selection: $recurrenceWeekdays)
    }

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
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var daysOfMonthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
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
                        .font(.caption)
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
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
