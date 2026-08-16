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
    static func handleReminders(_ arguments: [String], sourceSelector: String?) async throws -> Bool {
        let remindersPermission = RemindersPermission()
        let remindersStore = RemindersStore(permission: remindersPermission, sourceSelector: sourceSelector)
        switch arguments {
        case ["reminders", "permission"]:
            let granted = try await remindersPermission.requestFullAccess()
            emitJSONSuccess(RemindersPermissionResult(granted: granted, access: remindersPermission.status.rawValue))
            if !granted { Foundation.exit(CLIExitCode.remindersFailure.rawValue) }
        case ["reminders", "sources"]:
            emitJSONSuccess(try remindersStore.sourceDescriptions())
        case ["reminders", "lists"]:
            emitJSONSuccess(try remindersStore.listDescriptions())
        case let args where args.count >= 2 && args[0] == "reminders" && args[1] == "query":
            emitRemindersJSONSuccess(try await remindersStore.query(parseReminderQuery(Array(args.dropFirst(2)))))
        case let args where args.count == 4 && args[0] == "reminders" && args[1] == "get" && args[2] == "--id":
            emitRemindersJSONSuccess(try remindersStore.get(id: args[3]))
        case let args where args.count >= 3 && args[0] == "reminders" && args[1] == "create":
            let request = try parseReminderCreateArguments(Array(args.dropFirst(2)))
            let input: ReminderInput = try decodeReminder(request.data)
            if request.mode == "--dry-run" {
                emitRemindersJSONSuccess(try remindersStore.previewCreate(input))
            } else {
                emitRemindersJSONSuccess(try remindersStore.create(input, idempotent: request.idempotent))
            }
        case let args where args.count >= 5 && args[0] == "reminders" && args[1] == "edit" && args[2] == "--id":
            let request = try parseReminderEditArguments(Array(args.dropFirst(4)))
            let patch: ReminderPatch = try decodeReminder(request.data)
            if request.mode == "--dry-run" {
                emitRemindersJSONSuccess(try remindersStore.previewUpdate(id: args[3], patch: patch))
            } else {
                emitRemindersJSONSuccess(try remindersStore.update(id: args[3], patch: patch))
            }
        case let args where args.count >= 4 && args[0] == "reminders" && ["complete", "reopen"].contains(args[1]) && args[2] == "--id":
            let action: ReminderStateAction = args[1] == "complete" ? .complete : .reopen
            let apply = try parseReminderStateArguments(Array(args.dropFirst(4)), command: args[1])
            if apply {
                emitRemindersJSONSuccess(try remindersStore.changeState(id: args[3], action: action))
            } else {
                emitRemindersJSONSuccess(try remindersStore.previewStateChange(id: args[3], action: action))
            }
        case let args where args.count >= 4 && args[0] == "reminders" && args[1] == "delete" && args[2] == "--id":
            let apply = try parseReminderDeleteArguments(Array(args.dropFirst(4)))
            if apply {
                emitRemindersJSONSuccess(try remindersStore.delete(id: args[3]))
            } else {
                emitRemindersJSONSuccess(try remindersStore.previewDelete(id: args[3]))
            }
        default: return false
        }
        return true
    }
}
