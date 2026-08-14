import AppKit
import Foundation

public struct NotesFolderMutationDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let accountScriptingID: String
    public let parentScriptingID: String?
    public let name: String
    public let shared: Bool
    public let directNoteCount: Int
    public let directChildFolderCount: Int
    public init(scriptingID: String, accountScriptingID: String, parentScriptingID: String?, name: String, shared: Bool, directNoteCount: Int = 0, directChildFolderCount: Int = 0) {
        self.scriptingID = scriptingID
        self.accountScriptingID = accountScriptingID
        self.parentScriptingID = parentScriptingID
        self.name = name
        self.shared = shared
        self.directNoteCount = directNoteCount
        self.directChildFolderCount = directChildFolderCount
    }
}

public protocol NotesFolderMutationBridging: Sendable {
    func create(accountScriptingID: String, parentFolderScriptingID: String?, name: String) throws -> NotesFolderMutationDescriptor
    func rename(folderScriptingID: String, name: String) throws -> NotesFolderMutationDescriptor
    func move(folderScriptingID: String, accountScriptingID: String, destinationParentFolderScriptingID: String?) throws -> NotesFolderMutationDescriptor
    func read(folderScriptingID: String) throws -> NotesFolderMutationDescriptor
}

public struct SystemNotesFolderMutationBridge: NotesFolderMutationBridging {
    public static let timeoutSeconds = 5
    public init() {}

    public func create(accountScriptingID: String, parentFolderScriptingID: String?, name: String) throws -> NotesFolderMutationDescriptor {
        try executeAndParse(Self.createScript(accountScriptingID: accountScriptingID, parentFolderScriptingID: parentFolderScriptingID, name: name, timeoutSeconds: Self.timeoutSeconds))
    }
    public func rename(folderScriptingID: String, name: String) throws -> NotesFolderMutationDescriptor {
        try executeAndParse(Self.renameScript(folderScriptingID: folderScriptingID, name: name, timeoutSeconds: Self.timeoutSeconds))
    }
    public func move(folderScriptingID: String, accountScriptingID: String, destinationParentFolderScriptingID: String?) throws -> NotesFolderMutationDescriptor {
        try executeAndParse(Self.moveScript(folderScriptingID: folderScriptingID, accountScriptingID: accountScriptingID, destinationParentFolderScriptingID: destinationParentFolderScriptingID, timeoutSeconds: Self.timeoutSeconds))
    }
    public func read(folderScriptingID: String) throws -> NotesFolderMutationDescriptor {
        try executeAndParse(Self.readScript(folderScriptingID: folderScriptingID, timeoutSeconds: Self.timeoutSeconds))
    }

    public static func createScript(accountScriptingID: String, parentFolderScriptingID: String?, name: String, timeoutSeconds: Int) -> String {
        let target: String
        if let parentFolderScriptingID {
            target = "set parentFolderItem to folder id \"\(escape(parentFolderScriptingID))\"\n                set folderItem to make new folder at parentFolderItem with properties {name:\"\(escape(name))\"}"
        } else {
            target = "set folderItem to make new folder at accountItem with properties {name:\"\(escape(name))\"}"
        }
        return scriptPrelude(timeoutSeconds) + """
                set accountItem to account id "\(escape(accountScriptingID))"
                \(target)
                return my describeFolder(folderItem)
            end tell
        end timeout
        """ + descriptorHandler
    }

    public static func renameScript(folderScriptingID: String, name: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set folderItem to folder id "\(escape(folderScriptingID))"
                set name of folderItem to "\(escape(name))"
                return my describeFolder(folderItem)
            end tell
        end timeout
        """ + descriptorHandler
    }

    public static func moveScript(folderScriptingID: String, accountScriptingID: String, destinationParentFolderScriptingID: String?, timeoutSeconds: Int) -> String {
        let target: String
        if let destinationParentFolderScriptingID {
            target = "set destinationItem to folder id \"\(escape(destinationParentFolderScriptingID))\"\n                move folderItem to destinationItem"
        } else {
            target = "move folderItem to accountItem"
        }
        return scriptPrelude(timeoutSeconds) + """
                set folderItem to folder id "\(escape(folderScriptingID))"
                set accountItem to account id "\(escape(accountScriptingID))"
                \(target)
                return my describeFolder(folderItem)
            end tell
        end timeout
        """ + descriptorHandler
    }

    public static func readScript(folderScriptingID: String, timeoutSeconds: Int) -> String {
        scriptPrelude(timeoutSeconds) + """
                set folderItem to folder id "\(escape(folderScriptingID))"
                return my describeFolder(folderItem)
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

        on describeFolder(folderItem)
            using terms from application "Notes"
                tell application id "com.apple.Notes"
                    set parentItem to container of folderItem
                    set parentKey to ""
                    set accountItem to parentItem
                    if class of parentItem is folder then
                        set parentKey to (id of parentItem) as text
                        repeat while class of accountItem is folder
                            set accountItem to container of accountItem
                        end repeat
                    end if
                    return {(id of folderItem) as text, (id of accountItem) as text, parentKey, (name of folderItem) as text, shared of folderItem, (count of notes of folderItem), (count of folders of folderItem)}
                end tell
            end using terms from
        end describeFolder
        """

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func executeAndParse(_ source: String) throws -> NotesFolderMutationDescriptor {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else {
            throw NotesMetadataBridgeError.targetNotRunning
        }
        notesAppleEventExecutionLock.lock(); defer { notesAppleEventExecutionLock.unlock() }
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
        guard result.numberOfItems == 7,
              let scriptingID = result.atIndex(1)?.stringValue, !scriptingID.isEmpty,
              let accountScriptingID = result.atIndex(2)?.stringValue, !accountScriptingID.isEmpty else {
            throw NotesMetadataBridgeError.executionFailed
        }
        let parent = result.atIndex(3)?.stringValue
        return NotesFolderMutationDescriptor(
            scriptingID: scriptingID,
            accountScriptingID: accountScriptingID,
            parentScriptingID: parent.flatMap { $0.isEmpty ? nil : $0 },
            name: result.atIndex(4)?.stringValue ?? "",
            shared: result.atIndex(5)?.booleanValue ?? false,
            directNoteCount: max(0, Int(result.atIndex(6)?.int32Value ?? 0)),
            directChildFolderCount: max(0, Int(result.atIndex(7)?.int32Value ?? 0))
        )
    }

}
