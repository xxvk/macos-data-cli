import Foundation

public enum SafariError: Error, Equatable, CustomStringConvertible, Sendable {
    case bookmarksUnavailable
    case readFailed
    case fileTooLarge
    case schemaUnsupported
    case invalidInput
    case invalidIdentifier
    case notFound
    case permissionRequired
    case permissionDenied
    case targetUnavailable
    case automationUnknown
    case addFailed
    case writeOutcomeUnknown
    case localMutationSafariRunning
    case localMutationStale
    case localMutationConfirmationRequired
    case localMutationUnsafe

    public var machineCode: String {
        switch self {
        case .bookmarksUnavailable: "SAFARI_BOOKMARKS_UNAVAILABLE"
        case .readFailed: "SAFARI_READ_FAILED"
        case .fileTooLarge: "SAFARI_BOOKMARKS_TOO_LARGE"
        case .schemaUnsupported: "SAFARI_SCHEMA_UNSUPPORTED"
        case .invalidInput: "SAFARI_INVALID_INPUT"
        case .invalidIdentifier: "SAFARI_INVALID_IDENTIFIER"
        case .notFound: "SAFARI_NOT_FOUND"
        case .permissionRequired: "SAFARI_AUTOMATION_PERMISSION_REQUIRED"
        case .permissionDenied: "SAFARI_AUTOMATION_PERMISSION_DENIED"
        case .targetUnavailable: "SAFARI_TARGET_UNAVAILABLE"
        case .automationUnknown: "SAFARI_AUTOMATION_UNKNOWN"
        case .addFailed: "SAFARI_READING_LIST_ADD_FAILED"
        case .writeOutcomeUnknown: "SAFARI_READING_LIST_OUTCOME_UNKNOWN"
        case .localMutationSafariRunning: "SAFARI_LOCAL_MUTATION_SAFARI_RUNNING"
        case .localMutationStale: "SAFARI_LOCAL_MUTATION_STALE"
        case .localMutationConfirmationRequired: "SAFARI_LOCAL_MUTATION_CONFIRMATION_REQUIRED"
        case .localMutationUnsafe: "SAFARI_LOCAL_MUTATION_UNSAFE"
        }
    }

    public var description: String {
        switch self {
        case .bookmarksUnavailable:
            "Safari bookmarks are not readable. Grant Full Disk Access to the stable macos-data app or its Terminal host, then retry."
        case .readFailed:
            "Safari bookmarks could not be read as one consistent property-list snapshot."
        case .fileTooLarge:
            "Safari Bookmarks.plist exceeds the 32 MiB safety limit."
        case .schemaUnsupported:
            "This Safari Bookmarks.plist schema is unsupported or internally inconsistent. No data was modified."
        case .invalidInput:
            "Safari input is invalid. Use strict JSON, an http/https URL without credentials, and the documented size limits."
        case .invalidIdentifier:
            "The Safari bookmark, folder, Reading List item, or cursor identifier is invalid or stale."
        case .notFound:
            "The selected Safari bookmark or Reading List item was not found."
        case .permissionRequired:
            "Safari Automation requires consent. Open Safari, then run 'macos-data safari permission --request'."
        case .permissionDenied:
            "Safari Automation was denied. Enable macos-data for Safari in System Settings > Privacy & Security > Automation."
        case .targetUnavailable:
            "Safari is unavailable or could not be reached."
        case .automationUnknown:
            "Safari Automation status could not be determined safely."
        case .addFailed:
            "Safari rejected the Reading List addition. No successful write was confirmed."
        case .writeOutcomeUnknown:
            "The Safari Apple Event exceeded its deadline. The item may have been added. Do not retry automatically; query the URL first."
        case .localMutationSafariRunning:
            "Quit Safari completely before applying a local bookmark mutation."
        case .localMutationStale:
            "Safari bookmark data changed or is in use. Run dry-run again and do not reuse the old source hash."
        case .localMutationConfirmationRequired:
            "Safari bookmark deletion requires the exact documented confirmation phrase."
        case .localMutationUnsafe:
            "The guarded local Safari mutation could not prove backup, atomic write, or read-back safety. No automatic retry is allowed."
        }
    }
}
