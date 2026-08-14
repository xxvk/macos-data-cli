import Core

public struct NotesPermissionService: Sendable {
    private let probe: any NotesAutomationProbing

    public init(probe: any NotesAutomationProbing = SystemNotesAutomationProbe()) {
        self.probe = probe
    }

    public func check(requestConsent: Bool = false) -> NotesPermissionResult {
        NotesPermissionResult(
            access: probe.status(requestConsent: requestConsent),
            requested: requestConsent
        )
    }
}
