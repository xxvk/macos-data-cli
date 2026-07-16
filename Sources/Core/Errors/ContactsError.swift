public enum ContactsError: Error, Equatable, Sendable, CustomStringConvertible {
    case permissionRequired
    case permissionDenied
    case permissionRestricted
    case readFailed(String)
    case invalidInput(String)
    case duplicateExternalID(String)
    case externalIDImmutable
    case externalIDMigrationConfirmationRequired
    case icloudContainerNotFound

    public var description: String {
        switch self {
        case .permissionRequired: return "Contacts permission has not been granted. Run 'macos-data contacts permission' and allow access in macOS Settings."
        case .permissionDenied: return "Contacts permission was denied. Enable access in System Settings > Privacy & Security > Contacts."
        case .permissionRestricted: return "Contacts access is restricted by macOS or device policy."
        case .readFailed(let message): return "Unable to read Contacts: \(message)"
        case .invalidInput(let message): return "Invalid contact input: \(message)"
        case .duplicateExternalID(let id): return "A contact with external ID '\(id)' already exists."
        case .externalIDImmutable: return "external_id cannot be changed by a regular contact edit."
        case .externalIDMigrationConfirmationRequired: return "External ID migration requires --confirm \"CHANGE EXTERNAL ID\"."
        case .icloudContainerNotFound: return "iCloud Contacts container was not found. Sign in to iCloud and enable Contacts synchronization."
        }
    }
}
