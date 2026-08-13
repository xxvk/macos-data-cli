import Core
import Foundation

public struct CalendarEventLocator: Codable, Equatable, Sendable {
    public let calendarItemIdentifier: String
    public let occurrenceStart: Date

    public init(calendarItemIdentifier: String, occurrenceStart: Date) {
        self.calendarItemIdentifier = calendarItemIdentifier
        self.occurrenceStart = occurrenceStart
    }
}

public enum CalendarOpaqueID {
    private static let prefix = "calevent_"

    public static func encode(calendarItemIdentifier: String, occurrenceStart: Date) -> String {
        let locator = CalendarEventLocator(calendarItemIdentifier: calendarItemIdentifier, occurrenceStart: occurrenceStart)
        let data = (try? JSONEncoder().encode(locator)) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ value: String) throws -> CalendarEventLocator {
        guard value.hasPrefix(prefix) else { throw CalendarError.eventNotFound(value) }
        var encoded = String(value.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let locator = try? JSONDecoder().decode(CalendarEventLocator.self, from: data),
              !locator.calendarItemIdentifier.isEmpty else {
            throw CalendarError.eventNotFound(value)
        }
        return locator
    }
}
