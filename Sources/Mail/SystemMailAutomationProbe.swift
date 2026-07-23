import CoreServices
import Foundation

public struct SystemMailAutomationProbe: MailAutomationProbing {
    public init() {}

    public func status() -> MailAutomationStatus {
        let bundleID = Data("com.apple.mail".utf8)
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
            false
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
