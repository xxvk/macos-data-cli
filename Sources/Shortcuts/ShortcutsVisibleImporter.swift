import Core
import Foundation

public protocol ShortcutsVisibleImporting: Sendable {
    func importArtifact(at artifactURL: URL, expectedName: String, excludingShortcutIDs: Set<String>) throws -> ShortcutDescriptor?
    func replaceArtifact(at artifactURL: URL, expectedName: String, actionCount: Int, previousShortcutID: String, previousActionCount: Int) throws -> ShortcutDescriptor?
}

public struct SystemShortcutsVisibleImporter: ShortcutsVisibleImporting {
    private let metadataBridge: any ShortcutsMetadataBridging
    private let timeoutSeconds: TimeInterval
    private let pollInterval: TimeInterval

    public init(metadataBridge: any ShortcutsMetadataBridging = SystemShortcutsMetadataBridge(), timeoutSeconds: TimeInterval = 60, pollInterval: TimeInterval = 0.5) {
        self.metadataBridge = metadataBridge
        self.timeoutSeconds = timeoutSeconds
        self.pollInterval = pollInterval
    }

    public func importArtifact(at artifactURL: URL, expectedName: String, excludingShortcutIDs: Set<String>) throws -> ShortcutDescriptor? {
        try openArtifact(artifactURL)
        return try poll { snapshot in
            snapshot.shortcuts.filter {
                !excludingShortcutIDs.contains($0.scriptingID) && $0.name == expectedName
            }
        }
    }

    public func replaceArtifact(at artifactURL: URL, expectedName: String, actionCount: Int, previousShortcutID: String, previousActionCount: Int) throws -> ShortcutDescriptor? {
        guard actionCount != previousActionCount else { throw ShortcutsError.authorUpdateUnverifiable }
        try openArtifact(artifactURL)
        return try poll { snapshot in
            snapshot.shortcuts.filter { $0.name == expectedName && $0.actionCount == actionCount }
        }
    }

    private func openArtifact(_ artifactURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "/System/Applications/Shortcuts.app", artifactURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { throw ShortcutsError.authorImportFailed }
        guard process.terminationStatus == 0 else { throw ShortcutsError.authorImportFailed }
    }

    private func poll(matches: (ShortcutsMetadataSnapshot) -> [ShortcutDescriptor]) throws -> ShortcutDescriptor? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            let snapshot: ShortcutsMetadataSnapshot
            do {
                snapshot = try SystemShortcutsMetadataBridge.validate(metadataBridge.snapshot(maximumShortcuts: SystemShortcutsMetadataBridge.maximumShortcuts, maximumFolders: SystemShortcutsMetadataBridge.maximumFolders))
            } catch ShortcutsBridgeError.automationDenied { throw ShortcutsError.permissionDenied }
            catch ShortcutsBridgeError.timedOut { continue }
            catch { continue }
            guard snapshot.complete else { continue }
            let values = matches(snapshot)
            if values.count == 1 { return values[0] }
            if values.count > 1 { throw ShortcutsError.authorImportOutcomeUnknown }
        }
        return nil
    }
}
