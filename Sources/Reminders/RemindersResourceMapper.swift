import Core

public enum RemindersResourceMapper {
    public static func map(
        _ source: ReminderSourceDescriptor,
        selected: Bool,
        permission: DataPermissionState
    ) -> DataResource {
        let available = permission == .available
        return DataResource(
            id: source.identifier,
            kind: .remindersSource,
            provider: source.isICloud ? .iCloud : .eventKit,
            displayName: source.title,
            capabilities: DataResourceCapabilities(
                readable: available,
                writable: available && source.isICloud,
                selected: selected,
                permission: permission
            )
        )
    }
}
