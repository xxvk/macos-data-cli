import AppKit
import Foundation

public struct NotesAccountDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let name: String
    public let defaultFolderScriptingID: String?

    public init(scriptingID: String, name: String, defaultFolderScriptingID: String? = nil) {
        self.scriptingID = scriptingID
        self.name = name
        self.defaultFolderScriptingID = defaultFolderScriptingID
    }
}

public struct NotesFolderDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let accountScriptingID: String
    public let parentScriptingID: String?
    public let name: String
    public let shared: Bool
    public let depth: Int

    public init(
        scriptingID: String,
        accountScriptingID: String,
        parentScriptingID: String?,
        name: String,
        shared: Bool,
        depth: Int
    ) {
        self.scriptingID = scriptingID
        self.accountScriptingID = accountScriptingID
        self.parentScriptingID = parentScriptingID
        self.name = name
        self.shared = shared
        self.depth = depth
    }
}

public struct NotesMetadataSnapshot: Equatable, Sendable {
    public let accounts: [NotesAccountDescriptor]
    public let folders: [NotesFolderDescriptor]
    public let defaultAccountScriptingID: String?
    public let complete: Bool

    public init(
        accounts: [NotesAccountDescriptor],
        folders: [NotesFolderDescriptor],
        defaultAccountScriptingID: String?,
        complete: Bool
    ) {
        self.accounts = accounts
        self.folders = folders
        self.defaultAccountScriptingID = defaultAccountScriptingID
        self.complete = complete
    }
}

public enum NotesMetadataBridgeError: Error, Equatable, Sendable {
    case automationDenied
    case targetNotRunning
    case timedOut
    case executionFailed
}

public protocol NotesMetadataBridging: Sendable {
    func snapshot(maximumAccounts: Int, maximumFolders: Int) throws -> NotesMetadataSnapshot
}

public struct SystemNotesMetadataBridge: NotesMetadataBridging {
    public static let maximumAccounts = 32
    public static let maximumFolders = 200
    public static let maximumDepth = 16
    public static let timeoutSeconds = 5

    public init() {}

    public func snapshot(maximumAccounts: Int, maximumFolders: Int) throws -> NotesMetadataSnapshot {
        guard (1...Self.maximumAccounts).contains(maximumAccounts),
              (1...Self.maximumFolders).contains(maximumFolders) else {
            throw NotesMetadataBridgeError.executionFailed
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else {
            throw NotesMetadataBridgeError.targetNotRunning
        }
        let source = Self.snapshotScript(
            maximumAccounts: maximumAccounts,
            maximumFolders: maximumFolders,
            maximumDepth: Self.maximumDepth,
            timeoutSeconds: Self.timeoutSeconds
        )
        return try Self.parseSnapshot(execute(source))
    }

    public static func snapshotScript(
        maximumAccounts: Int,
        maximumFolders: Int,
        maximumDepth: Int,
        timeoutSeconds: Int
    ) -> String {
        """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Notes"
                set accountRows to {}
                set folderRows to {}
                set accountCounter to 0
                set folderCounter to 0
                set accountLimitReached to false
                set folderLimitReached to false
                set depthLimitReached to false
                set defaultAccountKey to ""
                try
                    set defaultAccountKey to (id of default account) as text
                end try
                repeat with accountItem in every account
                    if accountCounter is greater than or equal to \(maximumAccounts) then
                        set accountLimitReached to true
                    else
                        set accountCounter to accountCounter + 1
                        set accountKey to (id of accountItem) as text
                        set accountName to (name of accountItem) as text
                        set defaultFolderKey to ""
                        try
                            set defaultFolderKey to (id of default folder of accountItem) as text
                        end try
                        copy {accountKey, accountName, defaultFolderKey} to end of accountRows
                        set rootFolders to {}
                        repeat with candidateFolder in every folder of accountItem
                            set containerKey to ""
                            try
                                set containerKey to (id of container of candidateFolder) as text
                            end try
                            if containerKey is accountKey then copy contents of candidateFolder to end of rootFolders
                        end repeat
                        set folderResult to my collectFolders(rootFolders, accountKey, "", 0, folderRows, folderCounter, \(maximumFolders), \(maximumDepth))
                        set folderRows to item 1 of folderResult
                        set folderCounter to item 2 of folderResult
                        if item 3 of folderResult then set folderLimitReached to true
                        if item 4 of folderResult then set depthLimitReached to true
                    end if
                end repeat
                return {accountRows, folderRows, defaultAccountKey, accountLimitReached, folderLimitReached, depthLimitReached}
            end tell
        end timeout

        on collectFolders(folderItems, accountKey, parentKey, folderDepth, folderRows, folderCounter, maximumFolders, maximumDepth)
            using terms from application "Notes"
                tell application id "com.apple.Notes"
                    set folderLimitReached to false
                    set depthLimitReached to false
                    repeat with folderItem in folderItems
                        if folderCounter is greater than or equal to maximumFolders then
                            set folderLimitReached to true
                        else
                            set folderCounter to folderCounter + 1
                            set folderKey to (id of folderItem) as text
                            set folderName to (name of folderItem) as text
                            set sharedValue to false
                            try
                                set sharedValue to shared of folderItem
                            end try
                            copy {folderKey, accountKey, parentKey, folderName, sharedValue, folderDepth} to end of folderRows
                            set childFolders to every folder of folderItem
                            if (count of childFolders) is greater than 0 then
                                if folderDepth is greater than or equal to \(maximumDepth) then
                                    set depthLimitReached to true
                                else
                                    set nestedResult to my collectFolders(childFolders, accountKey, folderKey, folderDepth + 1, folderRows, folderCounter, maximumFolders, maximumDepth)
                                    set folderRows to item 1 of nestedResult
                                    set folderCounter to item 2 of nestedResult
                                    if item 3 of nestedResult then set folderLimitReached to true
                                    if item 4 of nestedResult then set depthLimitReached to true
                                end if
                            end if
                        end if
                    end repeat
                    return {folderRows, folderCounter, folderLimitReached, depthLimitReached}
                end tell
            end using terms from
        end collectFolders
        """
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) throws -> NotesMetadataSnapshot {
        guard descriptor.numberOfItems == 6,
              let accountRows = descriptor.atIndex(1),
              let folderRows = descriptor.atIndex(2) else {
            throw NotesMetadataBridgeError.executionFailed
        }
        var accounts: [NotesAccountDescriptor] = []
        for offset in 0..<accountRows.numberOfItems {
            guard let row = accountRows.atIndex(offset + 1), row.numberOfItems == 3,
                  let id = row.atIndex(1)?.stringValue, !id.isEmpty else { continue }
            let defaultFolder = row.atIndex(3)?.stringValue
            accounts.append(NotesAccountDescriptor(
                scriptingID: id,
                name: row.atIndex(2)?.stringValue ?? "",
                defaultFolderScriptingID: defaultFolder.flatMap { $0.isEmpty ? nil : $0 }
            ))
        }
        var folders: [NotesFolderDescriptor] = []
        for offset in 0..<folderRows.numberOfItems {
            guard let row = folderRows.atIndex(offset + 1), row.numberOfItems == 6,
                  let id = row.atIndex(1)?.stringValue, !id.isEmpty,
                  let accountID = row.atIndex(2)?.stringValue, !accountID.isEmpty else { continue }
            let parent = row.atIndex(3)?.stringValue
            folders.append(NotesFolderDescriptor(
                scriptingID: id,
                accountScriptingID: accountID,
                parentScriptingID: parent.flatMap { $0.isEmpty ? nil : $0 },
                name: row.atIndex(4)?.stringValue ?? "",
                shared: row.atIndex(5)?.booleanValue ?? false,
                depth: max(0, Int(row.atIndex(6)?.int32Value ?? 0))
            ))
        }
        let defaultValue = descriptor.atIndex(3)?.stringValue
        let limited = (descriptor.atIndex(4)?.booleanValue ?? false)
            || (descriptor.atIndex(5)?.booleanValue ?? false)
            || (descriptor.atIndex(6)?.booleanValue ?? false)
        return try validateSnapshot(NotesMetadataSnapshot(
            accounts: accounts,
            folders: folders,
            defaultAccountScriptingID: defaultValue.flatMap { $0.isEmpty ? nil : $0 },
            complete: !limited
        ))
    }

    static func validateSnapshot(_ snapshot: NotesMetadataSnapshot) throws -> NotesMetadataSnapshot {
        var accountIDs = Set<String>()
        guard snapshot.accounts.allSatisfy({ accountIDs.insert($0.scriptingID).inserted }) else {
            throw NotesMetadataBridgeError.executionFailed
        }
        var folderIDs = Set<String>()
        guard snapshot.folders.allSatisfy({ folderIDs.insert($0.scriptingID).inserted }) else {
            throw NotesMetadataBridgeError.executionFailed
        }
        let accountByID = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.scriptingID, $0) })
        let folderByID = Dictionary(uniqueKeysWithValues: snapshot.folders.map { ($0.scriptingID, $0) })
        for folder in snapshot.folders {
            guard accountByID[folder.accountScriptingID] != nil else {
                throw NotesMetadataBridgeError.executionFailed
            }
            if let parentID = folder.parentScriptingID {
                guard let parent = folderByID[parentID], parent.accountScriptingID == folder.accountScriptingID else {
                    throw NotesMetadataBridgeError.executionFailed
                }
            }
        }
        return snapshot
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
