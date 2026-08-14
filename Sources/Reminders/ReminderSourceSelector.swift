import Core
import Foundation

public enum ReminderSourceSelector {
    public static func select(
        _ sources: [ReminderSourceDescriptor],
        selector: String? = nil
    ) throws -> ReminderSourceDescriptor {
        if let selector {
            let matches = sources.filter {
                $0.identifier == selector || normalized($0.title) == normalized(selector)
            }
            guard !matches.isEmpty else { throw ReminderError.sourceNotFound(selector) }
            guard matches.count == 1 else { throw ReminderError.ambiguousSource(matches.count) }
            guard matches[0].isICloud else { throw ReminderError.sourceNotFound(selector) }
            return matches[0]
        }

        let matches = sources.filter(\.isICloud)
        guard !matches.isEmpty else { throw ReminderError.icloudSourceNotFound }
        guard matches.count == 1 else { throw ReminderError.ambiguousSource(matches.count) }
        return matches[0]
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
