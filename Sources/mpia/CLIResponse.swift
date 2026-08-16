import Foundation
import Core
import Contacts
import ContactsAdapter
import MailAdapter
import CalendarAdapter
import RemindersAdapter
import PhotosAdapter
import NotesAdapter
@_spi(ShortcutsFixtureGate) import ShortcutsAdapter
import SafariAdapter
import MessagesAdapter
import PhoneAdapter

extension MpiaCLI {
    static func report(error: String, code: String, arguments: [String], exitCode: Int32) {
        DiagnosticLogger.record(code: code, message: error)
        if arguments.contains("--format") && arguments.contains("json") {
            let response: [String: Any] = ["ok": false, "contractVersion": JSONContract.version, "error": ["code": code, "message": error]]
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { fputs(text + "\n", stderr) }
        } else {
            fputs("error: \(error)\n", stderr)
        }
    }

    static func reportREST(_ error: RESTCLIError) {
        DiagnosticLogger.record(code: error.machineCode, message: error.message)
        var detail: [String: Any] = ["code": error.machineCode, "message": error.message]
        if case .legacySyntaxRemoved(let nextAction) = error { detail["nextAction"] = nextAction }
        let response: [String: Any] = ["ok": false, "contractVersion": JSONContract.version, "error": detail]
        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { fputs(text + "\n", stderr) }
    }

    struct JSONSuccess<T: Encodable>: Encodable { let ok = true; let contractVersion = JSONContract.version; let data: T }
    struct ContactWriteResult: Encodable { let operation: String; let contact: ContactPayload }
    struct ContactImageWriteResult: Encodable { let operation: String; let contact: ContactPayload; let avatar: AvatarWriteVerification }
    struct ContactDeleteResult: Encodable { let operation = "deleted"; let contact: ContactPayload }
    struct ContactAlreadyDeletedResult: Encodable { let operation = "already_deleted"; let externalID: String }
    struct MigrationPreview: Encodable { let from: String; let to: String; let dryRun: Bool; let message: String? }
    struct MigrationResult: Encodable { let from: String; let to: String; let contact: ContactPayload }
    struct CalendarWriteResult: Encodable { let operation: String; let dryRun: Bool; let event: CalendarEventPayload }
    struct CalendarUpdatePreview: Encodable { let operation: String; let dryRun: Bool; let before: CalendarEventPayload; let after: CalendarEventPayload }
    struct CalendarPermissionResult: Encodable { let granted: Bool; let access: String }
    struct RemindersPermissionResult: Encodable { let granted: Bool; let access: String }
    struct PhotosPermissionResult: Encodable {
        let access: String
        let readable: Bool
        let complete: Bool
        let requested: Bool
    }
    struct PhotoAlbumArguments {
        var kind: PhotoAlbumQueryKind = .all
        var limit = Pagination.defaultLimit
        var cursor: String?
    }
    struct PhotoGetArguments {
        let id: String
        let includeLocation: Bool
    }
    struct PhotoExportArguments {
        let id: String
        let outputURL: URL
        let variant: PhotoExportVariant
        let allowNetwork: Bool
    }
    struct NotesFolderArguments {
        var accountID: String?
        var parentID: String?
        var limit = Pagination.defaultLimit
        var cursor: String?
    }

    struct NotesGetArguments {
        let id: String
        let bodyFormat: NotesBodyFormat
        let includeAttachments: Bool
    }

    struct NotesWriteAccountArguments { let accountID: String?; let apply: Bool }
    struct NotesMutationArguments { let id: String?; let data: Data; let apply: Bool; let idempotent: Bool }
    struct SafariBookmarkPageArguments { let query: SafariBookmarkQuery; let limit: Int; let cursor: String? }
    struct SafariReadingListPageArguments { let query: SafariReadingListQuery; let limit: Int; let cursor: String? }
    struct SafariReadingListAddArguments { let data: Data; let apply: Bool }
    struct SafariLocalMutationArguments { let data: Data; let apply: Bool; let confirmation: String? }

    static func emitJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) { print(text) }
    }

    static func emitPhotosJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    static func emitNotesJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    static func emitSafariJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

}
