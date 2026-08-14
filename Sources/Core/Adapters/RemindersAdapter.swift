public protocol ReminderAccessProviding: Sendable {
    var status: ReminderAccessStatus { get }
    func requestFullAccess() async throws -> Bool
}

public enum ReminderAccessStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
}
