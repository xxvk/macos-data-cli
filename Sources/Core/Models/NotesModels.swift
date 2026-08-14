import Foundation

public struct NotesPermissionResult: Codable, Equatable, Sendable {
    public let access: NotesAutomationStatus
    public let readable: Bool
    public let complete: Bool
    public let requested: Bool

    public init(access: NotesAutomationStatus, requested: Bool) {
        self.access = access
        self.readable = access.readable
        self.complete = access.complete
        self.requested = requested
    }
}

public struct NotesAccountPayload: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public let folderCount: Int

    public init(id: String, name: String, isDefault: Bool, folderCount: Int) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.folderCount = folderCount
    }
}

public struct NotesAccountListResult: Codable, Equatable, Sendable {
    public let accounts: [NotesAccountPayload]
    public let complete: Bool

    public init(accounts: [NotesAccountPayload], complete: Bool) {
        self.accounts = accounts
        self.complete = complete
    }
}

public struct NotesFolderPayload: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let parentID: String?
    public let name: String
    public let shared: Bool
    public let depth: Int

    public init(id: String, accountID: String, parentID: String?, name: String, shared: Bool, depth: Int) {
        self.id = id
        self.accountID = accountID
        self.parentID = parentID
        self.name = name
        self.shared = shared
        self.depth = depth
    }
}

public struct NotesNotePayload: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let folderID: String
    public let title: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let passwordProtected: Bool
    public let shared: Bool

    public init(
        id: String,
        accountID: String,
        folderID: String,
        title: String,
        creationDate: Date?,
        modificationDate: Date?,
        passwordProtected: Bool,
        shared: Bool
    ) {
        self.id = id
        self.accountID = accountID
        self.folderID = folderID
        self.title = title
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.passwordProtected = passwordProtected
        self.shared = shared
    }
}

public struct NotesQuery: Equatable, Sendable {
    public let accountID: String?
    public let folderID: String?
    public let title: String?
    public let modifiedAfter: Date?
    public let limit: Int
    public let cursor: String?

    public init(
        accountID: String? = nil,
        folderID: String? = nil,
        title: String? = nil,
        modifiedAfter: Date? = nil,
        limit: Int = Pagination.defaultLimit,
        cursor: String? = nil
    ) {
        self.accountID = accountID
        self.folderID = folderID
        self.title = title
        self.modifiedAfter = modifiedAfter
        self.limit = limit
        self.cursor = cursor
    }
}

public enum NotesBodyFormat: String, Codable, Equatable, Sendable {
    case none
    case plaintext
    case html
}

public struct NotesGetResult: Codable, Equatable, Sendable {
    public let note: NotesNotePayload
    public let bodyFormat: NotesBodyFormat
    public let body: String?
    public let bodyBytes: Int?
    public let attachmentsIncluded: Bool
    public let attachments: [NotesAttachmentPayload]?
    public let attachmentsComplete: Bool?

    public init(
        note: NotesNotePayload,
        bodyFormat: NotesBodyFormat,
        body: String?,
        bodyBytes: Int?,
        attachmentsIncluded: Bool = false,
        attachments: [NotesAttachmentPayload]? = nil,
        attachmentsComplete: Bool? = nil
    ) {
        self.note = note
        self.bodyFormat = bodyFormat
        self.body = body
        self.bodyBytes = bodyBytes
        self.attachmentsIncluded = attachmentsIncluded
        self.attachments = attachments
        self.attachmentsComplete = attachmentsComplete
    }
}

public struct NotesAttachmentPayload: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let contentIdentifier: String?
    public let url: String?
    public let shared: Bool

    public init(id: String, name: String, creationDate: Date?, modificationDate: Date?, contentIdentifier: String?, url: String?, shared: Bool) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.contentIdentifier = contentIdentifier
        self.url = url
        self.shared = shared
    }
}
