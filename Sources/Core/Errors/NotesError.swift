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
    case invalidWriteInput
    case writeAccountNotBound
    case writeAccountStale
    case writeAccountMismatch
    case sharedTarget
    case concurrencyConflict
    case bodyHashConflict
    case unsupportedRichContent
    case defaultFolderTarget
    case duplicateFolderName
    case folderCycle
    case folderConcurrencyConflict
    case incompleteFolderGraph
    case folderMoveUnsupported
    case folderNotEmpty
    case folderDeleteUnsupported
    case writeOutcomeUnknown

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
        case .invalidWriteInput: "NOTES_INVALID_WRITE_INPUT"
        case .writeAccountNotBound: "NOTES_WRITE_ACCOUNT_NOT_BOUND"
        case .writeAccountStale: "NOTES_WRITE_ACCOUNT_STALE"
        case .writeAccountMismatch: "NOTES_WRITE_ACCOUNT_MISMATCH"
        case .sharedTarget: "NOTES_SHARED_TARGET"
        case .concurrencyConflict: "NOTES_CONCURRENCY_CONFLICT"
        case .bodyHashConflict: "NOTES_BODY_HASH_CONFLICT"
        case .unsupportedRichContent: "NOTES_UNSUPPORTED_RICH_CONTENT"
        case .defaultFolderTarget: "NOTES_DEFAULT_FOLDER_TARGET"
        case .duplicateFolderName: "NOTES_DUPLICATE_FOLDER_NAME"
        case .folderCycle: "NOTES_FOLDER_CYCLE"
        case .folderConcurrencyConflict: "NOTES_FOLDER_CONCURRENCY_CONFLICT"
        case .incompleteFolderGraph: "NOTES_INCOMPLETE_FOLDER_GRAPH"
        case .folderMoveUnsupported: "NOTES_FOLDER_MOVE_UNSUPPORTED"
        case .folderNotEmpty: "NOTES_FOLDER_NOT_EMPTY"
        case .folderDeleteUnsupported: "NOTES_FOLDER_DELETE_UNSUPPORTED"
        case .writeOutcomeUnknown: "NOTES_WRITE_OUTCOME_UNKNOWN"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Notes.app Automation permission requires consent. Run: mpia OPTIONS /notes/permission --params '{\"request\":true}'."
        case .permissionDenied:
            "Notes.app Automation permission was denied. Enable mpia for Notes in System Settings > Privacy & Security > Automation."
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
        case .invalidWriteInput:
            "Notes write input is invalid or outside the guarded Notes write contract."
        case .writeAccountNotBound:
            "No user-confirmed iCloud Notes write account is bound."
        case .writeAccountStale:
            "The bound Notes write account is no longer available; bind it again."
        case .writeAccountMismatch:
            "The selected note or folder is outside the bound iCloud Notes account."
        case .sharedTarget:
            "Shared Notes and shared folders are read-only in the guarded write contract."
        case .concurrencyConflict:
            "The note modification date changed; fetch it again before writing."
        case .bodyHashConflict:
            "The note body hash changed; fetch the body again before writing."
        case .unsupportedRichContent:
            "The selected note contains attachments or unsupported rich content; guarded body replacement is refused."
        case .defaultFolderTarget:
            "The Notes account default folder cannot be renamed, moved, or used as a mutable folder parent."
        case .duplicateFolderName:
            "A sibling Notes folder with the same normalized name already exists."
        case .folderCycle:
            "The folder move would place a folder inside itself or one of its descendants."
        case .folderConcurrencyConflict:
            "The folder name or parent changed; list folders again before writing."
        case .incompleteFolderGraph:
            "The bounded Notes folder graph is incomplete; folder mutation is refused."
        case .folderMoveUnsupported:
            "Notes 4.13 folder move cannot preserve and confirm folder identity safely; apply is disabled."
        case .folderNotEmpty:
            "The selected Notes folder contains notes or child folders; recursive deletion is refused."
        case .folderDeleteUnsupported:
            "Notes 4.13 folder delete cannot prove durable iCloud deletion safely; apply is disabled."
        case .writeOutcomeUnknown:
            "The Notes write outcome is unknown. Do not retry automatically; query and verify first."
        }
    }
}
