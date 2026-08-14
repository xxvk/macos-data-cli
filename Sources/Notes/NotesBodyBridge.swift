import AppKit
import Core
import Foundation

private let systemNotesBodyExecutionLock = NSLock()

public enum NotesBodyPolicy {
    public static let maximumBytes = 256 * 1024
}

public protocol NotesBodyBridging: Sendable {
    func read(scriptingID: String, format: NotesBodyFormat) throws -> String
}

public struct SystemNotesBodyBridge: NotesBodyBridging {
    public static let timeoutSeconds = 5

    public init() {}

    public func read(scriptingID: String, format: NotesBodyFormat) throws -> String {
        guard format != .none else { throw NotesMetadataBridgeError.executionFailed }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else {
            throw NotesMetadataBridgeError.targetNotRunning
        }
        return try execute(Self.readScript(
            scriptingID: scriptingID,
            format: format,
            timeoutSeconds: Self.timeoutSeconds
        )).stringValue ?? ""
    }

    public static func readScript(scriptingID: String, format: NotesBodyFormat, timeoutSeconds: Int) -> String {
        let escapedID = scriptingID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let projection = format == .plaintext ? "plaintext of noteItem" : "body of noteItem"
        return """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Notes"
                set noteItem to note id "\(escapedID)"
                return \(projection)
            end tell
        end timeout
        """
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        systemNotesBodyExecutionLock.lock()
        defer { systemNotesBodyExecutionLock.unlock() }
        guard let script = NSAppleScript(source: source) else { throw NotesMetadataBridgeError.executionFailed }
        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details, let number = details[NSAppleScript.errorNumber] as? NSNumber {
            switch number.intValue {
            case -1743: throw NotesMetadataBridgeError.automationDenied
            case -1712: throw NotesMetadataBridgeError.timedOut
            case -600, -609: throw NotesMetadataBridgeError.targetNotRunning
            default: throw NotesMetadataBridgeError.executionFailed
            }
        }
        return result
    }
}
