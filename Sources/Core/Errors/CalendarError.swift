public enum CalendarError: Error, Equatable, Sendable, CustomStringConvertible {
    case permissionRequired
    case permissionDenied
    case permissionRestricted
    case fullAccessRequired
    case icloudSourceNotFound
    case ambiguousSource(Int)
    case sourceNotFound(String)
    case calendarNotFound(String)
    case ambiguousCalendar(Int)
    case eventNotFound(String)
    case invalidDateRange
    case invalidInput(String)
    case calendarReadOnly(String)
    case recurringSpanRequired
    case idempotencyConflict(Int)
    case conflictScanLimitExceeded
    case readFailed(String)
    case writeFailed(String)

    public var machineCode: String {
        switch self {
        case .permissionRequired: "CALENDAR_PERMISSION_REQUIRED"
        case .permissionDenied: "CALENDAR_PERMISSION_DENIED"
        case .permissionRestricted: "CALENDAR_PERMISSION_RESTRICTED"
        case .fullAccessRequired: "CALENDAR_FULL_ACCESS_REQUIRED"
        case .icloudSourceNotFound: "CALENDAR_ICLOUD_SOURCE_NOT_FOUND"
        case .ambiguousSource: "CALENDAR_SOURCE_AMBIGUOUS"
        case .sourceNotFound: "CALENDAR_SOURCE_NOT_FOUND"
        case .calendarNotFound: "CALENDAR_NOT_FOUND"
        case .ambiguousCalendar: "CALENDAR_AMBIGUOUS"
        case .eventNotFound: "CALENDAR_EVENT_NOT_FOUND"
        case .invalidDateRange: "CALENDAR_INVALID_DATE_RANGE"
        case .invalidInput: "CALENDAR_INVALID_INPUT"
        case .calendarReadOnly: "CALENDAR_READ_ONLY"
        case .recurringSpanRequired: "CALENDAR_RECURRING_SPAN_REQUIRED"
        case .idempotencyConflict: "CALENDAR_IDEMPOTENCY_CONFLICT"
        case .conflictScanLimitExceeded: "CALENDAR_CONFLICT_SCAN_LIMIT_EXCEEDED"
        case .readFailed: "CALENDAR_READ_FAILED"
        case .writeFailed: "CALENDAR_WRITE_FAILED"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Calendar permission has not been granted. Run 'mpia calendar permission' and allow full access."
        case .permissionDenied:
            "Calendar permission was denied. Enable full access in System Settings > Privacy & Security > Calendars."
        case .permissionRestricted:
            "Calendar access is restricted by macOS or device policy."
        case .fullAccessRequired:
            "Calendar full access is required for reads. Write-only access cannot query calendars or events."
        case .icloudSourceNotFound:
            "A unique iCloud Calendar source was not found. Sign in to iCloud and enable Calendar synchronization."
        case .ambiguousSource(let count):
            "Calendar source selection is ambiguous (\(count) matches). Specify --source <identifier>."
        case .sourceNotFound:
            "The requested iCloud Calendar source was not found."
        case .calendarNotFound:
            "The requested calendar was not found in the selected iCloud source."
        case .ambiguousCalendar(let count):
            "Calendar selection is ambiguous (\(count) writable calendars). Specify --calendar <identifier>."
        case .eventNotFound:
            "Calendar event was not found in the selected iCloud source, or its opaque ID is stale."
        case .invalidDateRange:
            "Calendar query requires start < end and a range no longer than 366 days."
        case .invalidInput(let message):
            "Invalid calendar input: \(message)"
        case .calendarReadOnly:
            "The selected calendar is read-only."
        case .recurringSpanRequired:
            "Recurring event changes require --span this or --span future."
        case .idempotencyConflict(let count):
            "Idempotent Calendar create found \(count) event(s) with the same title and start but different persisted fields."
        case .conflictScanLimitExceeded:
            "Conflict detection exceeded 200 events. Narrow the date range or select one calendar."
        case .readFailed(let message):
            "Unable to read Calendar: \(message)"
        case .writeFailed(let message):
            "Unable to write Calendar: \(message)"
        }
    }
}
