public protocol ContactsAdapter: Sendable {
    func list() async throws -> [ContactPayload]
}

public protocol ContactsAccessProviding: Sendable {
    var status: ContactsAccessStatus { get }
    func requestAccess() async throws -> Bool
}

public enum ContactsAccessStatus: Equatable, Sendable {
    case notDetermined, restricted, denied, authorized, limited
}
