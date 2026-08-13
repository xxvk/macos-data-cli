public protocol CalendarAccessProviding: Sendable {
    var status: CalendarAccessStatus { get }
    func requestFullAccess() async throws -> Bool
}

public enum CalendarAccessStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
}
