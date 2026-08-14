public protocol ShortcutsAutomationProbing: Sendable {
    func status(requestConsent: Bool) -> ShortcutsAutomationStatus
}

public enum ShortcutsAutomationStatus: String, Codable, Equatable, Sendable {
    case available
    case denied
    case requiresConsent
    case targetNotRunning
    case targetUnavailable
    case unknown

    public var readable: Bool { self == .available }
    public var complete: Bool { self == .available }
}
