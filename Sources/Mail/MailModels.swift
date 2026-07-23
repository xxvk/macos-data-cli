import Foundation

public enum MailCacheState: String, Codable, Equatable, Sendable {
    case metadataOnly = "metadata_only"
    case partial
    case complete
    case unknown
}

public enum MailContentProjection: String, Codable, Equatable, Sendable {
    case metadata
    case text
    case raw
}

public struct MailAccountSummary: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let mailboxCount: Int
    public let totalCount: Int
    public let unreadCount: Int
}

public struct MailboxSummary: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let name: String
    public let totalCount: Int
    public let unreadCount: Int
}

public struct MailAccountListResult: Codable, Equatable, Sendable {
    public let backend: String
    public let accounts: [MailAccountSummary]
    public let limitations: [String]

    public init(accounts: [MailAccountSummary]) {
        self.backend = "sqlite"
        self.accounts = accounts
        self.limitations = []
    }

    public init(backend: String, accounts: [MailAccountSummary], limitations: [String]) {
        self.backend = backend
        self.accounts = accounts
        self.limitations = limitations
    }
}

public struct MailboxListResult: Codable, Equatable, Sendable {
    public let backend: String
    public let mailboxes: [MailboxSummary]
    public let limitations: [String]

    public init(mailboxes: [MailboxSummary]) {
        self.backend = "sqlite"
        self.mailboxes = mailboxes
        self.limitations = []
    }


    public init(backend: String, mailboxes: [MailboxSummary], limitations: [String]) {
        self.backend = backend
        self.mailboxes = mailboxes
        self.limitations = limitations
    }
}

public struct MailMessageMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let idScope: String
    public let messageID: String?
    public let accountID: String
    public let mailboxID: String
    public let subject: String
    public let sender: String
    public let sentAt: String?
    public let receivedAt: String?
    public let unread: Bool
    public let flagged: Bool
    public let hasAttachment: Bool
    public let sizeBytes: Int
    public let cacheState: String
}

public struct MailTextContent: Codable, Equatable, Sendable {
    public let text: String?
    public let truncated: Bool
}

public struct MailGetResult: Codable, Equatable, Sendable {
    public let backend: String
    public let cacheState: String
    public let message: MailMessageMetadata
    public let content: MailTextContent?
    public let elapsedMs: Double
    public let fallbackReason: String?
    public let incomplete: Bool
    public let limitations: [String]
}

public struct MailRevealResult: Codable, Equatable, Sendable {
    public let backend: String
    public let id: String
    public let revealed: Bool
    public let elapsedMs: Double
    public let limitations: [String]
}

public struct MailAttachmentVerificationResult: Codable, Equatable, Sendable {
    public let backend: String
    public let id: String
    public let cacheState: String
    public let sqliteCount: Int
    public let mimeCount: Int?
    public let matched: Bool
    public let elapsedMs: Double
    public let incomplete: Bool
    public let limitations: [String]
}

public struct MailAttachmentExportItem: Codable, Equatable, Sendable {
    public let filename: String
    public let path: String
    public let bytes: Int
    public let contentType: String
}

public struct MailAttachmentExportResult: Codable, Equatable, Sendable {
    public let backend: String
    public let id: String
    public let outputDirectory: String
    public let files: [MailAttachmentExportItem]
    public let incomplete: Bool
    public let limitations: [String]
}

public struct MailThreadSummary: Codable, Equatable, Sendable {
    public let id: String
    public let messageCount: Int
    public let latestReceivedAt: String?
}

public struct MailThreadListResult: Codable, Equatable, Sendable {
    public let backend: String
    public let items: [MailThreadSummary]
    public let limit: Int
    public let truncated: Bool
    public let complete: Bool
    public let limitations: [String]
}

public struct MailRawMessage: Equatable, Sendable {
    public let data: Data
    public let cacheState: String
    public let message: MailMessageMetadata
    public let incomplete: Bool
    public let limitations: [String]
}

public struct MailRawWriteResult: Codable, Equatable, Sendable {
    public let backend: String
    public let cacheState: String
    public let id: String
    public let output: String
    public let bytesWritten: Int
    public let fallbackReason: String?
    public let incomplete: Bool
    public let limitations: [String]

    public init(
        backend: String,
        cacheState: String,
        id: String,
        output: String,
        bytesWritten: Int,
        fallbackReason: String?,
        incomplete: Bool,
        limitations: [String]
    ) {
        self.backend = backend
        self.cacheState = cacheState
        self.id = id
        self.output = output
        self.bytesWritten = bytesWritten
        self.fallbackReason = fallbackReason
        self.incomplete = incomplete
        self.limitations = limitations
    }
}

public struct MailQueryResult: Codable, Equatable, Sendable {
    public let backend: String
    public let cacheState: String
    public let messages: [MailMessageMetadata]
    /// Canonical cross-adapter page field. `messages` remains for 0.2 clients.
    public let items: [MailMessageMetadata]
    public let truncated: Bool
    public let nextCursor: String?
    public let elapsedMs: Double
    public let fallbackReason: String?
    public let incomplete: Bool
    public let limitations: [String]

    public init(
        backend: String,
        cacheState: String,
        messages: [MailMessageMetadata],
        truncated: Bool,
        nextCursor: String?,
        elapsedMs: Double,
        fallbackReason: String?,
        incomplete: Bool,
        limitations: [String]
    ) {
        self.backend = backend
        self.cacheState = cacheState
        self.messages = messages
        self.items = messages
        self.truncated = truncated
        self.nextCursor = nextCursor
        self.elapsedMs = elapsedMs
        self.fallbackReason = fallbackReason
        self.incomplete = incomplete
        self.limitations = limitations
    }
}

public struct MailTextSearchResult: Codable, Equatable, Sendable {
    public let backend: String
    public let items: [MailMessageMetadata]
    public let text: String
    public let scanned: Int
    public let limit: Int
    public let truncated: Bool
    public let complete: Bool
    public let elapsedMs: Double
    public let limitations: [String]
}

public struct MailQuery: Equatable, Sendable {
    public var accountID: String?
    public var mailboxID: String?
    public var from: String?
    public var to: String?
    public var subject: String?
    public var receivedAfter: Date?
    public var receivedBefore: Date?
    public var unread: Bool?
    public var flagged: Bool?
    public var hasAttachment: Bool?
    public var limit: Int
    public var cursor: String?

    public init(
        accountID: String? = nil,
        mailboxID: String? = nil,
        from: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        receivedAfter: Date? = nil,
        receivedBefore: Date? = nil,
        unread: Bool? = nil,
        flagged: Bool? = nil,
        hasAttachment: Bool? = nil,
        limit: Int = 50,
        cursor: String? = nil
    ) {
        self.accountID = accountID
        self.mailboxID = mailboxID
        self.from = from
        self.to = to
        self.subject = subject
        self.receivedAfter = receivedAfter
        self.receivedBefore = receivedBefore
        self.unread = unread
        self.flagged = flagged
        self.hasAttachment = hasAttachment
        self.limit = limit
        self.cursor = cursor
    }
}

public enum MailStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case databaseUnavailable
    case queryFailed
    case invalidOpaqueID
    case accountNotFound
    case invalidLimit
    case mailStoreNotFound
    case fullDiskAccessRequired
    case schemaUnsupported
    case staleLocalID
    case contentNotCached
    case emlxMalformed
    case contentTooLarge
    case contentReadTimedOut
    case outputAlreadyExists
    case outputFailed
    case automationDenied
    case mailAppNotRunning
    case mailAppTimedOut
    case mailAppMessageNotFound
    case mailAppCircuitOpen
    case mailAppExecutionFailed
    case invalidArgument(String)

    public var machineCode: String {
        switch self {
        case .automationDenied: "MAIL_AUTOMATION_DENIED"
        case .mailAppNotRunning: "MAIL_APP_NOT_RUNNING"
        case .mailAppTimedOut: "MAIL_APP_TIMEOUT"
        case .mailAppMessageNotFound: "MAIL_APP_MESSAGE_NOT_FOUND"
        case .mailAppCircuitOpen: "MAIL_APP_CIRCUIT_OPEN"
        case .fullDiskAccessRequired: "MAIL_FULL_DISK_ACCESS_REQUIRED"
        case .schemaUnsupported: "MAIL_SCHEMA_UNSUPPORTED"
        default: "MAIL_ERROR"
        }
    }

    public var description: String {
        switch self {
        case .databaseUnavailable: "Mail database is unavailable for read-only access."
        case .queryFailed: "Mail metadata query failed."
        case .invalidOpaqueID: "Mail selector or cursor is invalid or stale."
        case .accountNotFound: "Mail account was not found for the supplied opaque ID."
        case .invalidLimit: "Mail query limit must be between 1 and 200."
        case .mailStoreNotFound: "Mail store was not found. Configure Mail.app and retry."
        case .fullDiskAccessRequired: "Mail store is not readable. Grant Full Disk Access to the responsible process."
        case .schemaUnsupported: "Mail store schema is unsupported; the SQLite fast path is disabled."
        case .staleLocalID: "Mail message ID is stale or no longer resolves to the same local message."
        case .contentNotCached: "Mail message content is not cached locally and exact raw export cannot fall back to Mail.app."
        case .emlxMalformed: "Cached Mail message content has an invalid EMLX container or MIME structure."
        case .contentTooLarge: "Cached Mail message content exceeds the safe read limit."
        case .contentReadTimedOut: "Cached Mail message content exceeded the read deadline."
        case .outputAlreadyExists: "Raw output target already exists; choose a new file."
        case .outputFailed: "Raw Mail output could not be written."
        case .automationDenied: "Mail.app Automation permission is denied for the responsible process."
        case .mailAppNotRunning: "Mail.app is not running; ordinary reads do not launch it automatically."
        case .mailAppTimedOut: "The targeted Mail.app Apple Event timed out."
        case .mailAppMessageNotFound: "Mail.app could not resolve the selected local message."
        case .mailAppCircuitOpen: "Mail.app fallback is temporarily disabled after a timeout."
        case .mailAppExecutionFailed: "The targeted Mail.app Apple Event failed."
        case .invalidArgument(let message): message
        }
    }
}
