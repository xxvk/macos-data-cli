import Core

public enum ContactsResourceMapper {
    public static func map(
        _ container: ContactContainer,
        selected: Bool,
        permission: DataPermissionState = .available
    ) -> DataResource {
        DataResource(
            id: container.identifier,
            kind: .contactsContainer,
            provider: container.isICloud ? .iCloud : .contacts,
            displayName: container.name,
            capabilities: DataResourceCapabilities(
                readable: permission == .available,
                writable: container.isICloud && permission == .available,
                selected: selected,
                permission: permission
            )
        )
    }
}
