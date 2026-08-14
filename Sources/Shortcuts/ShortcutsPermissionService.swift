import Core

public struct ShortcutsPermissionService: Sendable {
    private let probe: any ShortcutsAutomationProbing

    public init(probe: any ShortcutsAutomationProbing = SystemShortcutsAutomationProbe()) {
        self.probe = probe
    }

    public func check(requestConsent: Bool = false) -> ShortcutsPermissionResult {
        ShortcutsPermissionResult(access: probe.status(requestConsent: requestConsent), requested: requestConsent)
    }
}
