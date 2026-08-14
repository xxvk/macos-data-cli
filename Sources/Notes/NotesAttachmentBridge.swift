import AppKit
import Foundation

public struct NotesAttachmentDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let name: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let contentIdentifier: String?
    public let url: String?
    public let shared: Bool

    public init(scriptingID: String, name: String, creationDate: Date?, modificationDate: Date?, contentIdentifier: String?, url: String?, shared: Bool) {
        self.scriptingID = scriptingID
        self.name = name
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.contentIdentifier = contentIdentifier
        self.url = url
        self.shared = shared
    }
}

public struct NotesAttachmentSnapshot: Equatable, Sendable {
    public let attachments: [NotesAttachmentDescriptor]
    public let complete: Bool

    public init(attachments: [NotesAttachmentDescriptor], complete: Bool) {
        self.attachments = attachments
        self.complete = complete
    }
}

public protocol NotesAttachmentBridging: Sendable {
    func snapshot(scriptingID: String, maximumAttachments: Int) throws -> NotesAttachmentSnapshot
}

public struct SystemNotesAttachmentBridge: NotesAttachmentBridging {
    public static let maximumAttachments = 100
    public static let timeoutSeconds = 5

    public init() {}

    public func snapshot(scriptingID: String, maximumAttachments: Int) throws -> NotesAttachmentSnapshot {
        guard (1...Self.maximumAttachments).contains(maximumAttachments) else { throw NotesMetadataBridgeError.executionFailed }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else {
            throw NotesMetadataBridgeError.targetNotRunning
        }
        return try Self.parseSnapshot(execute(Self.snapshotScript(
            scriptingID: scriptingID,
            maximumAttachments: maximumAttachments,
            timeoutSeconds: Self.timeoutSeconds
        )))
    }

    public static func snapshotScript(scriptingID: String, maximumAttachments: Int, timeoutSeconds: Int) -> String {
        let escapedID = scriptingID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Notes"
                set noteItem to note id "\(escapedID)"
                set attachmentRows to {}
                set attachmentCounter to 0
                set attachmentLimitReached to false
                repeat with attachmentItem in every attachment of noteItem
                    if attachmentCounter is greater than or equal to \(maximumAttachments) then
                        set attachmentLimitReached to true
                    else
                        set attachmentCounter to attachmentCounter + 1
                        set attachmentKey to (id of attachmentItem) as text
                        set nameValue to ""
                        set creationValue to missing value
                        set modificationValue to missing value
                        set contentIdentifierValue to ""
                        set urlValue to ""
                        set sharedValue to false
                        try
                            set nameValue to (name of attachmentItem) as text
                        end try
                        try
                            set creationValue to creation date of attachmentItem
                        end try
                        try
                            set modificationValue to modification date of attachmentItem
                        end try
                        try
                            set contentIdentifierValue to (content identifier of attachmentItem) as text
                        end try
                        try
                            set urlValue to (URL of attachmentItem) as text
                        end try
                        try
                            set sharedValue to shared of attachmentItem
                        end try
                        copy {attachmentKey, nameValue, creationValue, modificationValue, contentIdentifierValue, urlValue, sharedValue} to end of attachmentRows
                    end if
                end repeat
                return {attachmentRows, attachmentLimitReached}
            end tell
        end timeout
        """
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) throws -> NotesAttachmentSnapshot {
        guard descriptor.numberOfItems == 2, let rows = descriptor.atIndex(1) else { throw NotesMetadataBridgeError.executionFailed }
        var values: [NotesAttachmentDescriptor] = []
        for offset in 0..<rows.numberOfItems {
            guard let row = rows.atIndex(offset + 1), row.numberOfItems == 7,
                  let id = row.atIndex(1)?.stringValue, !id.isEmpty else { continue }
            let contentIdentifier = row.atIndex(5)?.stringValue
            let url = row.atIndex(6)?.stringValue
            values.append(NotesAttachmentDescriptor(
                scriptingID: id,
                name: row.atIndex(2)?.stringValue ?? "",
                creationDate: row.atIndex(3)?.dateValue,
                modificationDate: row.atIndex(4)?.dateValue,
                contentIdentifier: contentIdentifier.flatMap { $0.isEmpty ? nil : $0 },
                url: url.flatMap { $0.isEmpty ? nil : $0 },
                shared: row.atIndex(7)?.booleanValue ?? false
            ))
        }
        return NotesAttachmentSnapshot(attachments: values, complete: !(descriptor.atIndex(2)?.booleanValue ?? false))
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        notesAppleEventExecutionLock.lock()
        defer { notesAppleEventExecutionLock.unlock() }
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
