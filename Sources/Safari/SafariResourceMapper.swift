import Core

public enum SafariResourceMapper {
    public static func map(permission: SafariPermissionResult) -> DataResource {
        let state: DataPermissionState = permission.bookmarksReadable ? .available : .denied
        return DataResource(
            id: "safari_library_default",
            kind: .safariLibrary,
            provider: .safari,
            displayName: "Apple Safari",
            capabilities: .init(
                readable: permission.bookmarksReadable,
                writable: permission.readingListAddAvailable,
                selected: true,
                permission: state
            )
        )
    }
}
