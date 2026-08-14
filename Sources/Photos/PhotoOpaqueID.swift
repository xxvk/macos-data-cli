import Core
import Foundation

public enum PhotoOpaqueKind: String, Codable, Equatable, Sendable {
    case album
    case asset
}

public struct PhotoOpaqueLocator: Codable, Equatable, Sendable {
    public let localIdentifier: String
    public let kind: PhotoOpaqueKind
}

public enum PhotoOpaqueID {
    private static let prefix = "photo_"

    public static func encode(localIdentifier: String, kind: PhotoOpaqueKind) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(PhotoOpaqueLocator(localIdentifier: localIdentifier, kind: kind))) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ value: String, expectedKind: PhotoOpaqueKind) throws -> PhotoOpaqueLocator {
        guard value.hasPrefix(prefix) else { throw PhotoError.invalidIdentifier }
        var encoded = String(value.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let locator = try? JSONDecoder().decode(PhotoOpaqueLocator.self, from: data),
              !locator.localIdentifier.isEmpty,
              locator.kind == expectedKind else {
            throw PhotoError.invalidIdentifier
        }
        return locator
    }
}
