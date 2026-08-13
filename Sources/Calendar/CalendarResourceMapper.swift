import Core

public enum CalendarResourceMapper {
    public static func map(
        _ source: CalendarSourceDescriptor,
        selected: Bool,
        permission: DataPermissionState
    ) -> DataResource {
        let available = permission == .available
        return DataResource(
            id: source.identifier,
            kind: .calendarSource,
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
