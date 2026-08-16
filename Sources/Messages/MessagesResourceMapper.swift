import Core

public enum MessagesResourceMapper {
    public static func map(status: MessagesPermissionStatus) -> DataResource {
        let state: DataPermissionState = status.readable ? .available : .denied
        return DataResource(
            id: "messages_library_default",
            kind: .messagesLibrary,
            provider: .messages,
            displayName: "Messages",
            capabilities: .init(
                readable: status.readable,
                writable: false,
                selected: true,
                permission: state
            )
        )
    }
}
