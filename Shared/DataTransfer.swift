//
//  DataTransfer.swift
//  Goals
//

import Foundation
import SwiftData

/// Whole-account backup to a single JSON file, and restore from one. The restore is a **replace**:
/// the signed-in user's goals, habits and everything under them is wiped first, then rebuilt from
/// the file. Plain `Codable` DTOs rather than the SwiftData models directly, so the on-disk shape
/// stays stable even if the models move around.
enum DataTransfer {
    /// Bump when the DTO shape changes in a way older builds can't read.
    static let schemaVersion = 1

    enum TransferError: LocalizedError {
        case notJSON
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notJSON:
                String(localized: "backup.error.notJSON", defaultValue: "That file isn't a Goals backup.", bundle: AppLanguage.currentBundle)
            case .unsupportedVersion:
                String(localized: "backup.error.version", defaultValue: "This backup was made by a newer version of the app.", bundle: AppLanguage.currentBundle)
            }
        }
    }

    // MARK: - Document

    struct Document: Codable {
        var schemaVersion: Int
        var exportedAt: Date
        var appVersion: String?
        var categories: [CategoryDTO]
        var customUnits: [CustomUnitDTO]
        var goals: [GoalDTO]
        var habits: [HabitDTO]
    }

    /// Human-readable tally for the confirm step, before anything is touched.
    struct Summary {
        let exportedAt: Date
        let goals: Int
        let habits: Int
        let checkIns: Int
        let entries: Int
    }

    static func summary(of doc: Document) -> Summary {
        Summary(
            exportedAt: doc.exportedAt,
            goals: doc.goals.count,
            habits: doc.habits.count,
            checkIns: doc.goals.reduce(0) { $0 + $1.checkIns.count },
            entries: doc.habits.reduce(0) { $0 + $1.entries.count }
        )
    }

    // MARK: - Export

    static func export(userId: UUID, context: ModelContext) throws -> Data {
        let categories = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.ownerId == userId }))
        let customUnits = try context.fetch(FetchDescriptor<CustomUnit>(predicate: #Predicate { $0.ownerId == userId }))
        let goals = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.ownerId == userId }))
        let habits = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.ownerId == userId }))

        let doc = Document(
            schemaVersion: schemaVersion,
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            categories: categories.map(CategoryDTO.init),
            customUnits: customUnits.map(CustomUnitDTO.init),
            goals: goals.map(GoalDTO.init),
            habits: habits.map(HabitDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(doc)
    }

    // MARK: - Import

    static func decode(_ data: Data) throws -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc: Document
        do {
            doc = try decoder.decode(Document.self, from: data)
        } catch {
            throw TransferError.notJSON
        }
        guard doc.schemaVersion <= schemaVersion else {
            throw TransferError.unsupportedVersion(doc.schemaVersion)
        }
        return doc
    }

    /// Wipes the user's data and rebuilds it from `doc`. All or nothing — on any failure the
    /// context isn't saved.
    static func replaceAll(with doc: Document, userId: UUID, context: ModelContext) throws {
        try context.delete(model: CheckIn.self, where: #Predicate { $0.ownerId == userId })
        try context.delete(model: HabitEntry.self, where: #Predicate { $0.ownerId == userId })
        // Streak freezes aren't in the backup document; a restore rebuilds the bank from scratch,
        // so clear any that point at the data being replaced.
        try context.delete(model: StreakFreeze.self, where: #Predicate { $0.ownerId == userId })
        try context.delete(model: Milestone.self, where: #Predicate { $0.ownerId == userId })
        try context.delete(model: Goal.self, where: #Predicate { $0.ownerId == userId })
        try context.delete(model: Habit.self, where: #Predicate { $0.ownerId == userId })
        try context.delete(model: Category.self, where: #Predicate { $0.ownerId == userId })
        try context.delete(model: CustomUnit.self, where: #Predicate { $0.ownerId == userId })

        for dto in doc.customUnits {
            context.insert(dto.makeModel(ownerId: userId))
        }

        var categoriesByID: [UUID: Category] = [:]
        for dto in doc.categories {
            let category = dto.makeModel(ownerId: userId)
            context.insert(category)
            categoriesByID[dto.id] = category
        }

        for dto in doc.goals {
            let goal = dto.makeModel(ownerId: userId)
            context.insert(goal)
            if let categoryID = dto.categoryID { goal.category = categoriesByID[categoryID] }
            for milestoneDTO in dto.milestones {
                let milestone = milestoneDTO.makeModel(ownerId: userId)
                milestone.goal = goal
                context.insert(milestone)
            }
            for checkInDTO in dto.checkIns {
                let checkIn = checkInDTO.makeModel(ownerId: userId)
                checkIn.goal = goal
                context.insert(checkIn)
            }
        }

        for dto in doc.habits {
            let habit = dto.makeModel(ownerId: userId)
            context.insert(habit)
            for entryDTO in dto.entries {
                let entry = entryDTO.makeModel(ownerId: userId)
                entry.habit = habit
                context.insert(entry)
            }
        }

        try context.save()
    }
}

// MARK: - DTOs

struct CategoryDTO: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var defaultKey: String?

    init(_ model: Category) {
        id = model.id
        name = model.name
        createdAt = model.createdAt
        defaultKey = model.defaultKey
    }

    func makeModel(ownerId: UUID) -> Category {
        Category(id: id, ownerId: ownerId, name: name, createdAt: createdAt, defaultKey: defaultKey)
    }
}

struct CustomUnitDTO: Codable {
    var id: UUID
    var name: String
    var createdAt: Date

    init(_ model: CustomUnit) {
        id = model.id
        name = model.name
        createdAt = model.createdAt
    }

    func makeModel(ownerId: UUID) -> CustomUnit {
        CustomUnit(id: id, ownerId: ownerId, name: name, createdAt: createdAt)
    }
}

struct MilestoneDTO: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var order: Int

    init(_ model: Milestone) {
        id = model.id
        title = model.title
        isCompleted = model.isCompleted
        order = model.order
    }

    func makeModel(ownerId: UUID) -> Milestone {
        Milestone(id: id, ownerId: ownerId, title: title, isCompleted: isCompleted, order: order)
    }
}

struct CheckInDTO: Codable {
    var id: UUID
    var date: Date
    var note: String?
    var valueSnapshot: Double?

    init(_ model: CheckIn) {
        id = model.id
        date = model.date
        note = model.note
        valueSnapshot = model.valueSnapshot
    }

    func makeModel(ownerId: UUID) -> CheckIn {
        CheckIn(id: id, ownerId: ownerId, date: date, note: note, valueSnapshot: valueSnapshot)
    }
}

struct GoalDTO: Codable {
    var id: UUID
    var title: String
    var deadline: Date?
    var priorityRaw: String
    var isCompleted: Bool
    var createdAt: Date
    /// Optional so a backup written before start dates existed still decodes; nil falls back to `createdAt`.
    var startDate: Date?
    var categoryID: UUID?
    var targetValue: Double
    var currentValue: Double
    var startValue: Double
    var isLowerBetter: Bool
    var unitKey: String
    var customUnitText: String?
    var trackingModeRaw: String
    var isArchived: Bool
    var colorHex: String
    var emoji: String?
    var recurrenceTypeRaw: String
    var recurrenceWeekdays: [Int]
    var recurrenceDaysOfMonth: [Int]
    var recurrenceCount: Int
    var isReminderOn: Bool
    var reminderFrequencyRaw: String
    var reminderTimes: [Int]
    var reminderWeekdays: [Int]
    var widgetActionRaw: String
    var widgetQuickAmount: Double
    var milestones: [MilestoneDTO]
    var checkIns: [CheckInDTO]

    init(_ model: Goal) {
        id = model.id
        title = model.title
        deadline = model.deadline
        priorityRaw = model.priority.rawValue
        isCompleted = model.isCompleted
        createdAt = model.createdAt
        startDate = model.startDate
        categoryID = model.category?.id
        targetValue = model.targetValue
        currentValue = model.currentValue
        startValue = model.startValue
        isLowerBetter = model.isLowerBetter
        unitKey = model.unitKey
        customUnitText = model.customUnitText
        trackingModeRaw = model.trackingMode.rawValue
        isArchived = model.isArchived
        colorHex = model.colorHex
        emoji = model.emoji
        recurrenceTypeRaw = model.recurrenceType.rawValue
        recurrenceWeekdays = model.recurrenceWeekdays
        recurrenceDaysOfMonth = model.recurrenceDaysOfMonth
        recurrenceCount = model.recurrenceCount
        isReminderOn = model.isReminderOn
        reminderFrequencyRaw = model.reminderFrequency.rawValue
        reminderTimes = model.reminderTimes
        reminderWeekdays = model.reminderWeekdays
        widgetActionRaw = model.widgetAction.rawValue
        widgetQuickAmount = model.widgetQuickAmount
        milestones = model.milestones.map(MilestoneDTO.init)
        checkIns = model.checkIns.map(CheckInDTO.init)
    }

    func makeModel(ownerId: UUID) -> Goal {
        let goal = Goal(id: id, ownerId: ownerId, title: title)
        goal.deadline = deadline
        goal.priority = GoalPriority(rawValue: priorityRaw) ?? .medium
        goal.isCompleted = isCompleted
        goal.createdAt = createdAt
        if let startDate { goal.startDate = startDate }
        goal.targetValue = targetValue
        goal.currentValue = currentValue
        goal.startValue = startValue
        goal.isLowerBetter = isLowerBetter
        goal.unitKey = unitKey
        goal.customUnitText = customUnitText
        goal.trackingMode = GoalTrackingMode(rawValue: trackingModeRaw) ?? .value
        goal.isArchived = isArchived
        goal.colorHex = colorHex
        goal.emoji = emoji
        goal.recurrenceType = RecurrenceType(rawValue: recurrenceTypeRaw) ?? .daily
        goal.recurrenceWeekdays = recurrenceWeekdays
        goal.recurrenceDaysOfMonth = recurrenceDaysOfMonth
        goal.recurrenceCount = recurrenceCount
        goal.isReminderOn = isReminderOn
        goal.reminderFrequency = ReminderFrequency(rawValue: reminderFrequencyRaw) ?? .daily
        goal.reminderTimes = reminderTimes
        goal.reminderWeekdays = reminderWeekdays
        goal.widgetAction = WidgetAction(rawValue: widgetActionRaw) ?? .quickAction
        goal.widgetQuickAmount = widgetQuickAmount
        return goal
    }
}

struct HabitEntryDTO: Codable {
    var id: UUID
    var date: Date
    var amount: Double

    init(_ model: HabitEntry) {
        id = model.id
        date = model.date
        amount = model.amount
    }

    func makeModel(ownerId: UUID) -> HabitEntry {
        HabitEntry(id: id, ownerId: ownerId, date: date, amount: amount)
    }
}

struct HabitDTO: Codable {
    var id: UUID
    var title: String
    var emoji: String?
    var colorHex: String
    var createdAt: Date
    /// Optional so a backup written before start dates existed still decodes; nil falls back to `createdAt`.
    var startDate: Date?
    var deadline: Date?
    var sortIndex: Int
    var targetAmount: Double
    var unitKey: String
    var customUnitText: String?
    var recurrenceTypeRaw: String
    var recurrenceWeekdays: [Int]
    var recurrenceDaysOfMonth: [Int]
    var recurrenceCount: Int
    var isArchived: Bool
    var isReminderOn: Bool
    var reminderFrequencyRaw: String
    var reminderTimes: [Int]
    var reminderWeekdays: [Int]
    var widgetQuickAmount: Double
    var widgetActionRaw: String
    var entries: [HabitEntryDTO]

    init(_ model: Habit) {
        id = model.id
        title = model.title
        emoji = model.emoji
        colorHex = model.colorHex
        createdAt = model.createdAt
        startDate = model.startDate
        deadline = model.deadline
        sortIndex = model.sortIndex
        targetAmount = model.targetAmount
        unitKey = model.unitKey
        customUnitText = model.customUnitText
        recurrenceTypeRaw = model.recurrenceType.rawValue
        recurrenceWeekdays = model.recurrenceWeekdays
        recurrenceDaysOfMonth = model.recurrenceDaysOfMonth
        recurrenceCount = model.recurrenceCount
        isArchived = model.isArchived
        isReminderOn = model.isReminderOn
        reminderFrequencyRaw = model.reminderFrequency.rawValue
        reminderTimes = model.reminderTimes
        reminderWeekdays = model.reminderWeekdays
        widgetQuickAmount = model.widgetQuickAmount
        widgetActionRaw = model.widgetAction.rawValue
        entries = model.entries.map(HabitEntryDTO.init)
    }

    func makeModel(ownerId: UUID) -> Habit {
        let habit = Habit(id: id, ownerId: ownerId, title: title)
        habit.emoji = emoji
        habit.colorHex = colorHex
        habit.createdAt = createdAt
        if let startDate { habit.startDate = startDate }
        habit.deadline = deadline
        habit.sortIndex = sortIndex
        habit.targetAmount = targetAmount
        habit.unitKey = unitKey
        habit.customUnitText = customUnitText
        habit.recurrenceType = RecurrenceType(rawValue: recurrenceTypeRaw) ?? .daily
        habit.recurrenceWeekdays = recurrenceWeekdays
        habit.recurrenceDaysOfMonth = recurrenceDaysOfMonth
        habit.recurrenceCount = recurrenceCount
        habit.isArchived = isArchived
        habit.isReminderOn = isReminderOn
        habit.reminderFrequency = ReminderFrequency(rawValue: reminderFrequencyRaw) ?? .daily
        habit.reminderTimes = reminderTimes
        habit.reminderWeekdays = reminderWeekdays
        habit.widgetQuickAmount = widgetQuickAmount
        habit.widgetAction = HabitWidgetAction(rawValue: widgetActionRaw) ?? .checkOff
        return habit
    }
}
