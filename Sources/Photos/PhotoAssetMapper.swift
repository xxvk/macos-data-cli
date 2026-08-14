import Core

public enum PhotoAssetMapper {
    public static func map(_ descriptor: PhotoAssetDescriptor, includeLocation: Bool) -> PhotoAssetPayload {
        let location: PhotoLocationPayload?
        if includeLocation, let latitude = descriptor.latitude, let longitude = descriptor.longitude {
            location = PhotoLocationPayload(latitude: latitude, longitude: longitude)
        } else {
            location = nil
        }
        return PhotoAssetPayload(
            id: PhotoOpaqueID.encode(localIdentifier: descriptor.localIdentifier, kind: .asset),
            mediaType: descriptor.mediaType,
            mediaSubtypes: descriptor.mediaSubtypes.sorted(),
            pixelWidth: descriptor.pixelWidth,
            pixelHeight: descriptor.pixelHeight,
            duration: descriptor.mediaType == .video || descriptor.mediaType == .audio ? descriptor.duration : nil,
            creationDate: descriptor.creationDate,
            modificationDate: descriptor.modificationDate,
            favorite: descriptor.favorite,
            hidden: descriptor.hidden,
            burstIdentifier: descriptor.burstIdentifier,
            livePhoto: descriptor.livePhoto,
            location: location
        )
    }
}
