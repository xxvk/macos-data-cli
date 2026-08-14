import Foundation

public enum ReminderQueryMatcher {
    public static func matches(_ reminder: ReminderPayload, query: ReminderQuery) -> Bool {
        switch query.status {
        case .incomplete where reminder.completed: return false
        case .completed where !reminder.completed: return false
        default: break
        }

        if let title = query.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           !reminder.title.localizedCaseInsensitiveContains(title) {
            return false
        }

        if query.dueStart != nil || query.dueEnd != nil {
            guard let due = reminder.due?.comparisonDate() else { return false }
            if let start = query.dueStart, due < start { return false }
            if let end = query.dueEnd, due > end { return false }
        }

        return true
    }
}
