public enum PhotoAlbumKind: String, Codable, Equatable, Sendable {
    case userAlbum
    case smartAlbum
    case folder
}

public enum PhotoMediaType: String, Codable, Equatable, Sendable {
    case image
    case video
    case audio
    case unknown
}

public enum PhotoExportVariant: String, Codable, Equatable, Sendable {
    case original
    case current
    case pairedVideo = "paired-video"
    case adjustmentData = "adjustment-data"
}

public struct PhotoExportPayload: Codable, Equatable, Sendable {
    public let id: String
    public let variant: PhotoExportVariant
    public let resourceKind: String
    public let contentType: String?
    public let bytes: Int
    public let networkAllowed: Bool

    public init(
        id: String,
        variant: PhotoExportVariant,
        resourceKind: String,
        contentType: String?,
        bytes: Int,
        networkAllowed: Bool
    ) {
        self.id = id
        self.variant = variant
        self.resourceKind = resourceKind
        self.contentType = contentType
        self.bytes = bytes
        self.networkAllowed = networkAllowed
    }
}

public struct PhotoLocationPayload: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct PhotoAssetPayload: Codable, Equatable, Sendable {
    public let id: String
    public let mediaType: PhotoMediaType
    public let mediaSubtypes: [String]
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: Double?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let favorite: Bool
    public let hidden: Bool
    public let burstIdentifier: String?
    public let livePhoto: Bool
    public let contentAvailability: String
    public let location: PhotoLocationPayload?

    public init(
        id: String,
        mediaType: PhotoMediaType,
        mediaSubtypes: [String],
        pixelWidth: Int,
        pixelHeight: Int,
        duration: Double?,
        creationDate: Date?,
        modificationDate: Date?,
        favorite: Bool,
        hidden: Bool,
        burstIdentifier: String?,
        livePhoto: Bool,
        contentAvailability: String = "unknown",
        location: PhotoLocationPayload?
    ) {
        self.id = id
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
        self.contentAvailability = contentAvailability
        self.location = location
    }
}

public struct PhotoAssetQuery: Equatable, Sendable {
    public static let maximumRange: TimeInterval = 366 * 86_400

    public let start: Date
    public let end: Date
    public let albumID: String?
    public let mediaType: PhotoMediaType?
    public let favorite: Bool?
    public let includeHidden: Bool
    public let includeLocation: Bool
    public let limit: Int
    public let cursor: String?

    public init(
        start: Date,
        end: Date,
        albumID: String? = nil,
        mediaType: PhotoMediaType? = nil,
        favorite: Bool? = nil,
        includeHidden: Bool = false,
        includeLocation: Bool = false,
        limit: Int = Pagination.defaultLimit,
        cursor: String? = nil
    ) {
        self.start = start
        self.end = end
        self.albumID = albumID
        self.mediaType = mediaType
        self.favorite = favorite
        self.includeHidden = includeHidden
        self.includeLocation = includeLocation
        self.limit = limit
        self.cursor = cursor
    }
}

public enum PhotoAlbumQueryKind: String, Codable, Equatable, Sendable {
    case user
    case smart
    case all
}

public struct PhotoAlbumPayload: Codable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let kind: PhotoAlbumKind
    public let parentID: String?
    public let depth: Int
    public let canContainAssets: Bool
    public let canContainCollections: Bool
    public let estimatedAssetCount: Int?

    public init(
        id: String,
        title: String?,
        kind: PhotoAlbumKind,
        parentID: String?,
        depth: Int,
        canContainAssets: Bool,
        canContainCollections: Bool,
        estimatedAssetCount: Int?
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.parentID = parentID
        self.depth = depth
        self.canContainAssets = canContainAssets
        self.canContainCollections = canContainCollections
        self.estimatedAssetCount = estimatedAssetCount
    }
}
import Foundation
