import Core
import Photos
import XCTest
@testable import PhotosAdapter

final class PhotosAdapterTests: XCTestCase {
    private struct PermissionStub: PhotoAccessProviding {
        let status: PhotoAccessStatus
        func requestReadWriteAccess() async -> PhotoAccessStatus { status }
    }

    private struct CollectionStub: PhotoCollectionFetching {
        let descriptors: [PhotoCollectionDescriptor]
        func fetchCollections() throws -> [PhotoCollectionDescriptor] { descriptors }
    }

    private struct AssetStub: PhotoAssetFetching {
        let descriptors: [PhotoAssetDescriptor]

        func fetchAssets(start: Date, end: Date, albumLocalIdentifier: String?) throws -> [PhotoAssetDescriptor] {
            descriptors.filter { descriptor in
                guard let created = descriptor.creationDate, created >= start, created < end else { return false }
                return albumLocalIdentifier == nil || descriptor.albumLocalIdentifiers.contains(albumLocalIdentifier!)
            }
        }

        func fetchAsset(localIdentifier: String) throws -> PhotoAssetDescriptor? {
            descriptors.first { $0.localIdentifier == localIdentifier }
        }
    }

    private struct ExportStub: PhotoAssetExporting {
        func export(
            localIdentifier: String,
            variant: PhotoExportVariant,
            destination: URL,
            allowNetwork: Bool
        ) async throws -> PhotoExportArtifact {
            PhotoExportArtifact(
                resourceKind: variant.rawValue,
                contentType: "public.data",
                bytes: 12,
                networkAllowed: allowNetwork
            )
        }
    }

    private func asset(
        _ id: String,
        created: TimeInterval,
        media: PhotoMediaType = .image,
        favorite: Bool = false,
        hidden: Bool = false,
        albums: [String] = [],
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> PhotoAssetDescriptor {
        PhotoAssetDescriptor(
            localIdentifier: id,
            mediaType: media,
            mediaSubtypes: media == .image ? ["screenshot"] : [],
            pixelWidth: 100,
            pixelHeight: 200,
            duration: media == .video ? 3.5 : 0,
            creationDate: Date(timeIntervalSince1970: created),
            modificationDate: nil,
            favorite: favorite,
            hidden: hidden,
            burstIdentifier: nil,
            livePhoto: false,
            latitude: latitude,
            longitude: longitude,
            albumLocalIdentifiers: albums
        )
    }

    func testPermissionMapperPreservesLimitedAccess() {
        XCTAssertEqual(PhotosPermission.map(.notDetermined), .notDetermined)
        XCTAssertEqual(PhotosPermission.map(.restricted), .restricted)
        XCTAssertEqual(PhotosPermission.map(.denied), .denied)
        XCTAssertEqual(PhotosPermission.map(.limited), .limited)
        XCTAssertEqual(PhotosPermission.map(.authorized), .authorized)
    }

    func testPhotoKitFetchUsesOnlySupportedSortKeys() {
        XCTAssertEqual(PhotoKitAssetFetcher.sortDescriptorKeys, ["creationDate"])
    }

    func testResourceMapperDistinguishesFullLimitedAndDeniedReads() {
        let authorized = PhotosResourceMapper.map(status: .authorized)
        XCTAssertEqual(authorized.id, "photos_library_default")
        XCTAssertEqual(authorized.kind, .photosLibrary)
        XCTAssertEqual(authorized.provider, .photos)
        XCTAssertTrue(authorized.capabilities.readable)
        XCTAssertFalse(authorized.capabilities.writable)
        XCTAssertTrue(authorized.capabilities.selected)
        XCTAssertEqual(authorized.capabilities.permission, .available)

        let limited = PhotosResourceMapper.map(status: .limited)
        XCTAssertTrue(limited.capabilities.readable)
        XCTAssertEqual(limited.capabilities.permission, .limited)

        let denied = PhotosResourceMapper.map(status: .denied)
        XCTAssertFalse(denied.capabilities.readable)
        XCTAssertEqual(denied.capabilities.permission, .denied)
    }

    func testPermissionErrorsHaveStableCodes() {
        XCTAssertEqual(PhotoError.permissionRequired.machineCode, "PHOTOS_PERMISSION_REQUIRED")
        XCTAssertEqual(PhotoError.permissionDenied.machineCode, "PHOTOS_PERMISSION_DENIED")
        XCTAssertEqual(PhotoError.permissionRestricted.machineCode, "PHOTOS_PERMISSION_RESTRICTED")
    }

    func testAlbumOpaqueIDRoundTrips() throws {
        let albumID = PhotoOpaqueID.encode(localIdentifier: "album-local", kind: .album)
        XCTAssertEqual(try PhotoOpaqueID.decode(albumID, expectedKind: .album).localIdentifier, "album-local")
    }

    func testAlbumOpaqueIDRejectsWrongKind() {
        let albumID = PhotoOpaqueID.encode(localIdentifier: "album-local", kind: .album)
        XCTAssertThrowsError(try PhotoOpaqueID.decode(albumID, expectedKind: .asset)) { error in
            XCTAssertEqual(error as? PhotoError, .invalidIdentifier)
        }
    }

    func testAlbumOpaqueIDRejectsMalformedToken() {
        XCTAssertThrowsError(try PhotoOpaqueID.decode("photoalbum_broken", expectedKind: .album))
    }

    func testAlbumMapperPreservesHierarchyAndDuplicateTitles() {
        let descriptors = [
            PhotoCollectionDescriptor(localIdentifier: "folder", title: "Trips", kind: .folder, parentLocalIdentifier: nil, depth: 0, canContainAssets: false, canContainCollections: true, estimatedAssetCount: nil),
            PhotoCollectionDescriptor(localIdentifier: "a", title: "Japan", kind: .userAlbum, parentLocalIdentifier: "folder", depth: 1, canContainAssets: true, canContainCollections: false, estimatedAssetCount: 12),
            PhotoCollectionDescriptor(localIdentifier: "b", title: "Japan", kind: .userAlbum, parentLocalIdentifier: nil, depth: 0, canContainAssets: true, canContainCollections: false, estimatedAssetCount: nil),
            PhotoCollectionDescriptor(localIdentifier: "favorite", title: "Favorites", kind: .smartAlbum, parentLocalIdentifier: nil, depth: 0, canContainAssets: true, canContainCollections: false, estimatedAssetCount: 3)
        ]
        let mapped = PhotoAlbumMapper.map(descriptors)

        XCTAssertEqual(mapped.count, 4)
        XCTAssertEqual(mapped[1].parentID, mapped[0].id)
        XCTAssertEqual(mapped.filter { $0.title == "Japan" }.count, 2)
        XCTAssertNotEqual(mapped[1].id, mapped[2].id)
        XCTAssertEqual(mapped[3].kind, .smartAlbum)
    }

    func testAlbumStoreFailsClosedWithoutReadablePermission() {
        for (status, expected) in [
            (PhotoAccessStatus.notDetermined, PhotoError.permissionRequired),
            (.denied, .permissionDenied),
            (.restricted, .permissionRestricted)
        ] {
            let store = PhotosStore(permission: PermissionStub(status: status), collections: CollectionStub(descriptors: []))
            XCTAssertThrowsError(try store.albums()) { error in
                XCTAssertEqual(error as? PhotoError, expected)
            }
        }
    }

    func testAlbumPaginationBindsKindAndPreservesLimitedCompleteness() throws {
        let descriptors = [
            PhotoCollectionDescriptor(localIdentifier: "folder", title: "Folder", kind: .folder, parentLocalIdentifier: nil, depth: 0, canContainAssets: false, canContainCollections: true, estimatedAssetCount: nil),
            PhotoCollectionDescriptor(localIdentifier: "user", title: "User", kind: .userAlbum, parentLocalIdentifier: nil, depth: 0, canContainAssets: true, canContainCollections: false, estimatedAssetCount: 1),
            PhotoCollectionDescriptor(localIdentifier: "smart", title: "Smart", kind: .smartAlbum, parentLocalIdentifier: nil, depth: 0, canContainAssets: true, canContainCollections: false, estimatedAssetCount: 2)
        ]
        let store = PhotosStore(permission: PermissionStub(status: .limited), collections: CollectionStub(descriptors: descriptors))
        let first = try store.albums(kind: .all, limit: 2)
        XCTAssertEqual(first.items.count, 2)
        XCTAssertTrue(first.truncated)
        XCTAssertFalse(first.complete)

        let second = try store.albums(kind: .all, limit: 2, cursor: first.nextCursor)
        XCTAssertEqual(second.items.count, 1)
        XCTAssertFalse(second.truncated)
        XCTAssertFalse(second.complete)

        XCTAssertThrowsError(try store.albums(kind: .smart, limit: 2, cursor: first.nextCursor)) { error in
            XCTAssertEqual(error as? PaginationError, .invalidCursor)
        }
    }

    func testAssetQueryCombinesFiltersAndExcludesHiddenByDefault() throws {
        let descriptors = [
            asset("new", created: 300, favorite: true, albums: ["album"]),
            asset("video", created: 250, media: .video, favorite: true, albums: ["album"]),
            asset("hidden", created: 200, favorite: true, hidden: true, albums: ["album"]),
            asset("other", created: 150, favorite: true, albums: ["other"])
        ]
        let store = PhotosStore(
            permission: PermissionStub(status: .authorized),
            collections: CollectionStub(descriptors: []),
            assets: AssetStub(descriptors: descriptors)
        )
        let albumID = PhotoOpaqueID.encode(localIdentifier: "album", kind: .album)
        let page = try store.query(PhotoAssetQuery(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 400),
            albumID: albumID,
            mediaType: .image,
            favorite: true
        ))

        XCTAssertEqual(page.items.map(\.id), [PhotoOpaqueID.encode(localIdentifier: "new", kind: .asset)])
        XCTAssertTrue(page.complete)
    }

    func testAssetQueryLocationIsOptInAndOrderingUsesOpaqueIDTieBreak() throws {
        let descriptors = [
            asset("b", created: 300, latitude: 35.0, longitude: 139.0),
            asset("a", created: 300, latitude: 34.0, longitude: 138.0)
        ]
        let store = PhotosStore(
            permission: PermissionStub(status: .limited),
            collections: CollectionStub(descriptors: []),
            assets: AssetStub(descriptors: descriptors)
        )
        let base = PhotoAssetQuery(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 400))
        let privatePage = try store.query(base)
        XCTAssertEqual(privatePage.items.map(\.id), privatePage.items.map(\.id).sorted())
        XCTAssertTrue(privatePage.items.allSatisfy { $0.location == nil })
        XCTAssertFalse(privatePage.complete)

        let located = try store.query(PhotoAssetQuery(
            start: base.start,
            end: base.end,
            includeLocation: true
        ))
        XCTAssertNotNil(located.items.first?.location)
    }

    func testAssetPaginationCursorIsBoundToFilters() throws {
        let store = PhotosStore(
            permission: PermissionStub(status: .authorized),
            collections: CollectionStub(descriptors: []),
            assets: AssetStub(descriptors: [asset("a", created: 300), asset("b", created: 200)])
        )
        let first = try store.query(PhotoAssetQuery(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 400),
            limit: 1
        ))
        XCTAssertTrue(first.truncated)
        XCTAssertEqual(try store.query(PhotoAssetQuery(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 400),
            limit: 1,
            cursor: first.nextCursor
        )).items.count, 1)
        XCTAssertThrowsError(try store.query(PhotoAssetQuery(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 400),
            favorite: true,
            limit: 1,
            cursor: first.nextCursor
        )))
    }

    func testAssetGetUsesOpaqueIDAndHonorsLocationOptIn() throws {
        let descriptor = asset("asset", created: 300, latitude: 35, longitude: 139)
        let store = PhotosStore(
            permission: PermissionStub(status: .authorized),
            collections: CollectionStub(descriptors: []),
            assets: AssetStub(descriptors: [descriptor])
        )
        let id = PhotoOpaqueID.encode(localIdentifier: "asset", kind: .asset)
        XCTAssertNil(try store.get(id: id).location)
        XCTAssertEqual(try store.get(id: id, includeLocation: true).location?.latitude, 35)
        XCTAssertThrowsError(try store.get(id: PhotoOpaqueID.encode(localIdentifier: "missing", kind: .asset))) { error in
            XCTAssertEqual(error as? PhotoError, .assetNotFound("missing"))
        }
    }

    func testAssetQueryRejectsInvalidOrOverwideDateRange() {
        let store = PhotosStore(
            permission: PermissionStub(status: .authorized),
            collections: CollectionStub(descriptors: []),
            assets: AssetStub(descriptors: [])
        )
        XCTAssertThrowsError(try store.query(PhotoAssetQuery(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 10))))
        XCTAssertThrowsError(try store.query(PhotoAssetQuery(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 367 * 86_400))))
    }

    func testExportResourceSelectionIsExplicitAndFailsOnAmbiguity() throws {
        let original = PhotoExportResourceDescriptor(kind: .photo, contentType: "public.jpeg")
        let paired = PhotoExportResourceDescriptor(kind: .pairedVideo, contentType: "com.apple.quicktime-movie")
        XCTAssertEqual(
            try PhotoExportResourceSelector.select([original, paired], variant: .original),
            original
        )
        XCTAssertEqual(
            try PhotoExportResourceSelector.select([original, paired], variant: .pairedVideo),
            paired
        )
        XCTAssertThrowsError(try PhotoExportResourceSelector.select([], variant: .current)) { error in
            XCTAssertEqual(error as? PhotoError, .exportVariantUnavailable)
        }
        XCTAssertThrowsError(try PhotoExportResourceSelector.select([original, original], variant: .original)) { error in
            XCTAssertEqual(error as? PhotoError, .exportVariantAmbiguous)
        }
    }

    func testExportDefaultsToOfflineAndReturnsNoMediaBytesInPayload() async throws {
        let store = PhotosStore(
            permission: PermissionStub(status: .authorized),
            collections: CollectionStub(descriptors: []),
            assets: AssetStub(descriptors: []),
            exporter: ExportStub()
        )
        let id = PhotoOpaqueID.encode(localIdentifier: "asset", kind: .asset)
        let result = try await store.export(id: id, outputURL: URL(fileURLWithPath: "/tmp/export.jpg"))
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.variant, .original)
        XCTAssertEqual(result.bytes, 12)
        XCTAssertFalse(result.networkAllowed)
    }

    func testExportDestinationRefusesOverwriteAndUsesPrivateTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("asset.jpg")
        FileManager.default.createFile(atPath: output.path, contents: Data())
        XCTAssertThrowsError(try PhotoExportFileCoordinator.prepare(outputURL: output)) { error in
            XCTAssertEqual(error as? PhotoError, .outputExists)
        }

        try FileManager.default.removeItem(at: output)
        let temporary = try PhotoExportFileCoordinator.prepare(outputURL: output)
        XCTAssertEqual(temporary.deletingLastPathComponent().standardizedFileURL.path, directory.standardizedFileURL.path)
        XCTAssertTrue(temporary.lastPathComponent.hasPrefix(".macos-data-export-"))
        XCTAssertNotEqual(temporary, output)
    }

    func testExportFileCommitMovesAtomicallyWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("asset.bin")
        let temporary = try PhotoExportFileCoordinator.prepare(outputURL: output)
        try Data([1, 2, 3]).write(to: temporary)

        try PhotoExportFileCoordinator.commit(temporaryURL: temporary, outputURL: output)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertEqual(try Data(contentsOf: output), Data([1, 2, 3]))
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
