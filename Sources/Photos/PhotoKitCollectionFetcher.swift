import Core
import Foundation
import Photos

public protocol PhotoCollectionFetching: Sendable {
    func fetchCollections() throws -> [PhotoCollectionDescriptor]
}

public struct PhotoKitCollectionFetcher: PhotoCollectionFetching, Sendable {
    public init() {}

    public func fetchCollections() throws -> [PhotoCollectionDescriptor] {
        var descriptors: [PhotoCollectionDescriptor] = []
        var visited = Set<String>()
        let roots = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        for index in 0..<roots.count {
            append(roots.object(at: index), parent: nil, depth: 0, descriptors: &descriptors, visited: &visited)
        }

        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        for index in 0..<smartAlbums.count {
            let collection = smartAlbums.object(at: index)
            guard visited.insert(collection.localIdentifier).inserted else { continue }
            descriptors.append(descriptor(for: collection, parent: nil, depth: 0, kind: .smartAlbum))
        }
        return descriptors
    }

    private func append(
        _ collection: PHCollection,
        parent: String?,
        depth: Int,
        descriptors: inout [PhotoCollectionDescriptor],
        visited: inout Set<String>
    ) {
        guard visited.insert(collection.localIdentifier).inserted else { return }
        if let list = collection as? PHCollectionList {
            descriptors.append(descriptor(for: list, parent: parent, depth: depth, kind: .folder))
            let children = PHCollection.fetchCollections(in: list, options: nil)
            for index in 0..<children.count {
                append(children.object(at: index), parent: list.localIdentifier, depth: depth + 1, descriptors: &descriptors, visited: &visited)
            }
        } else if let album = collection as? PHAssetCollection {
            let kind: PhotoAlbumKind = album.assetCollectionType == .smartAlbum ? .smartAlbum : .userAlbum
            descriptors.append(descriptor(for: album, parent: parent, depth: depth, kind: kind))
        }
    }

    private func descriptor(
        for collection: PHCollection,
        parent: String?,
        depth: Int,
        kind: PhotoAlbumKind
    ) -> PhotoCollectionDescriptor {
        let estimatedCount: Int?
        if let album = collection as? PHAssetCollection, album.estimatedAssetCount != NSNotFound {
            estimatedCount = album.estimatedAssetCount
        } else {
            estimatedCount = nil
        }
        return PhotoCollectionDescriptor(
            localIdentifier: collection.localIdentifier,
            title: collection.localizedTitle,
            kind: kind,
            parentLocalIdentifier: parent,
            depth: depth,
            canContainAssets: collection.canContainAssets,
            canContainCollections: collection.canContainCollections,
            estimatedAssetCount: estimatedCount
        )
    }
}
