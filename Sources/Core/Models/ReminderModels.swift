import Foundation

public struct ReminderSourceDescriptor: Codable, Equatable, Sendable {
    public let title: String
    public let identifier: String
    public let type: String
    public let isICloud: Bool

    public init(title: String, identifier: String, type: String, isICloud: Bool) {
        self.title = title
        self.identifier = identifier
        self.type = type
        self.isICloud = isICloud
    }
}

public struct ReminderListDescriptor: Codable, Equatable, Sendable {
    public let title: String
    public let identifier: String
    public let sourceIdentifier: String
    public let type: String
    public let allowsContentModifications: Bool

    public init(
        title: String,
        identifier: String,
        sourceIdentifier: String,
        type: String,
        allowsContentModifications: Bool
    ) {
        self.title = title
        self.identifier = identifier
        self.sourceIdentifier = sourceIdentifier
        self.type = type
        self.allowsContentModifications = allowsContentModifications
    }
}

public struct ReminderSourceListResult: Codable, Equatable, Sendable {
    public let sources: [ReminderSourceDescriptor]
    public let selectedSourceID: String

    public init(sources: [ReminderSourceDescriptor], selectedSourceID: String) {
        self.sources = sources
        self.selectedSourceID = selectedSourceID
    }
}

public struct ReminderListResult: Codable, Equatable, Sendable {
    public let lists: [ReminderListDescriptor]
    public let selectedSourceID: String

    public init(lists: [ReminderListDescriptor], selectedSourceID: String) {
        self.lists = lists
        self.selectedSourceID = selectedSourceID
    }
}

public enum ReminderPriority: String, Codable, Equatable, Sendable {
    case none
    case high
    case medium
    case low
}

public enum ReminderAlarmProximity: String, Codable, Equatable, Sendable {
    case enter
    case leave
    case none
}

public struct ReminderAlarmLocation: Codable, Equatable, Sendable {
    public let title: String
    public let proximity: ReminderAlarmProximity

    public init(title: String, proximity: ReminderAlarmProximity) {
        self.title = title
        self.proximity = proximity
    }
}

public struct ReminderAlarm: Codable, Equatable, Sendable {
    public let relativeMinutes: Int?
    public let absoluteDate: Date?
    public let location: ReminderAlarmLocation?

    public init(relativeMinutes: Int? = nil, absoluteDate: Date? = nil, location: ReminderAlarmLocation? = nil) {
        self.relativeMinutes = relativeMinutes
        self.absoluteDate = absoluteDate
        self.location = location
    }
}

public struct ReminderDateValue: Codable, Equatable, Sendable {
    public let value: String
    public let timeZone: String?
    public let hasTime: Bool
    public let floating: Bool

    public init(value: String, timeZone: String?, hasTime: Bool, floating: Bool) {
        self.value = value
        self.timeZone = timeZone
        self.hasTime = hasTime
        self.floating = floating
    }

    public init(components: DateComponents) throws {
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw ReminderError.invalidInput("reminder date requires year, month, and day")
        }
        let hasTime = components.hour != nil || components.minute != nil || components.second != nil
        self.hasTime = hasTime

        if !hasTime {
            value = String(format: "%04d-%02d-%02d", year, month, day)
            timeZone = nil
            floating = true
            return
        }

        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw ReminderError.invalidInput("reminder time components are invalid")
        }

        guard let zone = components.timeZone else {
            value = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
            timeZone = nil
            floating = true
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var normalized = DateComponents()
        normalized.calendar = calendar
        normalized.timeZone = zone
        normalized.year = year
        normalized.month = month
        normalized.day = day
        normalized.hour = hour
        normalized.minute = minute
        normalized.second = second
        guard let date = calendar.date(from: normalized) else {
            throw ReminderError.invalidInput("reminder date components are invalid")
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        value = formatter.string(from: date)
        timeZone = zone.identifier
        floating = false
    }

    public func comparisonDate(defaultTimeZone: TimeZone = .current) -> Date? {
        if hasTime, !floating {
            return ISO8601DateFormatter().date(from: value)
        }
        let format = hasTime ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = defaultTimeZone
        formatter.dateFormat = format
        return formatter.date(from: value)
    }

    public func validatedComponents() throws -> DateComponents {
        if !hasTime {
            guard floating, timeZone == nil else {
                throw ReminderError.invalidInput("date-only reminder values must be floating and omit timeZone")
            }
            let formatter = Self.localFormatter(format: "yyyy-MM-dd", timeZone: TimeZone(secondsFromGMT: 0)!)
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
                throw ReminderError.invalidInput("date-only reminder value must use a valid YYYY-MM-DD date")
            }
            let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
            return DateComponents(calendar: Calendar(identifier: .gregorian), year: parts.year, month: parts.month, day: parts.day)
        }

        if floating {
            guard timeZone == nil else {
                throw ReminderError.invalidInput("floating reminder times must omit timeZone")
            }
            let zone = TimeZone(secondsFromGMT: 0)!
            let formatter = Self.localFormatter(format: "yyyy-MM-dd'T'HH:mm:ss", timeZone: zone)
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
                throw ReminderError.invalidInput("floating reminder time must use YYYY-MM-DDTHH:mm:ss")
            }
            let parts = Calendar(identifier: .gregorian).dateComponents(in: zone, from: date)
            return DateComponents(
                calendar: Calendar(identifier: .gregorian),
                year: parts.year, month: parts.month, day: parts.day,
                hour: parts.hour, minute: parts.minute, second: parts.second
            )
        }

        guard let identifier = timeZone, let zone = TimeZone(identifier: identifier) else {
            throw ReminderError.invalidInput("timed reminder value requires a valid IANA timeZone")
        }
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw ReminderError.invalidInput("timed reminder value must use ISO 8601 with an explicit offset")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        parts.calendar = calendar
        parts.timeZone = zone
        return parts
    }

    private static func localFormatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}

public struct ReminderInput: Codable, Equatable, Sendable {
    public let listID: String?
    public let title: String
    public let notes: String?
    public let url: String?
    public let priority: ReminderPriority
    public let start: ReminderDateValue?
    public let due: ReminderDateValue?
    public let alarms: [ReminderAlarm]
    public let recurrenceRules: [CalendarRecurrenceRule]

    public init(
        listID: String? = nil,
        title: String,
        notes: String? = nil,
        url: String? = nil,
        priority: ReminderPriority = .none,
        start: ReminderDateValue? = nil,
        due: ReminderDateValue? = nil,
        alarms: [ReminderAlarm] = [],
        recurrenceRules: [CalendarRecurrenceRule] = []
    ) {
        self.listID = listID
        self.title = title
        self.notes = notes
        self.url = url
        self.priority = priority
        self.start = start
        self.due = due
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case listID, title, notes, url, priority, start, due, alarms, recurrenceRules
    }

    public init(from decoder: Decoder) throws {
        let rawKeys = try decoder.container(keyedBy: ReminderInputAnyCodingKey.self).allKeys.map(\.stringValue)
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknown = rawKeys.first(where: { !knownKeys.contains($0) }) {
            throw ReminderError.invalidInput("unknown create field: \(unknown)")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        listID = try values.decodeIfPresent(String.self, forKey: .listID)
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        priority = try values.decodeIfPresent(ReminderPriority.self, forKey: .priority) ?? .none
        start = try values.decodeIfPresent(ReminderDateValue.self, forKey: .start)
        due = try values.decodeIfPresent(ReminderDateValue.self, forKey: .due)
        alarms = try values.decodeIfPresent([ReminderAlarm].self, forKey: .alarms) ?? []
        recurrenceRules = try values.decodeIfPresent([CalendarRecurrenceRule].self, forKey: .recurrenceRules) ?? []
    }

    public func validated() throws -> ReminderInput {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ReminderError.invalidInput("title must not be empty")
        }
        guard normalizedTitle.count <= 1_000 else { throw ReminderError.invalidInput("title exceeds 1,000 characters") }
        if let listID, listID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ReminderError.invalidInput("listID must not be empty")
        }
        if let notes, notes.count > 100_000 { throw ReminderError.invalidInput("notes exceeds 100,000 characters") }
        if let url {
            guard url.count <= 2_048, let parsed = URL(string: url), parsed.scheme != nil else {
                throw ReminderError.invalidInput("url must be an absolute URL")
            }
        }
        _ = try start?.validatedComponents()
        _ = try due?.validatedComponents()
        guard alarms.count <= 20 else { throw ReminderError.invalidInput("alarms supports at most 20 entries") }
        for alarm in alarms {
            if alarm.location != nil { throw ReminderError.unsupportedField("location alarm") }
            let triggerCount = (alarm.relativeMinutes == nil ? 0 : 1) + (alarm.absoluteDate == nil ? 0 : 1)
            guard triggerCount == 1 else {
                throw ReminderError.invalidInput("each alarm requires exactly one relativeMinutes or absoluteDate trigger")
            }
            if let minutes = alarm.relativeMinutes, !(-525_600...525_600).contains(minutes) {
                throw ReminderError.invalidInput("alarm relativeMinutes is outside the supported one-year range")
            }
        }
        guard recurrenceRules.count <= 1 else {
            throw ReminderError.invalidInput("a reminder supports at most one recurrence rule")
        }
        for rule in recurrenceRules { try Self.validate(rule) }
        return ReminderInput(
            listID: listID,
            title: normalizedTitle,
            notes: notes,
            url: url,
            priority: priority,
            start: start,
            due: due,
            alarms: alarms,
            recurrenceRules: recurrenceRules
        )
    }

    private static func validate(_ rule: CalendarRecurrenceRule) throws {
        guard rule.interval >= 1 else { throw ReminderError.invalidInput("recurrence interval must be at least 1") }
        guard rule.weekdayOrdinals.allSatisfy({ (-53...53).contains($0.weekNumber) && $0.weekNumber != 0 }) else {
            throw ReminderError.invalidInput("recurrence weekday ordinal is outside -53...53 or zero")
        }
        try validate(rule.daysOfMonth, range: -31...31, name: "daysOfMonth")
        try validate(rule.monthsOfYear, range: 1...12, name: "monthsOfYear")
        try validate(rule.weeksOfYear, range: -53...53, name: "weeksOfYear")
        try validate(rule.daysOfYear, range: -366...366, name: "daysOfYear")
        try validate(rule.setPositions, range: -366...366, name: "setPositions")
        if let end = rule.end, end.endDate != nil && end.occurrenceCount != nil {
            throw ReminderError.invalidInput("recurrence end accepts either endDate or occurrenceCount")
        }
        if let count = rule.end?.occurrenceCount, count < 1 {
            throw ReminderError.invalidInput("recurrence occurrenceCount must be at least 1")
        }
    }

    private static func validate(_ values: [Int], range: ClosedRange<Int>, name: String) throws {
        guard values.allSatisfy({ range.contains($0) && $0 != 0 }) else {
            throw ReminderError.invalidInput("recurrence \(name) contains an out-of-range value")
        }
    }
}

public struct ReminderPatch: Codable, Sendable {
    public private(set) var listID: String?
    public private(set) var title: String?
    public private(set) var notes: String?
    public private(set) var url: String?
    public private(set) var priority: ReminderPriority?
    public private(set) var start: ReminderDateValue?
    public private(set) var due: ReminderDateValue?
    public private(set) var alarms: [ReminderAlarm]?
    public private(set) var recurrenceRules: [CalendarRecurrenceRule]?
    private var present: Set<String> = []

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case listID, title, notes, url, priority, start, due, alarms, recurrenceRules
    }

    public init(from decoder: Decoder) throws {
        let rawKeys = try decoder.container(keyedBy: ReminderInputAnyCodingKey.self).allKeys.map(\.stringValue)
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknown = rawKeys.first(where: { !knownKeys.contains($0) }) {
            throw ReminderError.invalidInput("unknown edit field: \(unknown)")
        }
        guard !rawKeys.isEmpty else { throw ReminderError.invalidInput("edit patch must not be empty") }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        listID = try values.decodeIfPresent(String.self, forKey: .listID)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        priority = try values.decodeIfPresent(ReminderPriority.self, forKey: .priority)
        start = try values.decodeIfPresent(ReminderDateValue.self, forKey: .start)
        due = try values.decodeIfPresent(ReminderDateValue.self, forKey: .due)
        alarms = try values.decodeIfPresent([ReminderAlarm].self, forKey: .alarms)
        recurrenceRules = try values.decodeIfPresent([CalendarRecurrenceRule].self, forKey: .recurrenceRules)
        present = Set(rawKeys)
    }

    public func has(_ key: String) -> Bool { present.contains(key) }

    public func validated() throws -> ReminderPatch {
        if has("listID"), listID == nil { throw ReminderError.invalidInput("listID cannot be null") }
        if has("title"), title == nil { throw ReminderError.invalidInput("title cannot be null") }
        if has("priority"), priority == nil { throw ReminderError.invalidInput("priority cannot be null") }
        let validated = try ReminderInput(
            listID: has("listID") ? listID : nil,
            title: title ?? "patch-validation-placeholder",
            notes: has("notes") ? notes : nil,
            url: has("url") ? url : nil,
            priority: priority ?? .none,
            start: has("start") ? start : nil,
            due: has("due") ? due : nil,
            alarms: has("alarms") ? (alarms ?? []) : [],
            recurrenceRules: has("recurrenceRules") ? (recurrenceRules ?? []) : []
        ).validated()
        var copy = self
        if has("title") { copy.title = validated.title }
        return copy
    }
}

private struct ReminderInputAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
}

public struct ReminderDraft: Codable, Equatable, Sendable {
    public let listID: String
    public let listTitle: String
    public let title: String
    public let notes: String?
    public let url: String?
    public let priority: ReminderPriority
    public let start: ReminderDateValue?
    public let due: ReminderDateValue?
    public let alarms: [ReminderAlarm]
    public let recurrenceRules: [CalendarRecurrenceRule]

    public init(
        listID: String, listTitle: String, title: String, notes: String?, url: String?,
        priority: ReminderPriority, start: ReminderDateValue?, due: ReminderDateValue?,
        alarms: [ReminderAlarm], recurrenceRules: [CalendarRecurrenceRule]
    ) {
        self.listID = listID
        self.listTitle = listTitle
        self.title = title
        self.notes = notes
        self.url = url
        self.priority = priority
        self.start = start
        self.due = due
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
    }
}

public struct ReminderCreatePreview: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let reminder: ReminderDraft

    public init(reminder: ReminderDraft) {
        operation = "create_preview"
        dryRun = true
        self.reminder = reminder
    }
}

public enum ReminderWriteVerification: String, Codable, Equatable, Sendable {
    case readbackConfirmed = "readback_confirmed"
    case saveAcceptedReadbackPending = "save_accepted_readback_pending"
    case idempotencyReceiptReadbackConfirmed = "idempotency_receipt_readback_confirmed"
    case idempotencyReceiptOnly = "idempotency_receipt_only"
}

public struct ReminderCreateResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let created: Bool
    public let verification: ReminderWriteVerification
    public let reminder: ReminderPayload
    public let nextAction: String?

    public init(
        operation: String,
        created: Bool,
        verification: ReminderWriteVerification,
        reminder: ReminderPayload,
        nextAction: String? = nil
    ) {
        self.operation = operation
        dryRun = false
        self.created = created
        self.verification = verification
        self.reminder = reminder
        self.nextAction = nextAction
    }
}

public struct ReminderUpdatePreview: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let before: ReminderPayload
    public let after: ReminderPayload

    public init(before: ReminderPayload, after: ReminderPayload) {
        operation = "update_preview"
        dryRun = true
        self.before = before
        self.after = after
    }
}

public struct ReminderUpdateResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let verification: ReminderWriteVerification
    public let reminder: ReminderPayload
    public let nextAction: String?

    public init(
        verification: ReminderWriteVerification,
        reminder: ReminderPayload,
        nextAction: String? = nil
    ) {
        operation = "updated"
        dryRun = false
        self.verification = verification
        self.reminder = reminder
        self.nextAction = nextAction
    }
}

public enum ReminderStateAction: String, Codable, Equatable, Sendable {
    case complete
    case reopen

    public var targetCompleted: Bool { self == .complete }
}

public struct ReminderStateChangePreview: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let before: ReminderPayload
    public let after: ReminderPayload

    public init(action: ReminderStateAction, before: ReminderPayload, after: ReminderPayload) {
        operation = action == .complete ? "complete_preview" : "reopen_preview"
        dryRun = true
        self.before = before
        self.after = after
    }
}

public struct ReminderStateChangeResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let verification: ReminderWriteVerification
    public let reminder: ReminderPayload
    public let nextOccurrence: ReminderPayload?
    public let nextAction: String?

    public static func noOp(action: ReminderStateAction, reminder: ReminderPayload) -> Self {
        Self(
            operation: action == .complete ? "already_completed" : "already_incomplete",
            changed: false, verification: .readbackConfirmed, reminder: reminder
        )
    }

    public static func confirmed(
        action: ReminderStateAction,
        reminder: ReminderPayload,
        nextOccurrence: ReminderPayload? = nil
    ) -> Self {
        Self(
            operation: action == .complete ? "completed" : "reopened",
            changed: true, verification: .readbackConfirmed,
            reminder: reminder, nextOccurrence: nextOccurrence
        )
    }

    public static func pending(action: ReminderStateAction, reminder: ReminderPayload) -> Self {
        Self(
            operation: action == .complete ? "completed" : "reopened",
            changed: true, verification: .saveAcceptedReadbackPending,
            reminder: reminder,
            nextAction: "EventKit accepted the state change but immediate read-back is pending. Do not retry automatically; use reminders get with the returned ID."
        )
    }

    private init(
        operation: String,
        changed: Bool,
        verification: ReminderWriteVerification,
        reminder: ReminderPayload,
        nextOccurrence: ReminderPayload? = nil,
        nextAction: String? = nil
    ) {
        self.operation = operation
        dryRun = false
        self.changed = changed
        self.verification = verification
        self.reminder = reminder
        self.nextOccurrence = nextOccurrence
        self.nextAction = nextAction
    }
}

public enum ReminderDeleteVerification: String, Codable, Equatable, Sendable {
    case preview
    case absenceConfirmed = "absence_confirmed"
    case removeAcceptedReadbackPending = "remove_accepted_readback_pending"
}

public struct ReminderDeleteResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let deleted: Bool
    public let verification: ReminderDeleteVerification
    public let reminder: ReminderPayload
    public let nextAction: String?

    public static func preview(_ reminder: ReminderPayload) -> Self {
        Self(
            operation: "delete_preview", dryRun: true, deleted: false,
            verification: .preview, reminder: reminder, nextAction: nil
        )
    }

    public static func confirmed(_ reminder: ReminderPayload) -> Self {
        Self(
            operation: "deleted", dryRun: false, deleted: true,
            verification: .absenceConfirmed, reminder: reminder, nextAction: nil
        )
    }

    public static func pending(_ reminder: ReminderPayload) -> Self {
        Self(
            operation: "deleted", dryRun: false, deleted: true,
            verification: .removeAcceptedReadbackPending, reminder: reminder,
            nextAction: "EventKit accepted the removal but immediate absence verification is pending. Do not retry automatically; use reminders get with the same ID."
        )
    }

    private init(
        operation: String,
        dryRun: Bool,
        deleted: Bool,
        verification: ReminderDeleteVerification,
        reminder: ReminderPayload,
        nextAction: String?
    ) {
        self.operation = operation
        self.dryRun = dryRun
        self.deleted = deleted
        self.verification = verification
        self.reminder = reminder
        self.nextAction = nextAction
    }
}

public struct ReminderPayload: Codable, Equatable, Sendable {
    public let id: String
    public let listID: String
    public let listTitle: String
    public let title: String
    public let notes: String?
    public let url: String?
    public let priority: ReminderPriority
    public let completed: Bool
    public let completionDate: Date?
    public let start: ReminderDateValue?
    public let due: ReminderDateValue?
    public let hasAlarms: Bool
    public let hasRecurrenceRules: Bool
    public let alarms: [ReminderAlarm]
    public let recurrenceRules: [CalendarRecurrenceRule]

    public init(
        id: String,
        listID: String,
        listTitle: String,
        title: String,
        notes: String? = nil,
        url: String? = nil,
        priority: ReminderPriority = .none,
        completed: Bool = false,
        completionDate: Date? = nil,
        start: ReminderDateValue? = nil,
        due: ReminderDateValue? = nil,
        hasAlarms: Bool = false,
        hasRecurrenceRules: Bool = false,
        alarms: [ReminderAlarm] = [],
        recurrenceRules: [CalendarRecurrenceRule] = []
    ) {
        self.id = id
        self.listID = listID
        self.listTitle = listTitle
        self.title = title
        self.notes = notes
        self.url = url
        self.priority = priority
        self.completed = completed
        self.completionDate = completionDate
        self.start = start
        self.due = due
        self.hasAlarms = hasAlarms
        self.hasRecurrenceRules = hasRecurrenceRules
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
    }
}

public enum ReminderQueryStatus: String, Codable, Equatable, Sendable {
    case incomplete
    case completed
    case all
}

public struct ReminderQuery: Equatable, Sendable {
    public let status: ReminderQueryStatus
    public let dueStart: Date?
    public let dueEnd: Date?
    public let listID: String?
    public let title: String?
    public let limit: Int
    public let cursor: String?

    public init(
        status: ReminderQueryStatus = .incomplete,
        dueStart: Date? = nil,
        dueEnd: Date? = nil,
        listID: String? = nil,
        title: String? = nil,
        limit: Int = Pagination.defaultLimit,
        cursor: String? = nil
    ) throws {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw ReminderError.invalidLimit }
        if let dueStart, let dueEnd, dueStart > dueEnd { throw ReminderError.invalidDateRange }
        self.status = status
        self.dueStart = dueStart
        self.dueEnd = dueEnd
        self.listID = listID
        self.title = title
        self.limit = limit
        self.cursor = cursor
    }
}
