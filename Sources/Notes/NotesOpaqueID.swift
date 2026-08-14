import CryptoKit
import Foundation

public enum NotesOpaqueID {
    public static func account(scriptingID: String) -> String {
        "notesaccount_" + digest("notes-account-v1:\(scriptingID)")
    }

    public static func folder(accountScriptingID: String, scriptingID: String) -> String {
        "notesfolder_" + digest("notes-folder-v1:\(accountScriptingID):\(scriptingID)")
    }

    public static func note(accountScriptingID: String, scriptingID: String) -> String {
        "note_" + digest("notes-note-v1:\(accountScriptingID):\(scriptingID)")
    }

    public static func isNote(_ value: String) -> Bool {
        value.hasPrefix("note_") && value.count == "note_".count + 64
    }

    public static func attachment(noteScriptingID: String, scriptingID: String) -> String {
        "noteattachment_" + digest("notes-attachment-v1:\(noteScriptingID):\(scriptingID)")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
