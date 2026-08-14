import Core
import Foundation
import Photos

public struct PhotoKitAssetFetcher: PhotoAssetFetching, Sendable {
    public static let sortDescriptorKeys = ["creationDate"]

    public init() {}

    public func fetchAssets(start: Date, end: Date, albumLocalIdentifier: String?) throws -> [PhotoAssetDescriptor] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = Self.sortDescriptorKeys.map { NSSortDescriptor(key: $0, ascending: false) }

        let result: PHFetchResult<PHAsset>
        if let albumLocalIdentifier {
            let albums = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumLocalIdentifier], options: nil)
            guard let album = albums.firstObject else { throw PhotoError.invalidIdentifier }
            result = PHAsset.fetchAssets(in: album, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }

        var descriptors: [PhotoAssetDescriptor] = []
        descriptors.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            descriptors.append(Self.describe(asset, albumLocalIdentifier: albumLocalIdentifier))
        }
        return descriptors
    }

    public func fetchAsset(localIdentifier: String) throws -> PhotoAssetDescriptor? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject.map {
            Self.describe($0, albumLocalIdentifier: nil)
        }
    }

    private static func describe(_ asset: PHAsset, albumLocalIdentifier: String?) -> PhotoAssetDescriptor {
        PhotoAssetDescriptor(
            localIdentifier: asset.localIdentifier,
            mediaType: map(asset.mediaType),
            mediaSubtypes: map(asset.mediaSubtypes),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            favorite: asset.isFavorite,
            hidden: asset.isHidden,
            burstIdentifier: asset.burstIdentifier,
            livePhoto: asset.mediaSubtypes.contains(.photoLive),
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            albumLocalIdentifiers: albumLocalIdentifier.map { [$0] } ?? []
        )
    }

    private static func map(_ type: PHAssetMediaType) -> PhotoMediaType {
        switch type {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }

    private static func map(_ subtypes: PHAssetMediaSubtype) -> [String] {
        var values: [String] = []
        if subtypes.contains(.photoPanorama) { values.append("panorama") }
        if subtypes.contains(.photoHDR) { values.append("hdr") }
        if subtypes.contains(.photoScreenshot) { values.append("screenshot") }
        if subtypes.contains(.photoLive) { values.append("livePhoto") }
        if subtypes.contains(.photoDepthEffect) { values.append("depthEffect") }
        if subtypes.contains(.videoStreamed) { values.append("streamedVideo") }
        if subtypes.contains(.videoHighFrameRate) { values.append("highFrameRateVideo") }
        if subtypes.contains(.videoTimelapse) { values.append("timelapseVideo") }
        return values
    }
}
