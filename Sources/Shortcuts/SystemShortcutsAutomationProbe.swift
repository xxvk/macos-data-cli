import Core
import CoreServices
import Foundation

public struct SystemShortcutsAutomationProbe: ShortcutsAutomationProbing {
    public init() {}

    public func status(requestConsent: Bool) -> ShortcutsAutomationStatus {
        let bundleID = Data("com.apple.shortcuts.events".utf8)
        var target = AEAddressDesc()
        let createStatus = bundleID.withUnsafeBytes { bytes in
            AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, bytes.count, &target)
        }
        guard createStatus == noErr else { return .targetUnavailable }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            requestConsent
        )
        switch result {
        case noErr: return .available
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .requiresConsent
        case OSStatus(procNotFound): return .targetNotRunning
        default: return .unknown
        }
    }
}
