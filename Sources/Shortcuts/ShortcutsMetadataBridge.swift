import AppKit
import Foundation

public struct ShortcutDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let name: String
    public let subtitle: String
    public let folderScriptingID: String?
    public let acceptsInput: Bool
    public let actionCount: Int
    public let color: [Int]
    public let iconAvailable: Bool

    public init(scriptingID: String, name: String, subtitle: String, folderScriptingID: String?, acceptsInput: Bool, actionCount: Int, color: [Int], iconAvailable: Bool) {
        self.scriptingID = scriptingID
        self.name = name
        self.subtitle = subtitle
        self.folderScriptingID = folderScriptingID
        self.acceptsInput = acceptsInput
        self.actionCount = actionCount
        self.color = color
        self.iconAvailable = iconAvailable
    }
}

public struct ShortcutFolderDescriptor: Equatable, Sendable {
    public let scriptingID: String
    public let name: String
    public init(scriptingID: String, name: String) { self.scriptingID = scriptingID; self.name = name }
}

public struct ShortcutsMetadataSnapshot: Equatable, Sendable {
    public let shortcuts: [ShortcutDescriptor]
    public let folders: [ShortcutFolderDescriptor]
    public let complete: Bool
    public init(shortcuts: [ShortcutDescriptor], folders: [ShortcutFolderDescriptor], complete: Bool) {
        self.shortcuts = shortcuts; self.folders = folders; self.complete = complete
    }
}

public enum ShortcutsBridgeError: Error, Equatable, Sendable {
    case automationDenied
    case targetNotRunning
    case timedOut
    case executionFailed
}

public protocol ShortcutsMetadataBridging: Sendable {
    func snapshot(maximumShortcuts: Int, maximumFolders: Int) throws -> ShortcutsMetadataSnapshot
}

let shortcutsAppleEventLock = NSLock()

public struct SystemShortcutsMetadataBridge: ShortcutsMetadataBridging {
    public static let maximumShortcuts = 200
    public static let maximumFolders = 200
    public static let timeoutSeconds = 5
    public init() {}

    public func snapshot(maximumShortcuts: Int, maximumFolders: Int) throws -> ShortcutsMetadataSnapshot {
        guard (1...Self.maximumShortcuts).contains(maximumShortcuts),
              (1...Self.maximumFolders).contains(maximumFolders) else { throw ShortcutsBridgeError.executionFailed }
        return try Self.parseSnapshot(execute(Self.snapshotScript(maximumShortcuts: maximumShortcuts, maximumFolders: maximumFolders, timeoutSeconds: Self.timeoutSeconds)))
    }

    public static func snapshotScript(maximumShortcuts: Int, maximumFolders: Int, timeoutSeconds: Int) -> String {
        """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.shortcuts.events"
                set folderRows to {}
                set shortcutRows to {}
                set folderCounter to 0
                set shortcutCounter to 0
                set folderLimitReached to false
                set shortcutLimitReached to false
                repeat with folderItem in every folder
                    if folderCounter is greater than or equal to \(maximumFolders) then
                        set folderLimitReached to true
                    else
                        set folderCounter to folderCounter + 1
                        copy {(id of folderItem) as text, (name of folderItem) as text} to end of folderRows
                    end if
                end repeat
                repeat with shortcutItem in every shortcut
                    if shortcutCounter is greater than or equal to \(maximumShortcuts) then
                        set shortcutLimitReached to true
                    else
                        set shortcutCounter to shortcutCounter + 1
                        set folderKey to ""
                        try
                            set folderKey to (id of folder of shortcutItem) as text
                        end try
                        set colorValue to {}
                        try
                            set colorValue to color of shortcutItem
                        end try
                        set iconFlag to false
                        try
                            if icon of shortcutItem is not missing value then set iconFlag to true
                        end try
                        copy {(id of shortcutItem) as text, (name of shortcutItem) as text, (subtitle of shortcutItem) as text, folderKey, accepts input of shortcutItem, action count of shortcutItem, colorValue, iconFlag} to end of shortcutRows
                    end if
                end repeat
                return {shortcutRows, folderRows, shortcutLimitReached, folderLimitReached}
            end tell
        end timeout
        """
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) throws -> ShortcutsMetadataSnapshot {
        guard descriptor.numberOfItems == 4,
              let shortcutRows = descriptor.atIndex(1),
              let folderRows = descriptor.atIndex(2) else { throw ShortcutsBridgeError.executionFailed }
        var folders: [ShortcutFolderDescriptor] = []
        if folderRows.numberOfItems > 0 {
            for index in 1...folderRows.numberOfItems {
                guard let row = folderRows.atIndex(index), row.numberOfItems == 2,
                      let id = row.atIndex(1)?.stringValue, !id.isEmpty else { continue }
                folders.append(.init(scriptingID: id, name: row.atIndex(2)?.stringValue ?? ""))
            }
        }
        var shortcuts: [ShortcutDescriptor] = []
        if shortcutRows.numberOfItems > 0 {
            for index in 1...shortcutRows.numberOfItems {
                guard let row = shortcutRows.atIndex(index), row.numberOfItems == 8,
                      let id = row.atIndex(1)?.stringValue, !id.isEmpty else { continue }
                let folder = row.atIndex(4)?.stringValue
                let colorDescriptor = row.atIndex(7)
                var color: [Int] = []
                if let colorDescriptor, colorDescriptor.numberOfItems > 0 {
                    for colorIndex in 1...colorDescriptor.numberOfItems {
                        color.append(Int(colorDescriptor.atIndex(colorIndex)?.int32Value ?? 0))
                    }
                }
                shortcuts.append(.init(
                    scriptingID: id,
                    name: row.atIndex(2)?.stringValue ?? "",
                    subtitle: row.atIndex(3)?.stringValue ?? "",
                    folderScriptingID: folder.flatMap { $0.isEmpty ? nil : $0 },
                    acceptsInput: row.atIndex(5)?.booleanValue ?? false,
                    actionCount: max(0, Int(row.atIndex(6)?.int32Value ?? 0)),
                    color: color,
                    iconAvailable: row.atIndex(8)?.booleanValue ?? false
                ))
            }
        }
        let snapshot = ShortcutsMetadataSnapshot(
            shortcuts: shortcuts,
            folders: folders,
            complete: !(descriptor.atIndex(3)?.booleanValue ?? false) && !(descriptor.atIndex(4)?.booleanValue ?? false)
        )
        return try validate(snapshot)
    }

    static func validate(_ snapshot: ShortcutsMetadataSnapshot) throws -> ShortcutsMetadataSnapshot {
        let folderIDs = Set(snapshot.folders.map(\.scriptingID))
        guard folderIDs.count == snapshot.folders.count,
              Set(snapshot.shortcuts.map(\.scriptingID)).count == snapshot.shortcuts.count,
              snapshot.shortcuts.allSatisfy({ $0.folderScriptingID == nil || folderIDs.contains($0.folderScriptingID!) }) else {
            throw ShortcutsBridgeError.executionFailed
        }
        return snapshot
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        shortcutsAppleEventLock.lock()
        defer { shortcutsAppleEventLock.unlock() }
        do {
            return try executeOnce(source)
        } catch ShortcutsBridgeError.targetNotRunning {
            guard ShortcutsHelperLauncher.launch() else { throw ShortcutsBridgeError.targetNotRunning }
            for attempt in 0..<10 {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.1) }
                do { return try executeOnce(source) }
                catch ShortcutsBridgeError.targetNotRunning { continue }
            }
            throw ShortcutsBridgeError.targetNotRunning
        }
    }

    private func executeOnce(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw ShortcutsBridgeError.executionFailed }
        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details, let number = details[NSAppleScript.errorNumber] as? NSNumber {
            switch number.intValue {
            case -1743: throw ShortcutsBridgeError.automationDenied
            case -1712: throw ShortcutsBridgeError.timedOut
            case -600, -609: throw ShortcutsBridgeError.targetNotRunning
            default: throw ShortcutsBridgeError.executionFailed
            }
        }
        return result
    }
}
