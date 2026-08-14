import CryptoKit
import Foundation

public enum ShortcutsOpaqueID {
    public static func shortcut(scriptingID: String) -> String {
        "shortcut_" + digest("shortcuts-shortcut-v1:\(scriptingID)")
    }

    public static func folder(scriptingID: String) -> String {
        "shortcutfolder_" + digest("shortcuts-folder-v1:\(scriptingID)")
    }

    public static func isShortcut(_ value: String) -> Bool {
        value.hasPrefix("shortcut_") && value.count == "shortcut_".count + 64
    }

    public static func isFolder(_ value: String) -> Bool {
        value.hasPrefix("shortcutfolder_") && value.count == "shortcutfolder_".count + 64
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
