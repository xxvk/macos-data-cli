import Core

public enum PhotosResourceMapper {
    public static func map(status: PhotoAccessStatus) -> DataResource {
        let permission: DataPermissionState = switch status {
        case .notDetermined: .notDetermined
        case .restricted: .unavailable
        case .denied: .denied
        case .limited: .limited
        case .authorized: .available
        }

        return DataResource(
            id: "photos_library_default",
            kind: .photosLibrary,
            provider: .photos,
            displayName: "Photos Library",
            capabilities: DataResourceCapabilities(
                readable: status.canRead,
                writable: false,
                selected: true,
                permission: permission
            )
        )
    }
}
