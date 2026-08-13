import Core
import Foundation

public enum CalendarSourceSelector {
    public static func select(
        _ sources: [CalendarSourceDescriptor],
        selector: String? = nil
    ) throws -> CalendarSourceDescriptor {
        if let selector {
            let normalized = selector.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let matches = sources.filter {
                $0.identifier == selector || $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
            }
            guard !matches.isEmpty else { throw CalendarError.sourceNotFound(selector) }
            guard matches.count == 1 else { throw CalendarError.ambiguousSource(matches.count) }
            guard matches[0].isICloud else { throw CalendarError.sourceNotFound(selector) }
            return matches[0]
        }

        let matches = sources.filter(\.isICloud)
        guard !matches.isEmpty else { throw CalendarError.icloudSourceNotFound }
        guard matches.count == 1 else { throw CalendarError.ambiguousSource(matches.count) }
        return matches[0]
    }
}
