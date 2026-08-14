public enum NotesError: Error, Equatable, CustomStringConvertible, Sendable {
    case permissionRequired
    case permissionDenied
    case targetUnavailable
    case targetNotRunning
    case automationUnknown
    case invalidIdentifier
    case invalidLimit
    case timedOut
    case executionFailed
    case invalidQuery
    case lockedNote
    case bodyTooLarge

    public var machineCode: String {
        switch self {
        case .permissionRequired: "NOTES_PERMISSION_REQUIRED"
        case .permissionDenied: "NOTES_PERMISSION_DENIED"
        case .targetUnavailable: "NOTES_TARGET_UNAVAILABLE"
        case .targetNotRunning: "NOTES_TARGET_NOT_RUNNING"
        case .automationUnknown: "NOTES_AUTOMATION_UNKNOWN"
        case .invalidIdentifier: "NOTES_INVALID_IDENTIFIER"
        case .invalidLimit: "NOTES_INVALID_LIMIT"
        case .timedOut: "NOTES_TIMEOUT"
        case .executionFailed: "NOTES_EXECUTION_FAILED"
        case .invalidQuery: "NOTES_INVALID_QUERY"
        case .lockedNote: "NOTES_LOCKED"
        case .bodyTooLarge: "NOTES_BODY_TOO_LARGE"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Notes.app Automation permission requires consent. Run 'macos-data notes permission --request'."
        case .permissionDenied:
            "Notes.app Automation permission was denied. Enable macos-data for Notes in System Settings > Privacy & Security > Automation."
        case .targetUnavailable:
            "Notes.app is unavailable on this Mac."
        case .targetNotRunning:
            "Notes.app is not running. Open Notes and retry the permission request."
        case .automationUnknown:
            "Notes.app Automation status could not be determined safely."
        case .invalidIdentifier:
            "Notes account, folder, or cursor identifier is invalid or stale."
        case .invalidLimit:
            "Notes page limit must be between 1 and 200."
        case .timedOut:
            "The bounded Notes.app Apple Event timed out."
        case .executionFailed:
            "Notes.app could not return a valid bounded metadata response."
        case .invalidQuery:
            "Notes query options are invalid or unsupported."
        case .lockedNote:
            "The selected note is password protected; body access is refused."
        case .bodyTooLarge:
            "The selected note body exceeds the 256 KiB response limit."
        }
    }
}
