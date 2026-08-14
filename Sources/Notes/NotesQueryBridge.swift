import AppKit
import Foundation

public struct NotesNoteDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let accountScriptingID: String
    public let folderScriptingID: String
    public let title: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let passwordProtected: Bool
    public let shared: Bool

    public init(
        scriptingID: String,
        accountScriptingID: String,
        folderScriptingID: String,
        title: String,
        creationDate: Date?,
        modificationDate: Date?,
        passwordProtected: Bool,
        shared: Bool
    ) {
        self.scriptingID = scriptingID
        self.accountScriptingID = accountScriptingID
        self.folderScriptingID = folderScriptingID
        self.title = title
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.passwordProtected = passwordProtected
        self.shared = shared
    }
}

public struct NotesQuerySnapshot: Equatable, Sendable {
    public let notes: [NotesNoteDescriptor]
    public let complete: Bool

    public init(notes: [NotesNoteDescriptor], complete: Bool) {
        self.notes = notes
        self.complete = complete
    }
}

public protocol NotesQueryBridging: Sendable {
    func snapshot(maximumNotes: Int) throws -> NotesQuerySnapshot
}

public struct SystemNotesQueryBridge: NotesQueryBridging {
    public static let maximumNotes = 200
    public static let timeoutSeconds = 5

    public init() {}

    public func snapshot(maximumNotes: Int) throws -> NotesQuerySnapshot {
        guard (1...Self.maximumNotes).contains(maximumNotes) else {
            throw NotesMetadataBridgeError.executionFailed
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else {
            throw NotesMetadataBridgeError.targetNotRunning
        }
        return try Self.parseSnapshot(execute(Self.snapshotScript(
            maximumNotes: maximumNotes,
            timeoutSeconds: Self.timeoutSeconds
        )))
    }

    public static func snapshotScript(maximumNotes: Int, timeoutSeconds: Int) -> String {
        """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Notes"
                set noteRows to {}
                set noteCounter to 0
                set noteLimitReached to false
                set depthLimitReached to false
                repeat with accountItem in every account
                    set accountKey to (id of accountItem) as text
                    set noteResult to my collectNotes(every folder of accountItem, accountKey, 0, noteRows, noteCounter, \(maximumNotes), 16)
                    set noteRows to item 1 of noteResult
                    set noteCounter to item 2 of noteResult
                    if item 3 of noteResult then set noteLimitReached to true
                    if item 4 of noteResult then set depthLimitReached to true
                end repeat
                return {noteRows, noteLimitReached, depthLimitReached}
            end tell
        end timeout

        on collectNotes(folderItems, accountKey, folderDepth, noteRows, noteCounter, maximumNotes, maximumDepth)
            using terms from application "Notes"
                tell application id "com.apple.Notes"
                    set noteLimitReached to false
                    set depthLimitReached to false
                    repeat with folderItem in folderItems
                        if noteCounter is greater than or equal to maximumNotes then
                            set noteLimitReached to true
                        else
                            set folderKey to (id of folderItem) as text
                            set noteItems to notes of folderItem
                            set noteCount to count of noteItems
                            repeat with noteIndex from 1 to noteCount
                                if noteCounter is greater than or equal to maximumNotes then
                                    set noteLimitReached to true
                                else
                                    set noteCounter to noteCounter + 1
                                    set noteItem to item noteIndex of noteItems
                                    set noteKey to (id of noteItem) as text
                                    set titleValue to ""
                                    set creationValue to missing value
                                    set modificationValue to missing value
                                    set protectedValue to false
                                    set sharedValue to false
                                    try
                                        set titleValue to (name of noteItem) as text
                                    end try
                                    try
                                        set creationValue to creation date of noteItem
                                    end try
                                    try
                                        set modificationValue to modification date of noteItem
                                    end try
                                    try
                                        set protectedValue to password protected of noteItem
                                    end try
                                    try
                                        set sharedValue to shared of noteItem
                                    end try
                                    copy {noteKey, accountKey, folderKey, titleValue, creationValue, modificationValue, protectedValue, sharedValue} to end of noteRows
                                end if
                            end repeat
                            set childFolders to every folder of folderItem
                            if (count of childFolders) is greater than 0 then
                                if folderDepth is greater than or equal to maximumDepth then
                                    set depthLimitReached to true
                                else
                                    set nestedResult to my collectNotes(childFolders, accountKey, folderDepth + 1, noteRows, noteCounter, maximumNotes, maximumDepth)
                                    set noteRows to item 1 of nestedResult
                                    set noteCounter to item 2 of nestedResult
                                    if item 3 of nestedResult then set noteLimitReached to true
                                    if item 4 of nestedResult then set depthLimitReached to true
                                end if
                            end if
                        end if
                    end repeat
                    return {noteRows, noteCounter, noteLimitReached, depthLimitReached}
                end tell
            end using terms from
        end collectNotes
        """
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) throws -> NotesQuerySnapshot {
        guard descriptor.numberOfItems == 3, let rows = descriptor.atIndex(1) else {
            throw NotesMetadataBridgeError.executionFailed
        }
        var notes: [NotesNoteDescriptor] = []
        for offset in 0..<rows.numberOfItems {
            guard let row = rows.atIndex(offset + 1), row.numberOfItems == 8,
                  let noteID = row.atIndex(1)?.stringValue, !noteID.isEmpty,
                  let accountID = row.atIndex(2)?.stringValue, !accountID.isEmpty,
                  let folderID = row.atIndex(3)?.stringValue, !folderID.isEmpty else { continue }
            notes.append(NotesNoteDescriptor(
                scriptingID: noteID,
                accountScriptingID: accountID,
                folderScriptingID: folderID,
                title: row.atIndex(4)?.stringValue ?? "",
                creationDate: row.atIndex(5)?.dateValue,
                modificationDate: row.atIndex(6)?.dateValue,
                passwordProtected: row.atIndex(7)?.booleanValue ?? false,
                shared: row.atIndex(8)?.booleanValue ?? false
            ))
        }
        return NotesQuerySnapshot(
            notes: notes,
            complete: !(
                (descriptor.atIndex(2)?.booleanValue ?? false)
                    || (descriptor.atIndex(3)?.booleanValue ?? false)
            )
        )
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
