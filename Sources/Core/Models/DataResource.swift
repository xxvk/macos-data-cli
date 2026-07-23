import Foundation

public enum DataResourceKind: String, Codable, Equatable, Sendable {
    case contactsContainer
    case mailAccount
    case calendarSource
}

public enum DataResourceProvider: String, Codable, Equatable, Sendable {
    case contacts
    case iCloud
    case mail
    case eventKit
}

public enum DataPermissionState: String, Codable, Equatable, Sendable {
    case available
    case denied
    case notDetermined
    case requiresConsent
    case unavailable
    case unknown
}

public struct DataResourceCapabilities: Codable, Equatable, Sendable {
    public let readable: Bool
    public let writable: Bool
    public let selected: Bool
    public let permission: DataPermissionState

    public init(
        readable: Bool,
        writable: Bool,
        selected: Bool,
        permission: DataPermissionState
    ) {
        self.readable = readable
        self.writable = writable
        self.selected = selected
        self.permission = permission
    }
}

public struct DataResource: Codable, Equatable, Sendable {
    public let id: String
    public let kind: DataResourceKind
    public let provider: DataResourceProvider
    public let displayName: String
    public let capabilities: DataResourceCapabilities

    public init(
        id: String,
        kind: DataResourceKind,
        provider: DataResourceProvider,
        displayName: String,
        capabilities: DataResourceCapabilities
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

public struct DataResourcesResult: Codable, Equatable, Sendable {
    public let resources: [DataResource]
    public let limitations: [String]

    public init(resources: [DataResource], limitations: [String] = []) {
        self.resources = resources
        self.limitations = limitations
    }
}
