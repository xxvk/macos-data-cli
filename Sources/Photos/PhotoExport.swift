import Core
import Foundation
import Photos

public enum PhotoExportResourceKind: String, Equatable, Sendable {
    case photo
    case video
    case audio
    case alternatePhoto
    case fullSizePhoto
    case fullSizeVideo
    case adjustmentData
    case adjustmentBasePhoto
    case pairedVideo
    case fullSizePairedVideo
    case adjustmentBasePairedVideo
    case adjustmentBaseVideo
    case other
}

public struct PhotoExportResourceDescriptor: Equatable, Sendable {
    public let index: Int
    public let kind: PhotoExportResourceKind
    public let contentType: String?

    public init(index: Int = 0, kind: PhotoExportResourceKind, contentType: String?) {
        self.index = index
        self.kind = kind
        self.contentType = contentType
    }
}

public enum PhotoExportResourceSelector {
    public static func select(
        _ resources: [PhotoExportResourceDescriptor],
        variant: PhotoExportVariant
    ) throws -> PhotoExportResourceDescriptor {
        let priorities: [[PhotoExportResourceKind]] = switch variant {
        case .original: [[.photo, .video, .audio]]
        case .current: [[.fullSizePhoto, .fullSizeVideo], [.photo, .video, .audio]]
        case .pairedVideo: [[.fullSizePairedVideo], [.pairedVideo]]
        case .adjustmentData: [[.adjustmentData]]
        }
        for priority in priorities {
            let matches = resources.filter { priority.contains($0.kind) }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { throw PhotoError.exportVariantAmbiguous }
        }
        throw PhotoError.exportVariantUnavailable
    }
}

public struct PhotoExportArtifact: Equatable, Sendable {
    public let resourceKind: String
    public let contentType: String?
    public let bytes: Int
    public let networkAllowed: Bool

    public init(resourceKind: String, contentType: String?, bytes: Int, networkAllowed: Bool) {
        self.resourceKind = resourceKind
        self.contentType = contentType
        self.bytes = bytes
        self.networkAllowed = networkAllowed
    }
}

public protocol PhotoAssetExporting: Sendable {
    func export(
        localIdentifier: String,
        variant: PhotoExportVariant,
        destination: URL,
        allowNetwork: Bool
    ) async throws -> PhotoExportArtifact
}

public enum PhotoExportFileCoordinator {
    public static func prepare(outputURL: URL) throws -> URL {
        guard outputURL.isFileURL, !outputURL.path.isEmpty else { throw PhotoError.invalidOutput }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: outputURL.path) else { throw PhotoError.outputExists }
        let parent = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: parent.path) else {
            throw PhotoError.invalidOutput
        }
        return parent.appendingPathComponent(".mpia-export-\(UUID().uuidString).tmp")
    }

    public static func commit(temporaryURL: URL, outputURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: outputURL.path) else { throw PhotoError.outputExists }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch let error as PhotoError {
            throw error
        } catch {
            throw PhotoError.exportFailed
        }
    }
}

public struct PhotoKitAssetExporter: PhotoAssetExporting, @unchecked Sendable {
    public init() {}

    public func export(
        localIdentifier: String,
        variant: PhotoExportVariant,
        destination: URL,
        allowNetwork: Bool
    ) async throws -> PhotoExportArtifact {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            throw PhotoError.assetNotFound(localIdentifier)
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let descriptors = resources.enumerated().map { index, resource in
            PhotoExportResourceDescriptor(
                index: index,
                kind: Self.map(resource.type),
                contentType: resource.uniformTypeIdentifier
            )
        }
        let selected = try PhotoExportResourceSelector.select(descriptors, variant: variant)
        let temporaryURL = try PhotoExportFileCoordinator.prepare(outputURL: destination)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        do {
            try await write(resources[selected.index], to: temporaryURL, options: options)
        } catch {
            let nsError = error as NSError
            if nsError.domain == PHPhotosErrorDomain && nsError.code == 3164 {
                throw PhotoError.contentNotLocal
            }
            throw PhotoError.exportFailed
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard bytes > 0 else { throw PhotoError.exportFailed }
        try PhotoExportFileCoordinator.commit(temporaryURL: temporaryURL, outputURL: destination)
        return PhotoExportArtifact(
            resourceKind: selected.kind.rawValue,
            contentType: selected.contentType,
            bytes: bytes,
            networkAllowed: allowNetwork
        )
    }

    private func write(
        _ resource: PHAssetResource,
        to url: URL,
        options: PHAssetResourceRequestOptions
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private static func map(_ type: PHAssetResourceType) -> PhotoExportResourceKind {
        switch type {
        case .photo: .photo
        case .video: .video
        case .audio: .audio
        case .alternatePhoto: .alternatePhoto
        case .fullSizePhoto: .fullSizePhoto
        case .fullSizeVideo: .fullSizeVideo
        case .adjustmentData: .adjustmentData
        case .adjustmentBasePhoto: .adjustmentBasePhoto
        case .pairedVideo: .pairedVideo
        case .fullSizePairedVideo: .fullSizePairedVideo
        case .adjustmentBasePairedVideo: .adjustmentBasePairedVideo
        case .adjustmentBaseVideo: .adjustmentBaseVideo
        default: .other
        }
    }
}
