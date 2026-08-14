import Foundation

public enum ReminderOrdering {
    public static func sorted(_ reminders: [ReminderPayload]) -> [ReminderPayload] {
        reminders.sorted(by: comesBefore)
    }

    private static func comesBefore(_ lhs: ReminderPayload, _ rhs: ReminderPayload) -> Bool {
        if lhs.completed != rhs.completed { return !lhs.completed }

        if !lhs.completed {
            switch (lhs.due, rhs.due) {
            case let (left?, right?):
                let leftDate = left.comparisonDate(defaultTimeZone: stableTimeZone)
                let rightDate = right.comparisonDate(defaultTimeZone: stableTimeZone)
                if leftDate != rightDate {
                    return (leftDate ?? .distantFuture) < (rightDate ?? .distantFuture)
                }
                if left.value != right.value { return left.value < right.value }
                if left.floating != right.floating { return left.floating && !right.floating }
                if left.timeZone != right.timeZone { return (left.timeZone ?? "") < (right.timeZone ?? "") }
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
        } else if lhs.completionDate != rhs.completionDate {
            return (lhs.completionDate ?? .distantPast) > (rhs.completionDate ?? .distantPast)
        }

        if lhs.listID != rhs.listID { return lhs.listID < rhs.listID }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static let stableTimeZone = TimeZone(secondsFromGMT: 0)!
}
