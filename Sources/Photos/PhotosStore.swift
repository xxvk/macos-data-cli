import Core
import Foundation

public final class PhotosStore: @unchecked Sendable {
    private let permission: any PhotoAccessProviding
    private let collections: any PhotoCollectionFetching
    private let assets: any PhotoAssetFetching
    private let exporter: any PhotoAssetExporting

    public init(
        permission: any PhotoAccessProviding = PhotosPermission(),
        collections: any PhotoCollectionFetching = PhotoKitCollectionFetcher(),
        assets: any PhotoAssetFetching = PhotoKitAssetFetcher(),
        exporter: any PhotoAssetExporting = PhotoKitAssetExporter()
    ) {
        self.permission = permission
        self.collections = collections
        self.assets = assets
        self.exporter = exporter
    }

    public func query(_ query: PhotoAssetQuery) throws -> PagedResult<PhotoAssetPayload> {
        try requireReadAccess()
        guard query.start < query.end,
              query.end.timeIntervalSince(query.start) <= PhotoAssetQuery.maximumRange else {
            throw PhotoError.invalidDateRange
        }
        guard (1...Pagination.maximumLimit).contains(query.limit) else { throw PhotoError.invalidLimit }
        let albumLocalIdentifier = try query.albumID.map {
            try PhotoOpaqueID.decode($0, expectedKind: .album).localIdentifier
        }
        let descriptors = try assets.fetchAssets(
            start: query.start,
            end: query.end,
            albumLocalIdentifier: albumLocalIdentifier
        )
        let mapped = descriptors
            .filter { query.includeHidden || !$0.hidden }
            .filter { query.mediaType == nil || $0.mediaType == query.mediaType }
            .filter { query.favorite == nil || $0.favorite == query.favorite }
            .map { PhotoAssetMapper.map($0, includeLocation: query.includeLocation) }
            .sorted {
                let left = $0.creationDate ?? .distantPast
                let right = $1.creationDate ?? .distantPast
                return left == right ? $0.id < $1.id : left > right
            }
        return try PhotoAssetPagination.page(items: mapped, query: query, complete: permission.status.complete)
    }

    public func get(id: String, includeLocation: Bool = false) throws -> PhotoAssetPayload {
        try requireReadAccess()
        let locator = try PhotoOpaqueID.decode(id, expectedKind: .asset)
        guard let descriptor = try assets.fetchAsset(localIdentifier: locator.localIdentifier) else {
            throw PhotoError.assetNotFound(locator.localIdentifier)
        }
        return PhotoAssetMapper.map(descriptor, includeLocation: includeLocation)
    }

    public func export(
        id: String,
        outputURL: URL,
        variant: PhotoExportVariant = .original,
        allowNetwork: Bool = false
    ) async throws -> PhotoExportPayload {
        try requireReadAccess()
        let locator = try PhotoOpaqueID.decode(id, expectedKind: .asset)
        let artifact = try await exporter.export(
            localIdentifier: locator.localIdentifier,
            variant: variant,
            destination: outputURL,
            allowNetwork: allowNetwork
        )
        return PhotoExportPayload(
            id: id,
            variant: variant,
            resourceKind: artifact.resourceKind,
            contentType: artifact.contentType,
            bytes: artifact.bytes,
            networkAllowed: artifact.networkAllowed
        )
    }

    public func albums(
        kind: PhotoAlbumQueryKind = .all,
        limit: Int = Pagination.defaultLimit,
        cursor: String? = nil
    ) throws -> PagedResult<PhotoAlbumPayload> {
        try requireReadAccess()
        let mapped = PhotoAlbumMapper.map(try collections.fetchCollections())
        let filtered = mapped.filter { album in
            switch kind {
            case .all: true
            case .user: album.kind == .userAlbum || album.kind == .folder
            case .smart: album.kind == .smartAlbum
            }
        }
        return try PhotoAlbumPagination.page(
            items: filtered,
            kind: kind,
            limit: limit,
            cursor: cursor,
            complete: permission.status.complete
        )
    }

    private func requireReadAccess() throws {
        switch permission.status {
        case .authorized, .limited: return
        case .notDetermined: throw PhotoError.permissionRequired
        case .denied: throw PhotoError.permissionDenied
        case .restricted: throw PhotoError.permissionRestricted
        }
    }
}
