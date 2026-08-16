import Foundation

/// One call in a `phone-calls recent` page. Counterparty numbers, names,
/// locations, carriers, and raw local database IDs are never exposed; only an
/// opaque ID crosses the contract.
public struct PhoneCallItem: Codable, Equatable, Sendable {
    public let id: String
    public let direction: String
    public let kind: String
    public let answered: Bool
    public let missed: Bool
    public let durationSeconds: Double
    public let at: String
}

public struct PhoneCallsRecentResult: Codable, Equatable, Sendable {
    public let items: [PhoneCallItem]
    public let nextCursor: String?
    public let complete: Bool
    public let truncated: Bool
    public let limitations: [String]
}

public struct PhoneCallsPermissionStatus: Codable, Equatable, Sendable {
    public let readable: Bool
    public let fullDiskAccess: Bool
    public let schemaFingerprint: String?
    public let limitations: [String]
}

public enum PhoneCallsError: Error, Equatable, CustomStringConvertible, Sendable {
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
        case .fullDiskAccessRequired: "PHONE_CALLS_FULL_DISK_ACCESS_REQUIRED"
        case .schemaUnsupported: "PHONE_CALLS_SCHEMA_UNSUPPORTED"
        default: "PHONE_CALLS_ERROR"
        }
    }

    public var description: String {
        switch self {
        case .databaseUnavailable: "Call History database is unavailable for read-only access."
        case .queryFailed: "Call History metadata query failed."
        case .invalidOpaqueID: "Phone call selector or cursor is invalid or stale."
        case .invalidLimit: "Phone call query limit must be between 1 and 200."
        case .storeNotFound: "Call History store was not found. Make a call and retry."
        case .fullDiskAccessRequired: "Call History store is not readable. Grant Full Disk Access to the responsible process."
        case .schemaUnsupported: "Call History store schema is unsupported; the SQLite fast path is disabled."
        case .invalidArgument(let detail): "Invalid argument: \(detail)"
        }
    }
}
