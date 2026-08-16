import Foundation

/// One message in a `messages recent` page. Participant handles, raw local
/// database IDs, and account identifiers are never exposed; only opaque IDs
/// cross the contract.
public struct MessagesRecentItem: Codable, Equatable, Sendable {
    public let id: String
    public let service: String
    public let isFromMe: Bool
    public let sentAt: String
    public let conversationId: String
    public let text: String?
}

public struct MessagesRecentResult: Codable, Equatable, Sendable {
    public let items: [MessagesRecentItem]
    public let nextCursor: String?
    public let complete: Bool
    public let truncated: Bool
    public let limitations: [String]
}

public struct MessagesPermissionStatus: Codable, Equatable, Sendable {
    public let readable: Bool
    public let fullDiskAccess: Bool
    public let schemaFingerprint: String?
    public let limitations: [String]
}

public enum MessagesError: Error, Equatable, CustomStringConvertible, Sendable {
    case databaseUnavailable
    case queryFailed
    case invalidOpaqueID
    case invalidLimit
    case storeNotFound
    case fullDiskAccessRequired
    case schemaUnsupported
    case invalidArgument(String)

    public var machineCode: String {
        switch self {
        case .fullDiskAccessRequired: "MESSAGES_FULL_DISK_ACCESS_REQUIRED"
        case .schemaUnsupported: "MESSAGES_SCHEMA_UNSUPPORTED"
        default: "MESSAGES_ERROR"
        }
    }

    public var description: String {
        switch self {
        case .databaseUnavailable: "Messages database is unavailable for read-only access."
        case .queryFailed: "Messages metadata query failed."
        case .invalidOpaqueID: "Messages selector or cursor is invalid or stale."
        case .invalidLimit: "Messages query limit must be between 1 and 200."
        case .storeNotFound: "Messages store was not found. Sign in to Messages and retry."
        case .fullDiskAccessRequired: "Messages store is not readable. Grant Full Disk Access to the responsible process."
        case .schemaUnsupported: "Messages store schema is unsupported; the SQLite fast path is disabled."
        case .invalidArgument(let detail): "Invalid argument: \(detail)"
        }
    }
}
