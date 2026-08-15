public enum ReminderError: Error, Equatable, Sendable, CustomStringConvertible {
    case permissionRequired
    case permissionDenied
    case permissionRestricted
    case fullAccessRequired
    case icloudSourceNotFound
    case ambiguousSource(Int)
    case sourceNotFound(String)
    case listNotFound(String)
    case ambiguousList(Int)
    case listReadOnly(String)
    case reminderNotFound(String)
    case ambiguousReminder(Int)
    case invalidDateRange
    case invalidLimit
    case invalidInput(String)
    case unsupportedField(String)
    case writeFailed(String)
    case savedIdentifierUnavailable
    case queryTimedOut
    case queryCancelled
    case scanLimitExceeded(Int)
    case readFailed(String)

    public var machineCode: String {
        switch self {
        case .permissionRequired: "REMINDERS_PERMISSION_REQUIRED"
        case .permissionDenied: "REMINDERS_PERMISSION_DENIED"
        case .permissionRestricted: "REMINDERS_PERMISSION_RESTRICTED"
        case .fullAccessRequired: "REMINDERS_FULL_ACCESS_REQUIRED"
        case .icloudSourceNotFound: "REMINDERS_ICLOUD_SOURCE_NOT_FOUND"
        case .ambiguousSource: "REMINDERS_SOURCE_AMBIGUOUS"
        case .sourceNotFound: "REMINDERS_SOURCE_NOT_FOUND"
        case .listNotFound: "REMINDERS_LIST_NOT_FOUND"
        case .ambiguousList: "REMINDERS_LIST_AMBIGUOUS"
        case .listReadOnly: "REMINDERS_LIST_READ_ONLY"
        case .reminderNotFound: "REMINDERS_NOT_FOUND"
        case .ambiguousReminder: "REMINDERS_AMBIGUOUS"
        case .invalidDateRange: "REMINDERS_INVALID_DATE_RANGE"
        case .invalidLimit: "REMINDERS_INVALID_LIMIT"
        case .invalidInput: "REMINDERS_INVALID_INPUT"
        case .unsupportedField: "REMINDERS_UNSUPPORTED_FIELD"
        case .writeFailed: "REMINDERS_WRITE_FAILED"
        case .savedIdentifierUnavailable: "REMINDERS_SAVE_ACCEPTED_IDENTIFIER_UNAVAILABLE"
        case .queryTimedOut: "REMINDERS_QUERY_TIMED_OUT"
        case .queryCancelled: "REMINDERS_QUERY_CANCELLED"
        case .scanLimitExceeded: "REMINDERS_SCAN_LIMIT_EXCEEDED"
        case .readFailed: "REMINDERS_READ_FAILED"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Reminders permission has not been granted. Run 'mpia reminders permission' and allow full access."
        case .permissionDenied:
            "Reminders permission was denied. Enable full access in System Settings > Privacy & Security > Reminders."
        case .permissionRestricted:
            "Reminders access is restricted by macOS or device policy."
        case .fullAccessRequired:
            "Reminders full access is required."
        case .icloudSourceNotFound:
            "A unique iCloud Reminders source was not found. Sign in to iCloud and enable Reminders synchronization."
        case .ambiguousSource(let count):
            "Reminders source selection is ambiguous (\(count) matches). Specify --source <identifier>."
        case .sourceNotFound:
            "The requested iCloud Reminders source was not found."
        case .listNotFound:
            "The requested reminder list was not found in the selected iCloud source."
        case .ambiguousList(let count):
            "Reminder list selection is ambiguous (\(count) writable lists). Specify --list <identifier>."
        case .listReadOnly:
            "The selected reminder list is read-only."
        case .reminderNotFound:
            "The reminder was not found in the selected iCloud source, or its opaque ID is stale."
        case .ambiguousReminder(let count):
            "Reminder lookup is ambiguous (\(count) matches); no item was selected."
        case .invalidDateRange:
            "Reminder query requires due-start to be earlier than or equal to due-end."
        case .invalidLimit:
            "Reminder limit must be between 1 and 200."
        case .invalidInput(let message):
            "Invalid reminder input: \(message)"
        case .unsupportedField(let field):
            "Reminder field is not writable in 0.4: \(field)."
        case .writeFailed:
            "Unable to save Reminders data."
        case .savedIdentifierUnavailable:
            "Reminders accepted the save but did not return a usable identifier. Do not retry automatically; inspect Reminders before trying again."
        case .queryTimedOut:
            "Reminders query timed out before EventKit returned a result."
        case .queryCancelled:
            "Reminders query was cancelled."
        case .scanLimitExceeded(let maximum):
            "Reminders query exceeded the safe scan limit of \(maximum) items. Narrow the query by list, status, or due date."
        case .readFailed(let message):
            "Unable to read Reminders: \(message)"
        }
    }
}
