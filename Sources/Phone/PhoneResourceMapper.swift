import Core

public enum PhoneResourceMapper {
    public static func map(status: PhoneCallsPermissionStatus) -> DataResource {
        let state: DataPermissionState = status.readable ? .available : .denied
        return DataResource(
            id: "phone_library_default",
            kind: .phoneLibrary,
            provider: .phone,
            displayName: "Call History",
            capabilities: .init(
                readable: status.readable,
                writable: false,
                selected: true,
                permission: state
            )
        )
    }
}
