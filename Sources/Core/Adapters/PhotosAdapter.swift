public protocol PhotoAccessProviding: Sendable {
    var status: PhotoAccessStatus { get }
    func requestReadWriteAccess() async -> PhotoAccessStatus
}

public enum PhotoAccessStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case limited
    case authorized

    public var canRead: Bool { self == .limited || self == .authorized }
    public var complete: Bool { self == .authorized }
}
