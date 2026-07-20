public enum ContactsError: Error, Equatable, Sendable, CustomStringConvertible {
    case permissionRequired
    case permissionDenied
    case permissionRestricted
    case readFailed(String)
    case recordNeedsRecreation(String)
    case invalidInput(String)
    case duplicateExternalID(String)
    case idempotencyConflict(String)
    case externalIDImmutable
    case externalIDMigrationConfirmationRequired
    case avatarReplacementConfirmationRequired
    case icloudContainerNotFound

    public var description: String {
        switch self {
        case .permissionRequired: return "Contacts permission has not been granted. Run 'macos-data contacts permission' and allow access in macOS Settings."
        case .permissionDenied: return "Contacts permission was denied. Enable access in System Settings > Privacy & Security > Contacts."
        case .permissionRestricted: return "Contacts access is restricted by macOS or device policy."
        case .readFailed(let message): return "Unable to read Contacts: \(message)"
        case .recordNeedsRecreation(let externalID): return "Contacts record for external_id '\(externalID)' could not be saved because macOS Contacts reported CoreData error 134092. Preserve the JSON fields, then delete and recreate this contact before retrying the operation."
        case .invalidInput(let message): return "Invalid contact input: \(message)"
        case .duplicateExternalID(let id): return "A contact with external ID '\(id)' already exists."
        case .idempotencyConflict(let id): return "A contact with external ID '\(id)' already exists with different persisted fields; refusing an idempotent retry."
        case .externalIDImmutable: return "external_id cannot be changed by a regular contact edit."
        case .externalIDMigrationConfirmationRequired: return "External ID migration requires --confirm \"CHANGE EXTERNAL ID\"."
        case .avatarReplacementConfirmationRequired: return "Avatar replacement requires --confirm \"RECREATE CONTACT\"."
        case .icloudContainerNotFound: return "iCloud Contacts container was not found. Sign in to iCloud and enable Contacts synchronization."
        }
    }
}
