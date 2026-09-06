//
//  AddEditHabitView.swift
//  Goals
//

import SwiftUI
import SwiftData

struct AddEditHabitView: View {
    /// Free habits get one reminder time; Pro unlocks up to this many. Matches `AddEditGoalView`.
    private static let maxProReminderTimes = 4

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    private let habit: Habit?
    private let userId: UUID

    @State private var title: String
    @State private var emoji: String?
    @State private var colorHex: String
    @State private var customColor: Color
    @State private var dailyTarget: Int
    @State private var unitSelection: UnitSelection
    @State private var recurrenceType: RecurrenceType
    @State private var recurrenceWeekdays: Set<Int>
    @State private var recurrenceDaysOfMonth: Set<Int>
    @State private var recurrenceCount: Int
    @State private var isReminderOn: Bool
    @State private var reminderFrequency: ReminderFrequency
    @State private var reminderTimes: [Date]
    @State private var reminderWeekdays: Set<Int>

    @State private var isShowingPermissionAlert = false
    @State private var isShowingEmojiPicker = false
    @State private var isShowingUnitPicker = false

    init(habit: Habit?, userId: UUID) {
        self.habit = habit
        self.userId = habit?.ownerId ?? userId
        _title = State(initialValue: habit?.title ?? "")
        _emoji = State(initialValue: habit?.emoji)
        let hex = habit?.colorHex ?? ColorPalette.defaultHex
        _colorHex = State(initialValue: hex)
        _customColor = State(initialValue: Color(hex: hex))
        _dailyTarget = State(initialValue: habit?.dailyTarget ?? 1)
        _unitSelection = State(initialValue: UnitSelection(
            unitKey: habit?.unitKey ?? GoalUnit.times.rawValue,
            customUnitText: habit?.customUnitText
        ))
        _recurrenceType = State(initialValue: habit?.recurrenceType ?? .daily)
        _recurrenceWeekdays = State(initialValue: Set(habit?.recurrenceWeekdays ?? []))
        _recurrenceDaysOfMonth = State(initialValue: Set(habit?.recurrenceDaysOfMonth ?? []))
        _recurrenceCount = State(initialValue: habit?.recurrenceCount ?? 3)
        _isReminderOn = State(initialValue: habit?.isReminderOn ?? false)
        _reminderFrequency = State(initialValue: habit?.reminderFrequency ?? .daily)
        let minutes = habit?.reminderTimes ?? [9 * 60]
        _reminderTimes = State(initialValue: minutes.map { total in
            Calendar.current.date(bySettingHour: total / 60, minute: total % 60, second: 0, of: .now) ?? .now
        })
        _reminderWeekdays = State(initialValue: Set(habit?.reminderWeekdays ?? []))
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    identityRow
                    colorRow
                    LabeledSection("goal.field.recurrence") {
                        RecurrenceEditor(
                            type: $recurrenceType,
                            weekdays: $recurrenceWeekdays,
                            daysOfMonth: $recurrenceDaysOfMonth,
                            count: $recurrenceCount
                        )
                    }
                    LabeledSection("habit.field.dailyTarget") {
                        CardGroup {
                            Stepper(value: $dailyTarget, in: 1...50) {
                                Text("habit.field.dailyTarget.count \(dailyTarget)")
                                    .font(Theme.Typo.row)
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.vertical, 9)
                            RowDivider()
                            DisclosureRow(label: "goal.field.unit", value: unitSelection.displayText) {
                                isShowingUnitPicker = true
                            }
                        }
                    }
                    LabeledSection("reminder.title") {
                        ReminderEditor(
                            isOn: $isReminderOn,
                            frequency: $reminderFrequency,
                            times: $reminderTimes,
                            weekdays: $reminderWeekdays,
                            isProUnlocked: purchaseManager.isProUnlocked,
                            maxProReminderTimes: Self.maxProReminderTimes
                        )
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .screenGround()
            .navigationTitle(habit == nil
                ? String(localized: "habit.new.title", bundle: AppLanguage.currentBundle)
                : String(localized: "habit.edit.title", bundle: AppLanguage.currentBundle))
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
            .sheet(isPresented: $isShowingUnitPicker) {
                UnitPickerSheet(selection: $unitSelection, userId: userId)
            }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 14) {
            Button {
                isShowingEmojiPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: colorHex).opacity(0.20))
                        .overlay {
                            Circle().strokeBorder(
                                Color(hex: colorHex).opacity(0.5),
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
                TextField("habit.field.title", text: $title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                Rectangle()
                    .fill(Theme.textGhost)
                    .frame(height: 1)
            }
        }
    }

    /// True when the current colour is one the user dialled in themselves, not a preset.
    private var isCustomColor: Bool {
        !ColorPalette.hexValues.contains(colorHex.uppercased())
    }

    private var colorRow: some View {
        LabeledSection("habit.field.color") {
            HStack(spacing: 10) {
                ForEach(ColorPalette.hexValues, id: \.self) { hex in
                    let isSelected = hex.caseInsensitiveCompare(colorHex) == .orderedSame
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle().strokeBorder(Theme.text, lineWidth: isSelected ? 2.5 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("habit.field.color"))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }

                // The wheel, as one more swatch: a ring that shows the chosen custom colour (or a
                // neutral "+" until one is picked) and opens the system picker.
                ZStack {
                    Circle()
                        .fill(isCustomColor ? Color(hex: colorHex) : Theme.control)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle().strokeBorder(Theme.text, lineWidth: isCustomColor ? 2.5 : 0)
                        }
                    if !isCustomColor {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    ColorPicker("habit.field.color.custom", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .opacity(0.015)          // keep it hit-testable but invisible over our swatch
                        .frame(width: 28, height: 28)
                }
                .onChange(of: customColor) { _, newColor in
                    colorHex = newColor.hexString
                }
                .accessibilityLabel(Text("habit.field.color.custom"))

                Spacer(minLength: 0)
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedWeekdays = recurrenceWeekdays.sorted()
        let sortedDaysOfMonth = recurrenceDaysOfMonth.sorted()
        let minutes = reminderTimes.map { date -> Int in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 9) * 60 + (c.minute ?? 0)
        }

        let saved: Habit
        if let habit {
            habit.title = trimmedTitle
            habit.emoji = emoji
            habit.colorHex = colorHex
            habit.dailyTarget = dailyTarget
            habit.unitKey = unitSelection.unitKey
            habit.customUnitText = unitSelection.customUnitText
            habit.recurrenceType = recurrenceType
            habit.recurrenceWeekdays = sortedWeekdays
            habit.recurrenceDaysOfMonth = sortedDaysOfMonth
            habit.recurrenceCount = recurrenceCount
            saved = habit
        } else {
            let newHabit = Habit(
                ownerId: userId,
                title: trimmedTitle,
                emoji: emoji,
                colorHex: colorHex,
                sortIndex: nextSortIndex(),
                dailyTarget: dailyTarget,
                unitKey: unitSelection.unitKey,
                customUnitText: unitSelection.customUnitText,
                recurrenceType: recurrenceType,
                recurrenceWeekdays: sortedWeekdays,
                recurrenceDaysOfMonth: sortedDaysOfMonth,
                recurrenceCount: recurrenceCount
            )
            modelContext.insert(newHabit)
            saved = newHabit
            Analytics.send(.habitCreated)
        }

        saved.isReminderOn = isReminderOn
        saved.reminderFrequency = reminderFrequency
        saved.reminderTimes = minutes.isEmpty ? [9 * 60] : minutes
        saved.reminderWeekdays = Array(reminderWeekdays)

        let context = modelContext
        let userId = userId
        Task { await NotificationScheduler.syncAll(context: context, userId: userId) }
        dismiss()
    }

    /// One past the current highest, so a new habit lands at the bottom of the list.
    private func nextSortIndex() -> Int {
        let userId = userId
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId == userId })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        return (existing.map(\.sortIndex).max() ?? -1) + 1
    }
}

#Preview {
    AddEditHabitView(habit: nil, userId: UUID())
        .environment(PurchaseManager())
        .modelContainer(for: [Goal.self, Milestone.self, CheckIn.self, Category.self, CustomUnit.self, Habit.self, HabitEntry.self], inMemory: true)
}
