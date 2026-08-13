import Foundation

public struct CalendarSourceDescriptor: Codable, Equatable, Sendable {
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

public struct CalendarDescriptor: Codable, Equatable, Sendable {
    public let title: String
    public let identifier: String
    public let sourceIdentifier: String
    public let type: String
    public let allowsContentModifications: Bool

    public init(title: String, identifier: String, sourceIdentifier: String, type: String, allowsContentModifications: Bool) {
        self.title = title
        self.identifier = identifier
        self.sourceIdentifier = sourceIdentifier
        self.type = type
        self.allowsContentModifications = allowsContentModifications
    }
}

public struct CalendarSourceListResult: Codable, Equatable, Sendable {
    public let sources: [CalendarSourceDescriptor]
    public let selectedSourceID: String

    public init(sources: [CalendarSourceDescriptor], selectedSourceID: String) {
        self.sources = sources
        self.selectedSourceID = selectedSourceID
    }
}

public struct CalendarListResult: Codable, Equatable, Sendable {
    public let calendars: [CalendarDescriptor]
    public let selectedSourceID: String

    public init(calendars: [CalendarDescriptor], selectedSourceID: String) {
        self.calendars = calendars
        self.selectedSourceID = selectedSourceID
    }
}

public struct CalendarAttendee: Codable, Equatable, Sendable {
    public let name: String?
    public let email: String?
    public let status: String
    public let role: String
    public let type: String?

    public init(name: String? = nil, email: String? = nil, status: String, role: String, type: String? = nil) {
        self.name = name
        self.email = email
        self.status = status
        self.role = role
        self.type = type
    }
}

public enum CalendarRecurrenceFrequency: String, Codable, Equatable, Sendable {
    case daily, weekly, monthly, yearly
}

public enum CalendarWeekday: String, Codable, Equatable, Sendable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday
}

public struct CalendarRecurrenceWeekday: Codable, Equatable, Sendable {
    public let weekday: CalendarWeekday
    public let weekNumber: Int

    public init(weekday: CalendarWeekday, weekNumber: Int) {
        self.weekday = weekday
        self.weekNumber = weekNumber
    }
}

public struct CalendarRecurrenceEnd: Codable, Equatable, Sendable {
    public let endDate: Date?
    public let occurrenceCount: Int?

    public init(endDate: Date? = nil, occurrenceCount: Int? = nil) {
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
    }
}

public struct CalendarRecurrenceRule: Codable, Equatable, Sendable {
    public let frequency: CalendarRecurrenceFrequency
    public let interval: Int
    public let daysOfWeek: [CalendarWeekday]
    public let weekdayOrdinals: [CalendarRecurrenceWeekday]
    public let daysOfMonth: [Int]
    public let monthsOfYear: [Int]
    public let weeksOfYear: [Int]
    public let daysOfYear: [Int]
    public let setPositions: [Int]
    public let end: CalendarRecurrenceEnd?

    public init(
        frequency: CalendarRecurrenceFrequency,
        interval: Int = 1,
        daysOfWeek: [CalendarWeekday] = [],
        weekdayOrdinals: [CalendarRecurrenceWeekday] = [],
        daysOfMonth: [Int] = [],
        monthsOfYear: [Int] = [],
        weeksOfYear: [Int] = [],
        daysOfYear: [Int] = [],
        setPositions: [Int] = [],
        end: CalendarRecurrenceEnd? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.weekdayOrdinals = weekdayOrdinals
        self.daysOfMonth = daysOfMonth
        self.monthsOfYear = monthsOfYear
        self.weeksOfYear = weeksOfYear
        self.daysOfYear = daysOfYear
        self.setPositions = setPositions
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, interval, daysOfWeek, weekdayOrdinals, daysOfMonth, monthsOfYear, weeksOfYear, daysOfYear, setPositions, end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(CalendarRecurrenceFrequency.self, forKey: .frequency)
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1
        daysOfWeek = try container.decodeIfPresent([CalendarWeekday].self, forKey: .daysOfWeek) ?? []
        weekdayOrdinals = try container.decodeIfPresent([CalendarRecurrenceWeekday].self, forKey: .weekdayOrdinals) ?? []
        daysOfMonth = try container.decodeIfPresent([Int].self, forKey: .daysOfMonth) ?? []
        monthsOfYear = try container.decodeIfPresent([Int].self, forKey: .monthsOfYear) ?? []
        weeksOfYear = try container.decodeIfPresent([Int].self, forKey: .weeksOfYear) ?? []
        daysOfYear = try container.decodeIfPresent([Int].self, forKey: .daysOfYear) ?? []
        setPositions = try container.decodeIfPresent([Int].self, forKey: .setPositions) ?? []
        end = try container.decodeIfPresent(CalendarRecurrenceEnd.self, forKey: .end)
    }
}

public struct CalendarEventPayload: Codable, Equatable, Sendable {
    public let id: String?
    public let calendarID: String?
    public let calendarTitle: String?
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let allDay: Bool
    public let timeZone: String?
    public let location: String?
    public let notes: String?
    public let url: String?
    public let attendees: [CalendarAttendee]
    public let alarms: [CalendarAlarm]
    public let recurrenceRules: [CalendarRecurrenceRule]
    public let availability: String
    public let status: String
    public let occurrenceDate: Date?
    public let isDetached: Bool

    public init(
        id: String? = nil,
        calendarID: String? = nil,
        calendarTitle: String? = nil,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool = false,
        timeZone: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: String? = nil,
        attendees: [CalendarAttendee] = [],
        alarms: [CalendarAlarm] = [],
        recurrenceRules: [CalendarRecurrenceRule] = [],
        availability: String = "notSupported",
        status: String = "none",
        occurrenceDate: Date? = nil,
        isDetached: Bool = false
    ) {
        self.id = id
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.attendees = attendees
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
        self.availability = availability
        self.status = status
        self.occurrenceDate = occurrenceDate
        self.isDetached = isDetached
    }
}

extension CalendarEventPayload {
    private enum CodingKeys: String, CodingKey {
        case id, calendarID, calendarTitle, title, startDate, endDate, allDay, timeZone
        case location, notes, url, attendees, alarms, recurrenceRules, availability, status, occurrenceDate, isDetached
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(calendarID, forKey: .calendarID)
        try container.encodeIfPresent(calendarTitle, forKey: .calendarTitle)
        try container.encode(title, forKey: .title)
        if allDay {
            try container.encode(CalendarJSON.dateOnlyString(startDate, timeZone: timeZone), forKey: .startDate)
            try container.encode(CalendarJSON.dateOnlyString(endDate, timeZone: timeZone), forKey: .endDate)
        } else {
            try container.encode(startDate, forKey: .startDate)
            try container.encode(endDate, forKey: .endDate)
        }
        try container.encode(allDay, forKey: .allDay)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(attendees, forKey: .attendees)
        try container.encode(alarms, forKey: .alarms)
        try container.encode(recurrenceRules, forKey: .recurrenceRules)
        try container.encode(availability, forKey: .availability)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(occurrenceDate, forKey: .occurrenceDate)
        try container.encode(isDetached, forKey: .isDetached)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allDay = try container.decode(Bool.self, forKey: .allDay)
        let timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        let startDate: Date
        let endDate: Date
        if allDay {
            startDate = try CalendarJSON.parseDateOnly(container.decode(String.self, forKey: .startDate), timeZone: timeZone)
            endDate = try CalendarJSON.parseDateOnly(container.decode(String.self, forKey: .endDate), timeZone: timeZone)
        } else {
            startDate = try container.decode(Date.self, forKey: .startDate)
            endDate = try container.decode(Date.self, forKey: .endDate)
        }
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            calendarID: try container.decodeIfPresent(String.self, forKey: .calendarID),
            calendarTitle: try container.decodeIfPresent(String.self, forKey: .calendarTitle),
            title: try container.decode(String.self, forKey: .title),
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            timeZone: timeZone,
            location: try container.decodeIfPresent(String.self, forKey: .location),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            url: try container.decodeIfPresent(String.self, forKey: .url),
            attendees: try container.decodeIfPresent([CalendarAttendee].self, forKey: .attendees) ?? [],
            alarms: try container.decodeIfPresent([CalendarAlarm].self, forKey: .alarms) ?? [],
            recurrenceRules: try container.decodeIfPresent([CalendarRecurrenceRule].self, forKey: .recurrenceRules) ?? [],
            availability: try container.decodeIfPresent(String.self, forKey: .availability) ?? "notSupported",
            status: try container.decodeIfPresent(String.self, forKey: .status) ?? "none",
            occurrenceDate: try container.decodeIfPresent(Date.self, forKey: .occurrenceDate),
            isDetached: try container.decodeIfPresent(Bool.self, forKey: .isDetached) ?? false
        )
    }
}

public struct CalendarEventInput: Codable, Equatable, Sendable {
    public let calendarID: String?
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let allDay: Bool
    public let timeZone: String?
    public let location: String?
    public let notes: String?
    public let url: String?
    public let attendees: [CalendarAttendee]
    public let alarms: [CalendarAlarm]
    public let recurrenceRules: [CalendarRecurrenceRule]
    public let usesDateOnlyValues: Bool

    public init(
        calendarID: String? = nil,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool = false,
        timeZone: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: String? = nil,
        attendees: [CalendarAttendee] = [],
        alarms: [CalendarAlarm] = [],
        recurrenceRules: [CalendarRecurrenceRule] = [],
        usesDateOnlyValues: Bool = false
    ) {
        self.calendarID = calendarID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.attendees = attendees
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
        self.usesDateOnlyValues = usesDateOnlyValues
    }

    private enum CodingKeys: String, CodingKey {
        case calendarID, title, startDate, endDate, allDay, timeZone, location, notes, url, attendees, alarms, recurrenceRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calendarID = try container.decodeIfPresent(String.self, forKey: .calendarID)
        title = try container.decode(String.self, forKey: .title)
        allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        let startValue = try container.decode(String.self, forKey: .startDate)
        let endValue = try container.decode(String.self, forKey: .endDate)
        usesDateOnlyValues = allDay
        startDate = try allDay ? CalendarJSON.parseDateOnly(startValue, timeZone: timeZone) : CalendarJSON.parseTimestamp(startValue)
        endDate = try allDay ? CalendarJSON.parseDateOnly(endValue, timeZone: timeZone) : CalendarJSON.parseTimestamp(endValue)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        attendees = try container.decodeIfPresent([CalendarAttendee].self, forKey: .attendees) ?? []
        alarms = try container.decodeIfPresent([CalendarAlarm].self, forKey: .alarms) ?? []
        recurrenceRules = try container.decodeIfPresent([CalendarRecurrenceRule].self, forKey: .recurrenceRules) ?? []
    }
}

public struct CalendarEventPatch: Codable, Sendable {
    public var calendarID: String?
    public var title: String?
    public var startDate: Date?
    public var endDate: Date?
    public var allDay: Bool?
    public var timeZone: String?
    public var location: String?
    public var notes: String?
    public var url: String?
    public var recurrenceRules: [CalendarRecurrenceRule]?
    public var alarms: [CalendarAlarm]?
    public var usesDateOnlyValues = false
    private var present: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case calendarID, title, startDate, endDate, allDay, timeZone, location, notes, url, alarms, recurrenceRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) throws -> T? {
            try container.contains(key) ? container.decodeIfPresent(T.self, forKey: key) : nil
        }
        calendarID = try value(.calendarID)
        title = try value(.title)
        allDay = try value(.allDay)
        timeZone = try value(.timeZone)
        if container.contains(.startDate) || container.contains(.endDate) {
            var detectedDateOnly: Bool?
            func parseDate(_ key: CodingKeys) throws -> Date? {
                guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
                let raw = try container.decode(String.self, forKey: key)
                let dateOnly = raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                if let detectedDateOnly, detectedDateOnly != dateOnly {
                    throw CalendarError.invalidInput("startDate and endDate must use the same date format")
                }
                detectedDateOnly = dateOnly
                return try dateOnly ? CalendarJSON.parseDateOnly(raw, timeZone: timeZone) : CalendarJSON.parseTimestamp(raw)
            }
            startDate = try parseDate(.startDate)
            endDate = try parseDate(.endDate)
            usesDateOnlyValues = detectedDateOnly ?? false
        }
        location = try value(.location)
        notes = try value(.notes)
        url = try value(.url)
        alarms = try value(.alarms)
        recurrenceRules = try value(.recurrenceRules)
        present = Set(container.allKeys.map(\.stringValue))
    }

    public func has(_ key: String) -> Bool { present.contains(key) }
}

public struct CalendarEventQuery: Codable, Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public var calendarID: String?
    public var title: String?
    public var limit: Int
    public var cursor: String?

    public init(
        startDate: Date,
        endDate: Date,
        calendarID: String? = nil,
        title: String? = nil,
        limit: Int = Pagination.defaultLimit,
        cursor: String? = nil
    ) throws {
        guard startDate < endDate, endDate.timeIntervalSince(startDate) <= 366 * 86_400 else {
            throw CalendarError.invalidDateRange
        }
        guard (1...Pagination.maximumLimit).contains(limit) else {
            throw PaginationError.invalidLimit
        }
        self.startDate = startDate
        self.endDate = endDate
        self.calendarID = calendarID
        self.title = title
        self.limit = limit
        self.cursor = cursor
    }
}

public enum CalendarMutationSpan: String, Codable, Equatable, Sendable {
    case thisEvent = "this"
    case futureEvents = "future"
}
