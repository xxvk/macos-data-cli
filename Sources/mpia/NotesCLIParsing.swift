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
    static func parseNotesWriteAccountArguments(_ arguments: [String], clear: Bool) throws -> NotesWriteAccountArguments {
        var accountID: String?
        var apply = false
        var modeSeen = false
        var confirmation: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--account-id":
                guard !clear, accountID == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                accountID = arguments[index + 1]; index += 2
            case "--dry-run":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; index += 1
            case "--apply":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; apply = true; index += 1
            case "--confirm":
                guard confirmation == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                confirmation = arguments[index + 1]; index += 2
            default: throw NotesError.invalidWriteInput
            }
        }
        if clear { guard accountID == nil else { throw NotesError.invalidWriteInput } }
        else { guard let accountID, !accountID.isEmpty else { throw NotesError.invalidWriteInput } }
        if apply {
            let expected = clear ? "CLEAR ICLOUD NOTES" : "BIND ICLOUD NOTES"
            guard confirmation == expected else { throw NotesError.invalidWriteInput }
        }
        return NotesWriteAccountArguments(accountID: accountID, apply: apply)
    }

    static func parseNotesMutationArguments(_ arguments: [String], command: String, requiresID: Bool) throws -> NotesMutationArguments {
        var id: String?
        var inputData: Data?
        var apply = false
        var modeSeen = false
        var idempotent = false
        var confirmation: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--id":
                guard requiresID, id == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                id = arguments[index + 1]; index += 2
            case "--inline-json":
                guard inputData == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                inputData = Data(arguments[index + 1].utf8); index += 2
            case "--dry-run":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; index += 1
            case "--apply":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; apply = true; index += 1
            case "--idempotent":
                guard command == "create", !idempotent else { throw NotesError.invalidWriteInput }
                idempotent = true; index += 1
            case "--confirm":
                guard ["delete", "folder-delete"].contains(command), confirmation == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                confirmation = arguments[index + 1]; index += 2
            default: throw NotesError.invalidWriteInput
            }
        }
        guard let data = inputData, !data.isEmpty, !requiresID || !(id ?? "").isEmpty else { throw NotesError.invalidWriteInput }
        if command == "delete", apply {
            guard confirmation == "DELETE NOTE" else { throw NotesError.invalidWriteInput }
        } else if command == "folder-delete", apply {
            guard confirmation == "DELETE EMPTY NOTES FOLDER" else { throw NotesError.invalidWriteInput }
        } else if confirmation != nil {
            throw NotesError.invalidWriteInput
        }
        return NotesMutationArguments(id: id, data: data, apply: apply, idempotent: idempotent)
    }

    static func decodeNotesWrite<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(T.self, from: data) }
        catch { throw NotesError.invalidWriteInput }
    }

    static func parseNotesFolderArguments(_ arguments: [String]) throws -> NotesFolderArguments {
        var result = NotesFolderArguments()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw NotesError.invalidIdentifier }
            guard index + 1 < arguments.count else { throw NotesError.invalidIdentifier }
            let value = arguments[index + 1]
            guard !value.isEmpty else { throw NotesError.invalidIdentifier }
            switch option {
            case "--account-id": result.accountID = value
            case "--parent-id": result.parentID = value
            case "--limit":
                guard let limit = Int(value), (1...Pagination.maximumLimit).contains(limit) else {
                    throw NotesError.invalidLimit
                }
                result.limit = limit
            case "--cursor": result.cursor = value
            default: throw NotesError.invalidIdentifier
            }
            index += 2
        }
        return result
    }

    static func parseNotesQueryArguments(_ arguments: [String]) throws -> NotesQuery {
        var accountID: String?
        var folderID: String?
        var title: String?
        var modifiedAfter: Date?
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted, index + 1 < arguments.count else { throw NotesError.invalidQuery }
            let value = arguments[index + 1]
            guard !value.isEmpty else { throw NotesError.invalidQuery }
            switch option {
            case "--account-id": accountID = value
            case "--folder-id": folderID = value
            case "--title":
                guard value.count <= 200 else { throw NotesError.invalidQuery }
                title = value
            case "--modified-after":
                guard let parsed = ISO8601DateFormatter().date(from: value) else { throw NotesError.invalidQuery }
                modifiedAfter = parsed
            case "--limit":
                guard let parsed = Int(value), (1...Pagination.maximumLimit).contains(parsed) else {
                    throw NotesError.invalidLimit
                }
                limit = parsed
            case "--cursor": cursor = value
            default: throw NotesError.invalidQuery
            }
            index += 2
        }
        return NotesQuery(
            accountID: accountID,
            folderID: folderID,
            title: title,
            modifiedAfter: modifiedAfter,
            limit: limit,
            cursor: cursor
        )
    }

    static func parseNotesGetArguments(_ arguments: [String]) throws -> NotesGetArguments {
        var id: String?
        var bodyFormat = NotesBodyFormat.none
        var includeAttachments = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--body", "--include-attachments"].contains(option), seen.insert(option).inserted else { throw NotesError.invalidQuery }
            if option == "--include-attachments" {
                includeAttachments = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw NotesError.invalidQuery }
            let value = arguments[index + 1]
            if option == "--id" {
                id = value
            } else {
                guard let parsed = NotesBodyFormat(rawValue: value) else { throw NotesError.invalidQuery }
                bodyFormat = parsed
            }
            index += 2
        }
        guard let id, !id.isEmpty else { throw NotesError.invalidIdentifier }
        return NotesGetArguments(id: id, bodyFormat: bodyFormat, includeAttachments: includeAttachments)
    }

}
