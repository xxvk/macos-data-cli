import AppKit
import Core
import Foundation

public struct NotesMutationDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let accountScriptingID: String
    public let folderScriptingID: String
    public let title: String
    public let html: String
    public let plaintext: String
    public let modificationDate: Date?
    public let passwordProtected: Bool
    public let shared: Bool
    public init(scriptingID: String, accountScriptingID: String, folderScriptingID: String, title: String, html: String, plaintext: String = "", modificationDate: Date?, passwordProtected: Bool, shared: Bool) {
        self.scriptingID = scriptingID; self.accountScriptingID = accountScriptingID; self.folderScriptingID = folderScriptingID; self.title = title; self.html = html; self.plaintext = plaintext; self.modificationDate = modificationDate; self.passwordProtected = passwordProtected; self.shared = shared
    }
}

public protocol NotesMutationBridging: Sendable {
    func create(accountScriptingID: String, folderScriptingID: String, html: String) throws -> NotesMutationDescriptor
    func rename(noteScriptingID: String, title: String) throws -> NotesMutationDescriptor
    func move(noteScriptingID: String, destinationFolderScriptingID: String) throws -> NotesMutationDescriptor
    func replaceBody(noteScriptingID: String, html: String) throws -> NotesMutationDescriptor
    func delete(noteScriptingID: String) throws -> NotesMutationDescriptor
    func read(noteScriptingID: String) throws -> NotesMutationDescriptor
}

public struct SystemNotesMutationBridge: NotesMutationBridging {
    public static let timeoutSeconds = 5
    public init() {}

    public func create(accountScriptingID: String, folderScriptingID: String, html: String) throws -> NotesMutationDescriptor {
        try executeAndParse(Self.createScript(accountScriptingID: accountScriptingID, folderScriptingID: folderScriptingID, html: html, timeoutSeconds: Self.timeoutSeconds))
    }
    public func rename(noteScriptingID: String, title: String) throws -> NotesMutationDescriptor {
        try executeAndParse(Self.renameScript(noteScriptingID: noteScriptingID, title: title, timeoutSeconds: Self.timeoutSeconds))
    }
    public func move(noteScriptingID: String, destinationFolderScriptingID: String) throws -> NotesMutationDescriptor {
        try executeAndParse(Self.moveScript(noteScriptingID: noteScriptingID, destinationFolderScriptingID: destinationFolderScriptingID, timeoutSeconds: Self.timeoutSeconds))
    }
    public func replaceBody(noteScriptingID: String, html: String) throws -> NotesMutationDescriptor {
        try executeAndParse(Self.replaceBodyScript(noteScriptingID: noteScriptingID, html: html, timeoutSeconds: Self.timeoutSeconds))
    }
    public func delete(noteScriptingID: String) throws -> NotesMutationDescriptor {
        try executeAndParse(Self.deleteScript(noteScriptingID: noteScriptingID, timeoutSeconds: Self.timeoutSeconds))
    }
    public func read(noteScriptingID: String) throws -> NotesMutationDescriptor {
        try executeAndParse(Self.readScript(noteScriptingID: noteScriptingID, timeoutSeconds: Self.timeoutSeconds))
    }

    public static func createScript(accountScriptingID: String, folderScriptingID: String, html: String, timeoutSeconds: Int) -> String {
        let account = escape(accountScriptingID), folder = escape(folderScriptingID), content = escape(html)
        return scriptPrelude(timeoutSeconds) + """
                set accountItem to account id "\(account)"
                set folderItem to folder id "\(folder)" of accountItem
                set noteItem to make new note at folderItem with properties {body:"\(content)"}
                return my describeNote(noteItem)
            end tell
        end timeout
        """ + descriptorHandler
    }
    public static func renameScript(noteScriptingID: String, title: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set noteItem to note id "\(escape(noteScriptingID))"
                set name of noteItem to "\(escape(title))"
                return my describeNote(noteItem)
            end tell
        end timeout
        """ + descriptorHandler
    }
    public static func moveScript(noteScriptingID: String, destinationFolderScriptingID: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set noteItem to note id "\(escape(noteScriptingID))"
                set folderItem to folder id "\(escape(destinationFolderScriptingID))"
                move noteItem to folderItem
                return my describeNote(noteItem)
            end tell
        end timeout
        """ + descriptorHandler
    }
    public static func replaceBodyScript(noteScriptingID: String, html: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set noteItem to note id "\(escape(noteScriptingID))"
                set body of noteItem to "\(escape(html))"
                return my describeNote(noteItem)
            end tell
        end timeout
        """ + descriptorHandler
    }
    public static func readScript(noteScriptingID: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set noteItem to note id "\(escape(noteScriptingID))"
                return my describeNote(noteItem)
            end tell
        end timeout
        """ + descriptorHandler
    }
    public static func deleteScript(noteScriptingID: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set noteItem to note id "\(escape(noteScriptingID))"
                delete noteItem
                return my describeNote(noteItem)
            end tell
        end timeout
        """ + descriptorHandler
    }

    private static func scriptPrelude(_ timeoutSeconds: Int) -> String {
        """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Notes"
        """ + "\n"
    }
    private static let descriptorHandler = """

        on describeNote(noteItem)
            using terms from application "Notes"
                tell application id "com.apple.Notes"
                    set folderItem to container of noteItem
                    set accountItem to container of folderItem
                    return {(id of noteItem) as text, (id of accountItem) as text, (id of folderItem) as text, (name of noteItem) as text, (body of noteItem) as text, (plaintext of noteItem) as text, modification date of noteItem, password protected of noteItem, shared of noteItem}
                end tell
            end using terms from
        end describeNote
        """
    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    private func executeAndParse(_ source: String) throws -> NotesMutationDescriptor {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else { throw NotesMetadataBridgeError.targetNotRunning }
        notesAppleEventExecutionLock.lock(); defer { notesAppleEventExecutionLock.unlock() }
        guard let script = NSAppleScript(source: source) else { throw NotesMetadataBridgeError.executionFailed }
        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details, let number = details[NSAppleScript.errorNumber] as? NSNumber {
            DiagnosticLogger.record(code: "NOTES_MUTATION_APPLE_EVENT_ERROR", message: "Notes mutation AppleScript failed with code \(number.intValue). No script values were logged.")
            switch number.intValue {
            case -1743: throw NotesMetadataBridgeError.automationDenied
            case -1712: throw NotesMetadataBridgeError.timedOut
            case -600, -609: throw NotesMetadataBridgeError.targetNotRunning
            default: throw NotesMetadataBridgeError.executionFailed
            }
        }
        guard result.numberOfItems == 9,
              let noteID = result.atIndex(1)?.stringValue, !noteID.isEmpty,
              let accountID = result.atIndex(2)?.stringValue, !accountID.isEmpty,
              let folderID = result.atIndex(3)?.stringValue, !folderID.isEmpty else { throw NotesMetadataBridgeError.executionFailed }
        return NotesMutationDescriptor(scriptingID: noteID, accountScriptingID: accountID, folderScriptingID: folderID, title: result.atIndex(4)?.stringValue ?? "", html: result.atIndex(5)?.stringValue ?? "", plaintext: result.atIndex(6)?.stringValue ?? "", modificationDate: result.atIndex(7)?.dateValue, passwordProtected: result.atIndex(8)?.booleanValue ?? false, shared: result.atIndex(9)?.booleanValue ?? false)
    }
}
