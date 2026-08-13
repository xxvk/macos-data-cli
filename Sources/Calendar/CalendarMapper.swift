import Core
import EventKit
import Foundation

public struct CalendarMapper: Sendable {
    public init() {}

    public func map(_ event: EKEvent, id: String? = nil) -> CalendarEventPayload {
        CalendarEventPayload(
            id: id ?? event.eventIdentifier,
            calendarID: event.calendar?.calendarIdentifier,
            calendarTitle: event.calendar?.title,
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            allDay: event.isAllDay,
            timeZone: event.timeZone?.identifier,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            attendees: (event.attendees ?? []).map(mapAttendee),
            alarms: (event.alarms ?? []).compactMap(mapAlarm),
            recurrenceRules: (event.recurrenceRules ?? []).map(mapRecurrence),
            availability: mapAvailability(event.availability),
            status: mapStatus(event.status),
            occurrenceDate: event.occurrenceDate,
            isDetached: event.isDetached
        )
    }

    public func makeEvent(from input: CalendarEventInput, eventStore: EKEventStore) throws -> EKEvent {
        try validate(input)
        let event = EKEvent(eventStore: eventStore)
        event.title = input.title
        event.timeZone = try input.timeZone.map(validTimeZone)
        event.isAllDay = input.allDay
        event.startDate = input.startDate
        event.endDate = input.endDate
        event.location = input.location
        event.notes = input.notes
        event.url = try input.url.map(validURL)
        event.alarms?.forEach(event.removeAlarm)
        for alarm in input.alarms { event.addAlarm(try makeAlarm(alarm)) }
        for rule in input.recurrenceRules {
            event.addRecurrenceRule(try makeRecurrence(rule))
        }
        return event
    }

    public func apply(_ patch: CalendarEventPatch, to event: EKEvent) throws {
        let hasDateChange = patch.has("startDate") || patch.has("endDate")
        if patch.has("allDay"), patch.allDay != event.isAllDay,
           !(patch.has("startDate") && patch.has("endDate")) {
            throw CalendarError.invalidInput("changing allDay requires both startDate and endDate")
        }
        if hasDateChange, (patch.allDay ?? event.isAllDay) != patch.usesDateOnlyValues {
            throw CalendarError.invalidInput("all-day dates use YYYY-MM-DD; timed dates use ISO 8601 timestamps")
        }
        if patch.has("title") {
            guard let title = patch.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CalendarError.invalidInput("title cannot be empty")
            }
            event.title = title
        }
        if patch.has("allDay") { guard let value = patch.allDay else { throw CalendarError.invalidInput("allDay cannot be null") }; event.isAllDay = value }
        if patch.has("startDate") { guard let value = patch.startDate else { throw CalendarError.invalidInput("startDate cannot be null") }; event.startDate = value }
        if patch.has("endDate") { guard let value = patch.endDate else { throw CalendarError.invalidInput("endDate cannot be null") }; event.endDate = value }
        if patch.has("timeZone") { event.timeZone = try patch.timeZone.map(validTimeZone) }
        if patch.has("location") { event.location = patch.location }
        if patch.has("notes") { event.notes = patch.notes }
        if patch.has("url") { event.url = try patch.url.map(validURL) }
        if patch.has("alarms") {
            event.alarms?.forEach(event.removeAlarm)
            for alarm in patch.alarms ?? [] { event.addAlarm(try makeAlarm(alarm)) }
        }
        if patch.has("recurrenceRules") {
            event.recurrenceRules?.forEach(event.removeRecurrenceRule)
            for rule in patch.recurrenceRules ?? [] { event.addRecurrenceRule(try makeRecurrence(rule)) }
        }
        guard event.startDate < event.endDate else { throw CalendarError.invalidInput("startDate must be earlier than endDate") }
    }

    private func validate(_ input: CalendarEventInput) throws {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CalendarError.invalidInput("title is required")
        }
        guard input.startDate < input.endDate else {
            throw CalendarError.invalidInput("startDate must be earlier than endDate")
        }
        guard input.attendees.isEmpty else {
            throw CalendarError.invalidInput("attendees are read-only in 0.3")
        }
        guard input.alarms.count <= 20 else { throw CalendarError.invalidInput("an event supports at most 20 alarms") }
        _ = try input.alarms.map { try $0.validated() }
    }

    private func validTimeZone(_ identifier: String) throws -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else {
            throw CalendarError.invalidInput("unknown IANA time zone: \(identifier)")
        }
        return zone
    }

    private func validURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme != nil else {
            throw CalendarError.invalidInput("url must be absolute")
        }
        return url
    }

    private func mapAttendee(_ attendee: EKParticipant) -> CalendarAttendee {
        let absolute = attendee.url.absoluteString
        let email = attendee.url.scheme?.lowercased() == "mailto"
            ? String(absolute.dropFirst("mailto:".count)).removingPercentEncoding
            : nil
        return CalendarAttendee(
            name: attendee.name,
            email: email,
            status: attendee.participantStatus.stringValue,
            role: attendee.participantRole.stringValue,
            type: attendee.participantType.stringValue
        )
    }

    private func mapAlarm(_ alarm: EKAlarm) -> CalendarAlarm? {
        if let absoluteDate = alarm.absoluteDate { return CalendarAlarm(absoluteDate: absoluteDate) }
        return CalendarAlarm(relativeMinutes: Int((alarm.relativeOffset / 60).rounded()))
    }

    private func makeAlarm(_ alarm: CalendarAlarm) throws -> EKAlarm {
        let value = try alarm.validated()
        if let absoluteDate = value.absoluteDate { return EKAlarm(absoluteDate: absoluteDate) }
        return EKAlarm(relativeOffset: TimeInterval((value.relativeMinutes ?? 0) * 60))
    }

    private func mapRecurrence(_ rule: EKRecurrenceRule) -> CalendarRecurrenceRule {
        CalendarRecurrenceRule(
            frequency: rule.frequency.modelValue,
            interval: rule.interval,
            daysOfWeek: (rule.daysOfTheWeek ?? []).filter { $0.weekNumber == 0 }.compactMap { $0.dayOfTheWeek.modelValue },
            weekdayOrdinals: (rule.daysOfTheWeek ?? []).filter { $0.weekNumber != 0 }.compactMap {
                guard let weekday = $0.dayOfTheWeek.modelValue else { return nil }
                return CalendarRecurrenceWeekday(weekday: weekday, weekNumber: $0.weekNumber)
            },
            daysOfMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
            monthsOfYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
            weeksOfYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
            daysOfYear: (rule.daysOfTheYear ?? []).map(\.intValue),
            setPositions: (rule.setPositions ?? []).map(\.intValue),
            end: rule.recurrenceEnd.map { CalendarRecurrenceEnd(endDate: $0.endDate, occurrenceCount: $0.occurrenceCount > 0 ? $0.occurrenceCount : nil) }
        )
    }

    private func makeRecurrence(_ rule: CalendarRecurrenceRule) throws -> EKRecurrenceRule {
        guard rule.interval >= 1 else { throw CalendarError.invalidInput("recurrence interval must be at least 1") }
        guard rule.weekdayOrdinals.allSatisfy({ (-53...53).contains($0.weekNumber) && $0.weekNumber != 0 }) else {
            throw CalendarError.invalidInput("weekday ordinal must be between -53 and 53 and cannot be zero")
        }
        try validateValues(rule.daysOfMonth, range: -31...31, name: "daysOfMonth")
        try validateValues(rule.monthsOfYear, range: 1...12, name: "monthsOfYear", allowsZero: false)
        try validateValues(rule.weeksOfYear, range: -53...53, name: "weeksOfYear")
        try validateValues(rule.daysOfYear, range: -366...366, name: "daysOfYear")
        try validateValues(rule.setPositions, range: -366...366, name: "setPositions")
        if let end = rule.end, end.endDate != nil && end.occurrenceCount != nil {
            throw CalendarError.invalidInput("recurrence end accepts either endDate or occurrenceCount")
        }
        if let count = rule.end?.occurrenceCount, count < 1 {
            throw CalendarError.invalidInput("recurrence occurrenceCount must be at least 1")
        }
        let recurrenceEnd: EKRecurrenceEnd?
        if let date = rule.end?.endDate { recurrenceEnd = EKRecurrenceEnd(end: date) }
        else if let count = rule.end?.occurrenceCount { recurrenceEnd = EKRecurrenceEnd(occurrenceCount: count) }
        else { recurrenceEnd = nil }
        return EKRecurrenceRule(
            recurrenceWith: rule.frequency.eventKitValue,
            interval: rule.interval,
            daysOfTheWeek: (rule.daysOfWeek.isEmpty && rule.weekdayOrdinals.isEmpty) ? nil :
                rule.daysOfWeek.map { EKRecurrenceDayOfWeek($0.eventKitValue) } +
                rule.weekdayOrdinals.map { EKRecurrenceDayOfWeek($0.weekday.eventKitValue, weekNumber: $0.weekNumber) },
            daysOfTheMonth: rule.daysOfMonth.isEmpty ? nil : rule.daysOfMonth.map(NSNumber.init),
            monthsOfTheYear: rule.monthsOfYear.isEmpty ? nil : rule.monthsOfYear.map(NSNumber.init),
            weeksOfTheYear: rule.weeksOfYear.isEmpty ? nil : rule.weeksOfYear.map(NSNumber.init),
            daysOfTheYear: rule.daysOfYear.isEmpty ? nil : rule.daysOfYear.map(NSNumber.init),
            setPositions: rule.setPositions.isEmpty ? nil : rule.setPositions.map(NSNumber.init),
            end: recurrenceEnd
        )
    }

    private func validateValues(_ values: [Int], range: ClosedRange<Int>, name: String, allowsZero: Bool = false) throws {
        guard values.allSatisfy({ range.contains($0) && (allowsZero || $0 != 0) }) else {
            throw CalendarError.invalidInput("\(name) contains an out-of-range value")
        }
    }

    private func mapAvailability(_ value: EKEventAvailability) -> String {
        switch value { case .busy: "busy"; case .free: "free"; case .tentative: "tentative"; case .unavailable: "unavailable"; case .notSupported: "notSupported"; @unknown default: "unknown" }
    }

    private func mapStatus(_ value: EKEventStatus) -> String {
        switch value { case .none: "none"; case .confirmed: "confirmed"; case .tentative: "tentative"; case .canceled: "canceled"; @unknown default: "unknown" }
    }
}

private extension EKRecurrenceFrequency {
    var modelValue: CalendarRecurrenceFrequency {
        switch self { case .daily: .daily; case .weekly: .weekly; case .monthly: .monthly; case .yearly: .yearly; @unknown default: .daily }
    }
}

private extension CalendarRecurrenceFrequency {
    var eventKitValue: EKRecurrenceFrequency {
        switch self { case .daily: .daily; case .weekly: .weekly; case .monthly: .monthly; case .yearly: .yearly }
    }
}

private extension EKWeekday {
    var modelValue: CalendarWeekday? {
        switch self { case .sunday: .sunday; case .monday: .monday; case .tuesday: .tuesday; case .wednesday: .wednesday; case .thursday: .thursday; case .friday: .friday; case .saturday: .saturday; @unknown default: nil }
    }
}

private extension CalendarWeekday {
    var eventKitValue: EKWeekday {
        switch self { case .sunday: .sunday; case .monday: .monday; case .tuesday: .tuesday; case .wednesday: .wednesday; case .thursday: .thursday; case .friday: .friday; case .saturday: .saturday }
    }
}

private extension EKParticipantStatus {
    var stringValue: String { switch self { case .unknown: "unknown"; case .pending: "pending"; case .accepted: "accepted"; case .declined: "declined"; case .tentative: "tentative"; case .delegated: "delegated"; case .completed: "completed"; case .inProcess: "inProcess"; @unknown default: "unknown" } }
}

private extension EKParticipantRole {
    var stringValue: String { switch self { case .unknown: "unknown"; case .required: "required"; case .optional: "optional"; case .chair: "chair"; case .nonParticipant: "nonParticipant"; @unknown default: "unknown" } }
}

private extension EKParticipantType {
    var stringValue: String { switch self { case .unknown: "unknown"; case .person: "person"; case .room: "room"; case .resource: "resource"; case .group: "group"; @unknown default: "unknown" } }
}
