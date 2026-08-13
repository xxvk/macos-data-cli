import Core
import Foundation

public enum CalendarSelector {
    public static func selectForWrite(
        _ calendars: [CalendarDescriptor],
        selector: String? = nil,
        preferredIdentifier: String? = nil
    ) throws -> CalendarDescriptor {
        if let selector {
            let matches = matching(calendars, selector: selector)
            guard !matches.isEmpty else { throw CalendarError.calendarNotFound(selector) }
            guard matches.count == 1 else { throw CalendarError.ambiguousCalendar(matches.count) }
            guard matches[0].allowsContentModifications else { throw CalendarError.calendarReadOnly(matches[0].title) }
            return matches[0]
        }

        if let preferredIdentifier,
           let preferred = calendars.first(where: { $0.identifier == preferredIdentifier && $0.allowsContentModifications }) {
            return preferred
        }
        let writable = calendars.filter(\.allowsContentModifications)
        guard !writable.isEmpty else { throw CalendarError.calendarNotFound("writable iCloud calendar") }
        guard writable.count == 1 else { throw CalendarError.ambiguousCalendar(writable.count) }
        return writable[0]
    }

    public static func matching(_ calendars: [CalendarDescriptor], selector: String) -> [CalendarDescriptor] {
        let normalized = selector.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return calendars.filter {
            $0.identifier == selector || $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        }
    }
}
