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
    static func handleCalendar(_ arguments: [String], sourceSelector: String?) async throws -> Bool {
        let calendarPermission = CalendarPermission()
        let calendarStore = CalendarStore(permission: calendarPermission, sourceSelector: sourceSelector)
        switch arguments {
        case ["calendar", "permission"]:
            let granted = try await calendarPermission.requestFullAccess()
            emitJSONSuccess(CalendarPermissionResult(granted: granted, access: calendarPermission.status.rawValue))
            if !granted { Foundation.exit(CLIExitCode.calendarFailure.rawValue) }
        case ["calendar", "sources"]:
            emitJSONSuccess(try calendarStore.sourceDescriptions())
        case ["calendar", "calendars"]:
            emitJSONSuccess(try calendarStore.calendarDescriptions())
        case let args where args.count >= 2 && args[0] == "calendar" && args[1] == "query":
            emitCalendarJSONSuccess(try calendarStore.query(parseCalendarQuery(Array(args.dropFirst(2)))))
        case let args where args.count >= 2 && args[0] == "calendar" && args[1] == "conflicts":
            emitCalendarJSONSuccess(try calendarStore.conflicts(parseCalendarConflicts(Array(args.dropFirst(2)))))
        case let args where args.count == 4 && args[0] == "calendar" && args[1] == "get" && args[2] == "--id":
            emitCalendarJSONSuccess(try calendarStore.get(id: args[3]))
        case let args where args.count >= 3 && args[0] == "calendar" && args[1] == "create":
            let request = try parseCalendarWriteArguments(Array(args.dropFirst(2)), command: "create", allowsSpan: false)
            let input: CalendarEventInput = try decodeCalendar(request.data)
            if request.idempotent {
                let result = try calendarStore.createIdempotent(input, dryRun: request.mode == "--dry-run")
                emitCalendarJSONSuccess(CalendarWriteResult(
                    operation: result.created ? (request.mode == "--dry-run" ? "create_preview" : "created") : "existing",
                    dryRun: request.mode == "--dry-run",
                    event: result.event
                ))
            } else if request.mode == "--dry-run" {
                emitCalendarJSONSuccess(CalendarWriteResult(operation: "create_preview", dryRun: true, event: try calendarStore.previewCreate(input)))
            } else {
                emitCalendarJSONSuccess(CalendarWriteResult(operation: "created", dryRun: false, event: try calendarStore.create(input)))
            }
        case let args where args.count >= 5 && args[0] == "calendar" && args[1] == "edit" && args[2] == "--id":
            let id = args[3]
            let request = try parseCalendarWriteArguments(Array(args.dropFirst(4)), command: "edit", allowsSpan: true)
            let patch: CalendarEventPatch = try decodeCalendar(request.data)
            if request.mode == "--dry-run" {
                let before = try calendarStore.get(id: id)
                let after = try calendarStore.previewUpdate(id: id, patch: patch, span: request.span)
                emitCalendarJSONSuccess(CalendarUpdatePreview(operation: "update_preview", dryRun: true, before: before, after: after))
            } else {
                emitCalendarJSONSuccess(CalendarWriteResult(operation: "updated", dryRun: false, event: try calendarStore.update(id: id, patch: patch, span: request.span)))
            }
        case let args where args.count >= 5 && args[0] == "calendar" && args[1] == "delete" && args[2] == "--id":
            let request = try parseCalendarDeleteArguments(Array(args.dropFirst(4)))
            if request.apply {
                emitCalendarJSONSuccess(CalendarWriteResult(operation: "deleted", dryRun: false, event: try calendarStore.delete(id: args[3], span: request.span)))
            } else {
                emitCalendarJSONSuccess(CalendarWriteResult(operation: "delete_preview", dryRun: true, event: try calendarStore.previewDelete(id: args[3], span: request.span)))
            }
        default: return false
        }
        return true
    }
}
