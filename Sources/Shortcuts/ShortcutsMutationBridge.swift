import AppKit
import Foundation

public protocol ShortcutsMutationBridging: Sendable {
    func move(shortcutScriptingID: String, destinationFolderScriptingID: String) throws -> String
}

public struct SystemShortcutsMutationBridge: ShortcutsMutationBridging {
    public init() {}

    public func move(shortcutScriptingID: String, destinationFolderScriptingID: String) throws -> String {
        let source = Self.moveScript(shortcutScriptingID: shortcutScriptingID, destinationFolderScriptingID: destinationFolderScriptingID)
        shortcutsAppleEventLock.lock()
        defer { shortcutsAppleEventLock.unlock() }
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
        guard let value = result.stringValue, !value.isEmpty else { throw ShortcutsBridgeError.executionFailed }
        return value
    }

    public static func moveScript(shortcutScriptingID: String, destinationFolderScriptingID: String) -> String {
        """
        with timeout of 5 seconds
            tell application id "com.apple.shortcuts.events"
                set selectedShortcut to first shortcut whose id is "\(escape(shortcutScriptingID))"
                set destinationFolder to first folder whose id is "\(escape(destinationFolderScriptingID))"
                set folder of selectedShortcut to destinationFolder
                return (id of folder of selectedShortcut) as text
            end tell
        end timeout
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
