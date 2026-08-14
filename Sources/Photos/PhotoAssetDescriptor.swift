import Core
import Foundation

public struct PhotoAssetDescriptor: Equatable, Sendable {
    public let localIdentifier: String
    public let mediaType: PhotoMediaType
    public let mediaSubtypes: [String]
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: Double
    public let creationDate: Date?
    public let modificationDate: Date?
    public let favorite: Bool
    public let hidden: Bool
    public let burstIdentifier: String?
    public let livePhoto: Bool
    public let latitude: Double?
    public let longitude: Double?
    public let albumLocalIdentifiers: [String]

    public init(
        localIdentifier: String,
        mediaType: PhotoMediaType,
        mediaSubtypes: [String],
        pixelWidth: Int,
        pixelHeight: Int,
        duration: Double,
        creationDate: Date?,
        modificationDate: Date?,
        favorite: Bool,
        hidden: Bool,
        burstIdentifier: String?,
        livePhoto: Bool,
        latitude: Double?,
        longitude: Double?,
        albumLocalIdentifiers: [String]
    ) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.favorite = favorite
        self.hidden = hidden
        self.burstIdentifier = burstIdentifier
        self.livePhoto = livePhoto
        self.latitude = latitude
        self.longitude = longitude
        self.albumLocalIdentifiers = albumLocalIdentifiers
    }
}

public protocol PhotoAssetFetching: Sendable {
    func fetchAssets(start: Date, end: Date, albumLocalIdentifier: String?) throws -> [PhotoAssetDescriptor]
    func fetchAsset(localIdentifier: String) throws -> PhotoAssetDescriptor?
}
