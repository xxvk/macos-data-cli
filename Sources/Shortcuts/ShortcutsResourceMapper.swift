import Core

public enum ShortcutsResourceMapper {
    public static func map(status: ShortcutsAutomationStatus) -> DataResource {
        let permission: DataPermissionState = switch status {
        case .available: .available
        case .denied: .denied
        case .requiresConsent: .requiresConsent
        case .targetNotRunning, .targetUnavailable: .unavailable
        case .unknown: .unknown
        }
        return DataResource(
            id: "shortcuts_library_default",
            kind: .shortcutsLibrary,
            provider: .shortcuts,
            displayName: "Apple Shortcuts",
            capabilities: .init(readable: status.readable, writable: status == .available, selected: true, permission: permission)
        )
    }
}
