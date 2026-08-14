import CryptoKit
import Foundation

protocol SafariBookmarksSnapshotReading: Sendable {
    func snapshot() throws -> SafariBookmarksSnapshot
}

struct SystemSafariBookmarksSnapshotReader: SafariBookmarksSnapshotReading {
    static let maximumBytes = 32 * 1024 * 1024
    let fileURL: URL

    init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")) {
        self.fileURL = fileURL
    }

    func snapshot() throws -> SafariBookmarksSnapshot {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else { throw SafariError.bookmarksUnavailable }
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { throw SafariError.readFailed }
        guard (values.fileSize ?? 0) <= Self.maximumBytes else { throw SafariError.fileTooLarge }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard data.count <= Self.maximumBytes else { throw SafariError.fileTooLarge }
            return try SafariBookmarksParser.parse(data: data)
        } catch let error as SafariError { throw error }
        catch { throw SafariError.readFailed }
    }
}

enum SafariBookmarksParser {
    static let maximumNodes = 50_000
    static let maximumDepth = 64

    static func parse(data: Data) throws -> SafariBookmarksSnapshot {
        guard data.count <= SystemSafariBookmarksSnapshotReader.maximumBytes else { throw SafariError.fileTooLarge }
        let object: Any
        do { object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        catch { throw SafariError.schemaUnsupported }
        guard let root = object as? [String: Any],
              root["WebBookmarkFileVersion"] is NSNumber,
              root["WebBookmarkType"] as? String == "WebBookmarkTypeList",
              root["Children"] is [[String: Any]] else { throw SafariError.schemaUnsupported }

        var readingListContainers = 0
        var nodeCount = 0
        try inspect(root, depth: 0, nodeCount: &nodeCount, readingListContainers: &readingListContainers)
        guard readingListContainers <= 1 else { throw SafariError.schemaUnsupported }

        var bookmarks: [SafariBookmarkPayload] = []
        var readingList: [SafariReadingListItemPayload] = []
        for child in root["Children"] as! [[String: Any]] {
            try parseNode(child, parentID: nil, depth: 1, bookmarks: &bookmarks, readingList: &readingList)
        }
        return SafariBookmarksSnapshot(
            fingerprint: digest(data),
            bookmarks: bookmarks,
            readingList: readingList
        )
    }

    private static func inspect(_ node: [String: Any], depth: Int, nodeCount: inout Int, readingListContainers: inout Int) throws {
        guard depth <= maximumDepth else { throw SafariError.schemaUnsupported }
        nodeCount += 1
        guard nodeCount <= maximumNodes else { throw SafariError.schemaUnsupported }
        if node["Title"] as? String == "com.apple.ReadingList" { readingListContainers += 1 }
        if let children = node["Children"] {
            guard let dictionaries = children as? [[String: Any]] else { throw SafariError.schemaUnsupported }
            for child in dictionaries { try inspect(child, depth: depth + 1, nodeCount: &nodeCount, readingListContainers: &readingListContainers) }
        }
    }

    private static func parseNode(
        _ node: [String: Any],
        parentID: String?,
        depth: Int,
        bookmarks: inout [SafariBookmarkPayload],
        readingList: inout [SafariReadingListItemPayload]
    ) throws {
        guard depth <= maximumDepth,
              let type = node["WebBookmarkType"] as? String,
              let uuid = node["WebBookmarkUUID"] as? String, !uuid.isEmpty else { throw SafariError.schemaUnsupported }
        let children = node["Children"] as? [[String: Any]] ?? []

        if node["Title"] as? String == "com.apple.ReadingList" {
            for child in children { readingList.append(try parseReadingListItem(child)) }
            return
        }

        switch type {
        case "WebBookmarkTypeProxy":
            return
        case "WebBookmarkTypeList":
            let id = SafariOpaqueID.folder(uuid: uuid)
            let title = node["Title"] as? String ?? ""
            bookmarks.append(.init(id: id, parentID: parentID, kind: .folder, title: title, url: nil, childCount: children.count, dateAdded: node["dateAdded"] as? Date))
            for child in children { try parseNode(child, parentID: id, depth: depth + 1, bookmarks: &bookmarks, readingList: &readingList) }
        case "WebBookmarkTypeLeaf":
            guard let url = node["URLString"] as? String, URL(string: url) != nil else { throw SafariError.schemaUnsupported }
            bookmarks.append(.init(
                id: SafariOpaqueID.bookmark(uuid: uuid),
                parentID: parentID,
                kind: .bookmark,
                title: title(node),
                url: url,
                childCount: 0,
                dateAdded: node["dateAdded"] as? Date
            ))
        default:
            throw SafariError.schemaUnsupported
        }
    }

    private static func parseReadingListItem(_ node: [String: Any]) throws -> SafariReadingListItemPayload {
        guard node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
              let uuid = node["WebBookmarkUUID"] as? String, !uuid.isEmpty,
              let rawURL = node["URLString"] as? String, URL(string: rawURL) != nil else { throw SafariError.schemaUnsupported }
        let metadata = node["ReadingList"] as? [String: Any]
        return .init(
            id: SafariOpaqueID.readingList(uuid: uuid),
            url: rawURL,
            title: title(node),
            previewText: metadata?["PreviewText"] as? String ?? node["previewText"] as? String,
            dateAdded: metadata?["DateAdded"] as? Date ?? node["dateAdded"] as? Date,
            lastViewedDate: metadata?["DateLastViewed"] as? Date
        )
    }

    private static func title(_ node: [String: Any]) -> String {
        if let title = node["Title"] as? String { return title }
        if let dictionary = node["URIDictionary"] as? [String: Any], let title = dictionary["title"] as? String { return title }
        if let metadata = node["ReadingListNonSync"] as? [String: Any], let title = metadata["Title"] as? String { return title }
        if let title = node["TopicTitle"] as? String { return title }
        return ""
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
