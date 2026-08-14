import Core

public struct PhotoCollectionDescriptor: Equatable, Sendable {
    public let localIdentifier: String
    public let title: String?
    public let kind: PhotoAlbumKind
    public let parentLocalIdentifier: String?
    public let depth: Int
    public let canContainAssets: Bool
    public let canContainCollections: Bool
    public let estimatedAssetCount: Int?

    public init(
        localIdentifier: String,
        title: String?,
        kind: PhotoAlbumKind,
        parentLocalIdentifier: String?,
        depth: Int,
        canContainAssets: Bool,
        canContainCollections: Bool,
        estimatedAssetCount: Int?
    ) {
        self.localIdentifier = localIdentifier
        self.title = title
        self.kind = kind
        self.parentLocalIdentifier = parentLocalIdentifier
        self.depth = depth
        self.canContainAssets = canContainAssets
        self.canContainCollections = canContainCollections
        self.estimatedAssetCount = estimatedAssetCount
    }
}

public enum PhotoAlbumMapper {
    public static func map(_ descriptors: [PhotoCollectionDescriptor]) -> [PhotoAlbumPayload] {
        let ids = Dictionary(uniqueKeysWithValues: descriptors.map {
            ($0.localIdentifier, PhotoOpaqueID.encode(localIdentifier: $0.localIdentifier, kind: .album))
        })
        return descriptors.map { descriptor in
            PhotoAlbumPayload(
                id: ids[descriptor.localIdentifier]!,
                title: descriptor.title,
                kind: descriptor.kind,
                parentID: descriptor.parentLocalIdentifier.flatMap { ids[$0] },
                depth: descriptor.depth,
                canContainAssets: descriptor.canContainAssets,
                canContainCollections: descriptor.canContainCollections,
                estimatedAssetCount: descriptor.estimatedAssetCount
            )
        }
    }
}
