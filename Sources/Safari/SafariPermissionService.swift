import CoreServices
import Foundation

public protocol SafariAutomationProbing: Sendable {
    func status(requestConsent: Bool) -> SafariAutomationStatus
}

public struct SystemSafariAutomationProbe: SafariAutomationProbing {
    public init() {}

    public func status(requestConsent: Bool) -> SafariAutomationStatus {
        let bundleID = Data("com.apple.Safari".utf8)
        var target = AEAddressDesc()
        let createStatus = bundleID.withUnsafeBytes { bytes in
            AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, bytes.count, &target)
        }
        guard createStatus == noErr else { return .targetUnavailable }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), requestConsent)
        switch result {
        case noErr: return .available
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .requiresConsent
        case OSStatus(procNotFound): return .targetNotRunning
        default: return .unknown
        }
    }
}

public struct SafariPermissionService: Sendable {
    private let fileProbe: @Sendable () -> Bool
    private let automationProbe: any SafariAutomationProbing

    public init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        automationProbe: any SafariAutomationProbing = SystemSafariAutomationProbe()
    ) {
        self.fileProbe = { FileManager.default.isReadableFile(atPath: fileURL.path) }
        self.automationProbe = automationProbe
    }

    init(fileProbe: @escaping @Sendable () -> Bool, automationProbe: any SafariAutomationProbing) {
        self.fileProbe = fileProbe
        self.automationProbe = automationProbe
    }

    public func check(requestConsent: Bool = false) -> SafariPermissionResult {
        .init(bookmarksReadable: fileProbe(), automation: automationProbe.status(requestConsent: requestConsent), requested: requestConsent)
    }
}
