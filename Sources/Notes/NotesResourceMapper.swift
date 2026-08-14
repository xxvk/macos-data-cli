import Core

public enum NotesResourceMapper {
    public static func map(status: NotesAutomationStatus, writable: Bool = false) -> DataResource {
        let permission: DataPermissionState = switch status {
        case .available: .available
        case .denied: .denied
        case .requiresConsent: .requiresConsent
        case .targetNotRunning, .targetUnavailable: .unavailable
        case .unknown: .unknown
        }

        return DataResource(
            id: "notes_library_default",
            kind: .notesLibrary,
            provider: .notes,
            displayName: "Apple Notes",
            capabilities: DataResourceCapabilities(
                readable: status.readable,
                writable: status == .available && writable,
                selected: true,
                permission: permission
            )
        )
    }
}
