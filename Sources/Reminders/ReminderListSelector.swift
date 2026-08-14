import Core
import Foundation

public enum ReminderListSelector {
    public static func selectForWrite(
        _ lists: [ReminderListDescriptor],
        selector: String? = nil,
        preferredIdentifier: String? = nil
    ) throws -> ReminderListDescriptor {
        if let selector {
            let matches = matching(lists, selector: selector)
            guard !matches.isEmpty else { throw ReminderError.listNotFound(selector) }
            guard matches.count == 1 else { throw ReminderError.ambiguousList(matches.count) }
            guard matches[0].allowsContentModifications else {
                throw ReminderError.listReadOnly(matches[0].title)
            }
            return matches[0]
        }

        if let preferredIdentifier,
           let preferred = lists.first(where: {
               $0.identifier == preferredIdentifier && $0.allowsContentModifications
           }) {
            return preferred
        }

        let writable = lists.filter(\.allowsContentModifications)
        guard !writable.isEmpty else { throw ReminderError.listNotFound("writable iCloud reminder list") }
        guard writable.count == 1 else { throw ReminderError.ambiguousList(writable.count) }
        return writable[0]
    }

    public static func matching(
        _ lists: [ReminderListDescriptor],
        selector: String
    ) -> [ReminderListDescriptor] {
        let normalized = selector.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return lists.filter {
            $0.identifier == selector ||
                $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        }
    }
}
