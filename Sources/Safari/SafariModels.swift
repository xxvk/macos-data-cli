import Foundation

public enum SafariBookmarkKind: String, Codable, Equatable, Sendable {
    case bookmark
    case folder
}

public struct SafariBookmarkPayload: Codable, Equatable, Sendable {
    public let id: String
    public let parentID: String?
    public let kind: SafariBookmarkKind
    public let title: String
    public let url: String?
    public let childCount: Int
    public let dateAdded: Date?

    public init(id: String, parentID: String?, kind: SafariBookmarkKind, title: String, url: String?, childCount: Int, dateAdded: Date?) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.title = title
        self.url = url
        self.childCount = childCount
        self.dateAdded = dateAdded
    }
}

public struct SafariReadingListItemPayload: Codable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let previewText: String?
    public let dateAdded: Date?
    public let lastViewedDate: Date?
    public let isRead: Bool

    public init(id: String, url: String, title: String, previewText: String?, dateAdded: Date?, lastViewedDate: Date?) {
        self.id = id
        self.url = url
        self.title = title
        self.previewText = previewText
        self.dateAdded = dateAdded
        self.lastViewedDate = lastViewedDate
        self.isRead = lastViewedDate != nil
    }
}

public struct SafariBookmarkQuery: Equatable, Sendable {
    public var text: String?
    public var url: String?
    public var folderID: String?

    public init(text: String? = nil, url: String? = nil, folderID: String? = nil) {
        self.text = text
        self.url = url
        self.folderID = folderID
    }
}

public struct SafariReadingListQuery: Equatable, Sendable {
    public var text: String?
    public var url: String?
    public var read: Bool?

    public init(text: String? = nil, url: String? = nil, read: Bool? = nil) {
        self.text = text
        self.url = url
        self.read = read
    }
}

public enum SafariWriteVerification: String, Codable, Equatable, Sendable {
    case notApplied = "not_applied"
    case readbackConfirmed = "readback_confirmed"
    case saveAcceptedReadbackPending = "save_accepted_readback_pending"
}

public struct SafariReadingListAddResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let urlSHA256: String
    public let itemID: String?
    public let verification: SafariWriteVerification
    public let nextAction: String?

    public init(operation: String, dryRun: Bool, changed: Bool, urlSHA256: String, itemID: String?, verification: SafariWriteVerification, nextAction: String?) {
        self.operation = operation
        self.dryRun = dryRun
        self.changed = changed
        self.urlSHA256 = urlSHA256
        self.itemID = itemID
        self.verification = verification
        self.nextAction = nextAction
    }
}

public struct SafariReadingListAddInput: Equatable, Sendable {
    public static let maximumInputBytes = 16 * 1024
    public let url: URL
    public let title: String?
    public let previewText: String?

    public init(url: URL, title: String?, previewText: String?) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil,
              url.absoluteString.utf8.count <= 4_096,
              title?.count ?? 0 <= 500,
              previewText?.utf8.count ?? 0 <= 4_096 else {
            throw SafariError.invalidInput
        }
        self.url = url
        self.title = title
        self.previewText = previewText
    }

    public static func decode(_ data: Data) throws -> SafariReadingListAddInput {
        guard data.count <= maximumInputBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys).isSubset(of: ["url", "title", "previewText"]),
              let rawURL = dictionary["url"] as? String,
              let url = URL(string: rawURL),
              dictionary["title"] == nil || dictionary["title"] is String,
              dictionary["previewText"] == nil || dictionary["previewText"] is String else {
            throw SafariError.invalidInput
        }
        return try SafariReadingListAddInput(
            url: url,
            title: dictionary["title"] as? String,
            previewText: dictionary["previewText"] as? String
        )
    }
}

public enum SafariAutomationStatus: String, Codable, Equatable, Sendable {
    case available
    case denied
    case requiresConsent
    case targetNotRunning
    case targetUnavailable
    case unknown
}

public struct SafariPermissionResult: Codable, Equatable, Sendable {
    public let bookmarksReadable: Bool
    public let automation: SafariAutomationStatus
    public let readingListAddAvailable: Bool
    public let requested: Bool

    public init(bookmarksReadable: Bool, automation: SafariAutomationStatus, requested: Bool) {
        self.bookmarksReadable = bookmarksReadable
        self.automation = automation
        self.readingListAddAvailable = bookmarksReadable && automation == .available
        self.requested = requested
    }
}

struct SafariBookmarksSnapshot: Equatable, Sendable {
    let fingerprint: String
    let bookmarks: [SafariBookmarkPayload]
    let readingList: [SafariReadingListItemPayload]
}
