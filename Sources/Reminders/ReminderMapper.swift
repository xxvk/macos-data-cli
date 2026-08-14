import Core
import EventKit
import Foundation

public struct ReminderMapper: Sendable {
    public init() {}

    public func map(
        _ reminder: EKReminder,
        listID: String,
        listTitle: String,
        id: String
    ) throws -> ReminderPayload {
        ReminderPayload(
            id: id,
            listID: listID,
            listTitle: listTitle,
            title: reminder.title ?? "",
            notes: reminder.notes,
            url: reminder.url?.absoluteString,
            priority: mapPriority(reminder.priority),
            completed: reminder.isCompleted,
            completionDate: reminder.completionDate,
            start: try reminder.startDateComponents.map(ReminderDateValue.init(components:)),
            due: try reminder.dueDateComponents.map(ReminderDateValue.init(components:)),
            hasAlarms: reminder.hasAlarms,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            alarms: (reminder.alarms ?? []).map(mapAlarm),
            recurrenceRules: (reminder.recurrenceRules ?? []).map(mapRecurrence)
        )
    }

    public func makeReminder(
        from rawInput: ReminderInput,
        eventStore: EKEventStore,
        calendar: EKCalendar
    ) throws -> EKReminder {
        let input = try rawInput.validated()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = input.title
        reminder.notes = input.notes
        reminder.url = input.url.flatMap(URL.init(string:))
        reminder.priority = input.priority.eventKitValue
        reminder.startDateComponents = try input.start?.validatedComponents()
        reminder.dueDateComponents = try input.due?.validatedComponents()
        reminder.alarms?.forEach(reminder.removeAlarm)
        for alarm in input.alarms { reminder.addAlarm(try makeAlarm(alarm)) }
        for rule in input.recurrenceRules { reminder.addRecurrenceRule(makeRecurrence(rule)) }
        return reminder
    }

    public func apply(_ rawPatch: ReminderPatch, to reminder: EKReminder) throws {
        let patch = try rawPatch.validated()
        if patch.has("title") { reminder.title = patch.title }
        if patch.has("notes") { reminder.notes = patch.notes }
        if patch.has("url") { reminder.url = patch.url.flatMap(URL.init(string:)) }
        if patch.has("priority"), let priority = patch.priority { reminder.priority = priority.eventKitValue }
        if patch.has("start") { reminder.startDateComponents = try patch.start?.validatedComponents() }
        if patch.has("due") { reminder.dueDateComponents = try patch.due?.validatedComponents() }
        if patch.has("alarms") {
            if (reminder.alarms ?? []).contains(where: { $0.structuredLocation != nil }) {
                throw ReminderError.unsupportedField("alarms on a reminder containing a location alarm")
            }
            reminder.alarms?.forEach(reminder.removeAlarm)
            for alarm in patch.alarms ?? [] { reminder.addAlarm(try makeAlarm(alarm)) }
        }
        if patch.has("recurrenceRules") {
            reminder.recurrenceRules?.forEach(reminder.removeRecurrenceRule)
            for rule in patch.recurrenceRules ?? [] { reminder.addRecurrenceRule(makeRecurrence(rule)) }
        }
    }

    public func applyCompletion(
        _ completed: Bool,
        completionDate: Date,
        to reminder: EKReminder
    ) {
        reminder.isCompleted = completed
        reminder.completionDate = completed ? completionDate : nil
    }

    public func mapDraft(
        _ reminder: EKReminder,
        listID: String,
        listTitle: String
    ) throws -> ReminderDraft {
        ReminderDraft(
            listID: listID,
            listTitle: listTitle,
            title: reminder.title ?? "",
            notes: reminder.notes,
            url: reminder.url?.absoluteString,
            priority: mapPriority(reminder.priority),
            start: try reminder.startDateComponents.map(ReminderDateValue.init(components:)),
            due: try reminder.dueDateComponents.map(ReminderDateValue.init(components:)),
            alarms: (reminder.alarms ?? []).map(mapAlarm),
            recurrenceRules: (reminder.recurrenceRules ?? []).map(mapRecurrence)
        )
    }

    private func mapPriority(_ value: Int) -> ReminderPriority {
        switch value {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }

    private func mapAlarm(_ alarm: EKAlarm) -> ReminderAlarm {
        let location = alarm.structuredLocation.map {
            ReminderAlarmLocation(title: $0.title ?? "", proximity: mapProximity(alarm.proximity))
        }
        if let absoluteDate = alarm.absoluteDate {
            return ReminderAlarm(absoluteDate: absoluteDate, location: location)
        }
        return ReminderAlarm(
            relativeMinutes: location == nil ? Int((alarm.relativeOffset / 60).rounded()) : nil,
            location: location
        )
    }

    private func makeAlarm(_ alarm: ReminderAlarm) throws -> EKAlarm {
        if alarm.location != nil { throw ReminderError.unsupportedField("location alarm") }
        if let date = alarm.absoluteDate { return EKAlarm(absoluteDate: date) }
        guard let minutes = alarm.relativeMinutes else {
            throw ReminderError.invalidInput("alarm requires a trigger")
        }
        return EKAlarm(relativeOffset: TimeInterval(minutes * 60))
    }

    private func mapProximity(_ proximity: EKAlarmProximity) -> ReminderAlarmProximity {
        switch proximity {
        case .enter: .enter
        case .leave: .leave
        case .none: .none
        @unknown default: .none
        }
    }

    private func mapRecurrence(_ rule: EKRecurrenceRule) -> CalendarRecurrenceRule {
        CalendarRecurrenceRule(
            frequency: rule.frequency.reminderModelValue,
            interval: rule.interval,
            daysOfWeek: (rule.daysOfTheWeek ?? []).filter { $0.weekNumber == 0 }.compactMap { $0.dayOfTheWeek.reminderModelValue },
            weekdayOrdinals: (rule.daysOfTheWeek ?? []).filter { $0.weekNumber != 0 }.compactMap {
                guard let weekday = $0.dayOfTheWeek.reminderModelValue else { return nil }
                return CalendarRecurrenceWeekday(weekday: weekday, weekNumber: $0.weekNumber)
            },
            daysOfMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
            monthsOfYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
            weeksOfYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
            daysOfYear: (rule.daysOfTheYear ?? []).map(\.intValue),
            setPositions: (rule.setPositions ?? []).map(\.intValue),
            end: rule.recurrenceEnd.map {
                CalendarRecurrenceEnd(endDate: $0.endDate, occurrenceCount: $0.occurrenceCount > 0 ? $0.occurrenceCount : nil)
            }
        )
    }

    private func makeRecurrence(_ rule: CalendarRecurrenceRule) -> EKRecurrenceRule {
        let end: EKRecurrenceEnd?
        if let date = rule.end?.endDate { end = EKRecurrenceEnd(end: date) }
        else if let count = rule.end?.occurrenceCount { end = EKRecurrenceEnd(occurrenceCount: count) }
        else { end = nil }
        return EKRecurrenceRule(
            recurrenceWith: rule.frequency.reminderEventKitValue,
            interval: rule.interval,
            daysOfTheWeek: (rule.daysOfWeek.isEmpty && rule.weekdayOrdinals.isEmpty) ? nil :
                rule.daysOfWeek.map { EKRecurrenceDayOfWeek($0.reminderEventKitValue) } +
                rule.weekdayOrdinals.map { EKRecurrenceDayOfWeek($0.weekday.reminderEventKitValue, weekNumber: $0.weekNumber) },
            daysOfTheMonth: rule.daysOfMonth.isEmpty ? nil : rule.daysOfMonth.map(NSNumber.init),
            monthsOfTheYear: rule.monthsOfYear.isEmpty ? nil : rule.monthsOfYear.map(NSNumber.init),
            weeksOfTheYear: rule.weeksOfYear.isEmpty ? nil : rule.weeksOfYear.map(NSNumber.init),
            daysOfTheYear: rule.daysOfYear.isEmpty ? nil : rule.daysOfYear.map(NSNumber.init),
            setPositions: rule.setPositions.isEmpty ? nil : rule.setPositions.map(NSNumber.init),
            end: end
        )
    }
}

private extension EKRecurrenceFrequency {
    var reminderModelValue: CalendarRecurrenceFrequency {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        @unknown default: .daily
        }
    }
}

private extension EKWeekday {
    var reminderModelValue: CalendarWeekday? {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        @unknown default: nil
        }
    }
}

private extension ReminderPriority {
    var eventKitValue: Int {
        switch self { case .none: 0; case .high: 1; case .medium: 5; case .low: 9 }
    }
}

private extension CalendarRecurrenceFrequency {
    var reminderEventKitValue: EKRecurrenceFrequency {
        switch self { case .daily: .daily; case .weekly: .weekly; case .monthly: .monthly; case .yearly: .yearly }
    }
}

private extension CalendarWeekday {
    var reminderEventKitValue: EKWeekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}
