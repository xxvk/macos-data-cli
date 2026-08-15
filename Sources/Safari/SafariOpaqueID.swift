import CryptoKit
import Foundation

enum SafariOpaqueID {
    static func bookmark(uuid: String) -> String { value(prefix: "safaribookmark_", namespace: "bookmark", uuid: uuid) }
    static func folder(uuid: String) -> String { value(prefix: "safarifolder_", namespace: "folder", uuid: uuid) }
    static func readingList(uuid: String) -> String { value(prefix: "safarireading_", namespace: "reading-list", uuid: uuid) }

    static func isBookmarkOrFolder(_ value: String) -> Bool {
        hasValidDigest(value, prefix: "safaribookmark_") || hasValidDigest(value, prefix: "safarifolder_")
    }

    static func isReadingList(_ value: String) -> Bool { hasValidDigest(value, prefix: "safarireading_") }

    private static func value(prefix: String, namespace: String, uuid: String) -> String {
        prefix + SHA256.hash(data: Data("mpia-safari-v1:\(namespace):\(uuid)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func hasValidDigest(_ value: String, prefix: String) -> Bool {
        value.hasPrefix(prefix) && value.dropFirst(prefix.count).count == 64
            && value.dropFirst(prefix.count).allSatisfy { $0.isHexDigit }
    }
}
