public protocol NotesAutomationProbing: Sendable {
    func status(requestConsent: Bool) -> NotesAutomationStatus
}

public enum NotesAutomationStatus: String, Codable, Equatable, Sendable {
    case available
    case denied
    case requiresConsent
    case targetNotRunning
    case targetUnavailable
    case unknown

    public var readable: Bool { self == .available }
    public var complete: Bool { self == .available }
}
