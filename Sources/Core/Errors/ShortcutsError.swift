public enum ShortcutsError: Error, Equatable, CustomStringConvertible, Sendable {
    case permissionRequired
    case permissionDenied
    case targetUnavailable
    case targetNotRunning
    case automationUnknown
    case invalidIdentifier
    case invalidLimit
    case timedOut
    case executionFailed
    case incompleteMetadata
    case moveVerificationFailed
    case confirmationRequired
    case invalidRunInput
    case outputExists
    case outputTooLarge
    case runFailed
    case runOutcomeUnknown

    public var machineCode: String {
        switch self {
        case .permissionRequired: "SHORTCUTS_PERMISSION_REQUIRED"
        case .permissionDenied: "SHORTCUTS_PERMISSION_DENIED"
        case .targetUnavailable: "SHORTCUTS_TARGET_UNAVAILABLE"
        case .targetNotRunning: "SHORTCUTS_TARGET_NOT_RUNNING"
        case .automationUnknown: "SHORTCUTS_AUTOMATION_UNKNOWN"
        case .invalidIdentifier: "SHORTCUTS_INVALID_IDENTIFIER"
        case .invalidLimit: "SHORTCUTS_INVALID_LIMIT"
        case .timedOut: "SHORTCUTS_TIMEOUT"
        case .executionFailed: "SHORTCUTS_EXECUTION_FAILED"
        case .incompleteMetadata: "SHORTCUTS_INCOMPLETE_METADATA"
        case .moveVerificationFailed: "SHORTCUTS_MOVE_VERIFICATION_FAILED"
        case .confirmationRequired: "SHORTCUTS_CONFIRMATION_REQUIRED"
        case .invalidRunInput: "SHORTCUTS_INVALID_RUN_INPUT"
        case .outputExists: "SHORTCUTS_OUTPUT_EXISTS"
        case .outputTooLarge: "SHORTCUTS_OUTPUT_TOO_LARGE"
        case .runFailed: "SHORTCUTS_RUN_FAILED"
        case .runOutcomeUnknown: "SHORTCUTS_RUN_OUTCOME_UNKNOWN"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Shortcuts Automation permission requires consent. Run 'macos-data shortcuts permission --request'."
        case .permissionDenied:
            "Shortcuts Automation permission was denied. Enable macos-data for Shortcuts Events in System Settings > Privacy & Security > Automation."
        case .targetUnavailable:
            "Shortcuts Events is unavailable on this Mac."
        case .targetNotRunning:
            "Shortcuts Events could not be reached. Open Shortcuts.app and retry."
        case .automationUnknown:
            "Shortcuts Automation status could not be determined safely."
        case .invalidIdentifier:
            "The shortcut, folder, or cursor identifier is invalid or stale."
        case .invalidLimit:
            "Shortcuts page limit must be between 1 and 200."
        case .timedOut:
            "The bounded Shortcuts Apple Event timed out."
        case .executionFailed:
            "Shortcuts Events could not return a valid bounded response."
        case .incompleteMetadata:
            "The bounded Shortcuts metadata snapshot is incomplete; mutation is refused."
        case .moveVerificationFailed:
            "Shortcuts accepted the move but the destination folder could not be confirmed. Do not retry automatically; list and verify first."
        case .confirmationRequired:
            "Applying a shortcut move requires --confirm \"MOVE SHORTCUT\"."
        case .invalidRunInput:
            "Shortcut run input is invalid. Use at most 16 readable files, a 1...300 second timeout, and a valid output UTI."
        case .outputExists:
            "Shortcut output already exists; automatic overwrite is refused."
        case .outputTooLarge:
            "Shortcut text output exceeds the 256 KiB JSON response limit; use --output-path."
        case .runFailed:
            "The system shortcuts CLI reported that the shortcut failed."
        case .runOutcomeUnknown:
            "The shortcut exceeded its deadline. Its side effects may have occurred. Do not retry automatically; inspect the target state first."
        }
    }
}
