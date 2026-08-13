import Foundation

public enum CalendarJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    public static func parseTimestamp(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw CalendarError.invalidInput("date-time values require ISO 8601 with a time-zone offset")
        }
        return date
    }

    public static func parseDateOnly(_ value: String, timeZone identifier: String?) throws -> Date {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw CalendarError.invalidInput("all-day values require YYYY-MM-DD")
        }
        let zone = try timeZone(identifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(timeZone: zone, year: parts[0], month: parts[1], day: parts[2])),
              calendar.component(.year, from: date) == parts[0],
              calendar.component(.month, from: date) == parts[1],
              calendar.component(.day, from: date) == parts[2] else {
            throw CalendarError.invalidInput("invalid calendar date")
        }
        return date
    }

    public static func dateOnlyString(_ date: Date, timeZone identifier: String?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = (try? timeZone(identifier)) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func timeZone(_ identifier: String?) throws -> TimeZone {
        guard let identifier else { return .current }
        guard let zone = TimeZone(identifier: identifier) else {
            throw CalendarError.invalidInput("unknown IANA time zone")
        }
        return zone
    }
}

public struct CalendarAlarm: Codable, Equatable, Sendable {
    public let relativeMinutes: Int?
    public let absoluteDate: Date?

    public init(relativeMinutes: Int? = nil, absoluteDate: Date? = nil) {
        self.relativeMinutes = relativeMinutes
        self.absoluteDate = absoluteDate
    }

    public func validated() throws -> CalendarAlarm {
        guard (relativeMinutes == nil) != (absoluteDate == nil) else {
            throw CalendarError.invalidInput("each alarm requires exactly one of relativeMinutes or absoluteDate")
        }
        guard relativeMinutes.map({ abs($0) <= 525_600 }) ?? true else {
            throw CalendarError.invalidInput("relativeMinutes exceeds one year")
        }
        return self
    }
}

public struct CalendarConflict: Codable, Equatable, Sendable {
    public let firstEventID: String
    public let secondEventID: String
    public let overlapStart: Date
    public let overlapEnd: Date
}

public struct CalendarConflictResult: Codable, Equatable, Sendable {
    public let checkedEventCount: Int
    public let conflicts: [CalendarConflict]
    public var hasConflicts: Bool { !conflicts.isEmpty }

    public init(checkedEventCount: Int, conflicts: [CalendarConflict]) {
        self.checkedEventCount = checkedEventCount
        self.conflicts = conflicts
    }
}

public enum CalendarConflictDetector {
    public static let maximumEventCount = 200

    public static func validateEventCount(_ count: Int) throws {
        guard count <= maximumEventCount else { throw CalendarError.conflictScanLimitExceeded }
    }

    public static func detect(_ events: [CalendarEventPayload]) -> [CalendarConflict] {
        let values = events.sorted { $0.startDate == $1.startDate ? $0.endDate < $1.endDate : $0.startDate < $1.startDate }
        var result: [CalendarConflict] = []
        for firstIndex in values.indices {
            guard let firstID = values[firstIndex].id else { continue }
            for secondIndex in values.index(after: firstIndex)..<values.endIndex {
                let second = values[secondIndex]
                if second.startDate >= values[firstIndex].endDate { break }
                guard let secondID = second.id else { continue }
                let start = max(values[firstIndex].startDate, second.startDate)
                let end = min(values[firstIndex].endDate, second.endDate)
                if start < end {
                    result.append(CalendarConflict(firstEventID: firstID, secondEventID: secondID, overlapStart: start, overlapEnd: end))
                }
            }
        }
        return result
    }
}

public enum CalendarIdempotencyMatcher {
    public static func equivalent(_ input: CalendarEventInput, _ event: CalendarEventPayload) -> Bool {
        (input.calendarID.map { $0 == event.calendarID } ?? true)
            && input.title == event.title
            && abs(input.startDate.timeIntervalSince(event.startDate)) < 0.001
            && abs(input.endDate.timeIntervalSince(event.endDate)) < 0.001
            && input.allDay == event.allDay
            && input.timeZone == event.timeZone
            && input.location == event.location
            && input.notes == event.notes
            && input.url == event.url
            && alarmKeys(input.alarms) == alarmKeys(event.alarms)
            && input.recurrenceRules == event.recurrenceRules
    }

    private static func alarmKeys(_ alarms: [CalendarAlarm]) -> [String] {
        alarms.map {
            if let minutes = $0.relativeMinutes { return "r:\(minutes)" }
            return "a:\($0.absoluteDate?.timeIntervalSince1970 ?? 0)"
        }.sorted()
    }
}
