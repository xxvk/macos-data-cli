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
    static func handleNotes(_ arguments: [String]) throws -> Bool {
        let notesPermission = NotesPermissionService()
        let notesStore = NotesStore(permission: notesPermission)
        switch arguments {
        case ["notes", "permission"]:
            emitJSONSuccess(notesPermission.check(requestConsent: false))
        case ["notes", "permission", "--request"]:
            let result = notesPermission.check(requestConsent: true)
            emitJSONSuccess(result)
            if !result.readable { Foundation.exit(CLIExitCode.notesFailure.rawValue) }
        case ["notes", "accounts"]:
            emitJSONSuccess(try notesStore.accounts())
        case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "create":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "create", requiresID: false)
            let input: NotesFolderCreateInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.createFolder(input, idempotent: request.idempotent)) }
            else { emitNotesJSONSuccess(try notesStore.previewCreateFolder(input)) }
        case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "rename":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "rename", requiresID: true)
            let input: NotesFolderRenameInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.renameFolder(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewRenameFolder(id: request.id!, input: input)) }
        case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "move":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "move", requiresID: true)
            let input: NotesFolderMoveInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.moveFolder(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewMoveFolder(id: request.id!, input: input)) }
        case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "delete":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "folder-delete", requiresID: true)
            let input: NotesFolderDeleteInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.deleteFolder(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewDeleteFolder(id: request.id!, input: input)) }
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "folders":
            let request = try parseNotesFolderArguments(Array(args.dropFirst(2)))
            emitJSONSuccess(try notesStore.folders(
                limit: request.limit,
                cursor: request.cursor,
                accountID: request.accountID,
                parentID: request.parentID
            ))
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "query":
            emitNotesJSONSuccess(try notesStore.query(parseNotesQueryArguments(Array(args.dropFirst(2)))))
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "get":
            let request = try parseNotesGetArguments(Array(args.dropFirst(2)))
            emitNotesJSONSuccess(try notesStore.get(id: request.id, bodyFormat: request.bodyFormat, includeAttachments: request.includeAttachments))
        case ["notes", "write-account", "status"]:
            emitNotesJSONSuccess(notesStore.writeAccountStatus())
        case let args where args.count >= 3 && args[0] == "notes" && args[1] == "write-account" && args[2] == "bind":
            let request = try parseNotesWriteAccountArguments(Array(args.dropFirst(3)), clear: false)
            emitNotesJSONSuccess(try notesStore.changeWriteAccount(accountID: request.accountID, clear: false, apply: request.apply))
        case let args where args.count >= 3 && args[0] == "notes" && args[1] == "write-account" && args[2] == "clear":
            let request = try parseNotesWriteAccountArguments(Array(args.dropFirst(3)), clear: true)
            emitNotesJSONSuccess(try notesStore.changeWriteAccount(accountID: nil, clear: true, apply: request.apply))
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "create":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "create", requiresID: false)
            let input: NotesCreateInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.create(input, idempotent: request.idempotent)) }
            else { emitNotesJSONSuccess(try notesStore.previewCreate(input)) }
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "rename":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "rename", requiresID: true)
            let input: NotesRenameInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.rename(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewRename(id: request.id!, input: input)) }
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "move":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "move", requiresID: true)
            let input: NotesMoveInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.move(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewMove(id: request.id!, input: input)) }
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "delete":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "delete", requiresID: true)
            let input: NotesDeleteInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.delete(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewDelete(id: request.id!, input: input)) }
        case let args where args.count >= 2 && args[0] == "notes" && args[1] == "edit-body":
            let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "edit-body", requiresID: true)
            let input: NotesEditBodyInput = try decodeNotesWrite(request.data)
            if request.apply { emitNotesJSONSuccess(try notesStore.editBody(id: request.id!, input: input)) }
            else { emitNotesJSONSuccess(try notesStore.previewEditBody(id: request.id!, input: input)) }
        default: return false
        }
        return true
    }
}
