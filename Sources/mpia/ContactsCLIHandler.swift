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
    static func handleContacts(_ arguments: [String], containerSelector: String?) async throws -> Bool {
        let permission = ContactsPermission()
        let store = ContactsStore(permission: permission, containerSelector: containerSelector)
        switch arguments {
        case ["contacts", "permission"]:
            let granted = try await permission.requestAccess()
            emitJSONSuccess(["granted": granted])
            if !granted { Foundation.exit(2) }
        case ["contacts", "count"]:
            emitJSONSuccess(["count": try store.count()])
        case ["contacts", "containers"]:
            emitJSONSuccess(try store.containerDescriptions())
        case ["contacts", "container"]:
            emitJSONSuccess(try store.selectedContainerDescription())
        case ["contacts", "export"]:
            emitJSONSuccess(try store.list())
        case let args where args.count == 4 && args[0] == "contacts" && args[1] == "export" && args[2] == "--output":
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store.list()).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
            emitJSONSuccess(["message": "Contacts exported.", "output": args[3]])
        case let args where args.count >= 2 && args[0] == "contacts" && args[1] == "list":
            let pagination = try parseContactPagination(Array(args.dropFirst(2)))
            emitJSONSuccess(try store.listPage(limit: pagination.limit, cursor: pagination.cursor))
        case let args where args.count == 4 && args[0] == "contacts" && args[1] == "get" && args[2] == "--external-id":
            emitJSONSuccess(try store.get(externalID: args[3]))
        case let args where args.count == 5 && args[0] == "contacts" && args[1] == "avatar" && args[2] == "verify" && args[3] == "--external-id":
            let verification = try store.verifyImage(externalID: args[4])
            emitJSONSuccess(verification)
        case let args where (args.count == 8 || args.count == 10) &&
            args[0] == "contacts" && args[1] == "avatar" && args[2] == "replace" &&
            args[3] == "--external-id" && args[5] == "--image":
            let externalID = args[4]
            let imagePath = args[6]
            let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            guard !imageData.isEmpty else { throw ContactsError.invalidInput("image file is empty") }
            let processed = try ContactImageProcessor().process(imageData)
            let isApply = args.count == 10 && args[7] == "--apply" && args[8] == "--confirm" && args[9] == "RECREATE CONTACT"
            let isDryRun = args.count == 8 && args[7] == "--dry-run"
            guard isApply || isDryRun else { throw ContactsError.avatarReplacementConfirmationRequired }
            if isDryRun {
                let preview: [String: JSONValue] = ["externalID": .string(externalID), "originalBytes": .integer(imageData.count), "finalBytes": .integer(processed.data.count), "width": .integer(processed.width), "height": .integer(processed.height), "dryRun": .bool(true), "operation": .string("avatar_replace")]
                emitJSONSuccess(preview)
            } else {
                let verification = try store.replaceImage(externalID: externalID, data: imageData)
                emitJSONSuccess(ContactImageWriteResult(operation: "avatar_replaced", contact: try store.get(externalID: externalID), avatar: verification))
            }
        case let args where args.count >= 4 && args[0] == "contacts" && args[1] == "query":
            let pagination = try parseContactPagination(Array(args.dropFirst(2)))
            let query = try parseQuerySet(pagination.conditions)
            emitJSONSuccess(try store.queryPage(query, limit: pagination.limit, cursor: pagination.cursor))
        case let args where args.count >= 4 && args[0] == "contacts" && args[1] == "create":
            let (inputData, mode, idempotent) = try parseJSONWriteArguments(Array(args.dropFirst(2)), command: "create")
            let payload = try JSONDecoder().decode(ContactPayload.self, from: inputData)
            guard payload.externalID != nil else { throw ContactsError.invalidInput("external_id is required") }
            if mode == "--dry-run" {
                let preview = ContactsMapper().map(ContactsMapper().makeMutableContact(from: payload))
                emitJSONSuccess(preview)
            } else {
                let existing: ContactPayload?
                do { existing = try store.get(externalID: payload.externalID!) }
                catch ContactsQueryError.notFound { existing = nil }
                if let existing {
                    guard idempotent else { throw ContactsError.duplicateExternalID(payload.externalID!) }
                    guard payload.isEquivalentForIdempotentCreate(to: existing) else { throw ContactsError.idempotencyConflict(payload.externalID!) }
                    emitJSONSuccess(ContactWriteResult(operation: "already_exists", contact: existing))
                } else {
                    try store.create(payload)
                    emitJSONSuccess(ContactWriteResult(operation: "created", contact: try store.get(externalID: payload.externalID!)))
                }
            }
        case let args where args.count >= 6 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && args.contains("--inline-json"):
            let externalID = args[3]
            let (inputData, mode, idempotent) = try parseJSONWriteArguments(Array(args.dropFirst(4)), command: "edit")
            guard !idempotent else { throw ContactsError.invalidInput("--idempotent is supported only by create") }
            let patch = try JSONDecoder().decode(ContactPatch.self, from: inputData)
            if mode == "--apply" { try store.update(externalID: externalID, with: patch); emitJSONSuccess(ContactWriteResult(operation: "updated", contact: try store.get(externalID: externalID))) }
            else { let before = try store.get(externalID: externalID); let mutable = ContactsMapper().makeMutableContact(from: before); try ContactsMapper().update(mutable, from: patch, preservingExternalID: externalID); var after = ContactsMapper().map(mutable); after.imageAvailable = before.imageAvailable; emitJSONSuccess(["before": before, "after": after]) }
        case let args where args.count == 7 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && args[4] == "--image":
            let externalID = args[3]
            let imagePath = args[5]
            guard args[6] == "--dry-run" || args[6] == "--apply" else { throw ContactsError.invalidInput("image edit requires --dry-run or --apply") }
            let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            guard !imageData.isEmpty else { throw ContactsError.invalidInput("image file is empty") }
            let processed = try ContactImageProcessor().process(imageData)
            if args[6] == "--apply" {
                let verification = try store.updateImage(externalID: externalID, data: imageData)
                emitJSONSuccess(ContactImageWriteResult(operation: "image_updated", contact: try store.get(externalID: externalID), avatar: verification))
            } else {
                let preview: [String: JSONValue] = [
                    "externalID": .string(externalID), "originalBytes": .integer(imageData.count),
                    "finalBytes": .integer(processed.data.count), "width": .integer(processed.width),
                    "height": .integer(processed.height), "compressed": .bool(processed.wasCompressed),
                    "dryRun": .bool(true), "operation": .string("avatar_edit")
                ]
                emitJSONSuccess(preview)
            }
        case let args where args.count >= 4 &&
            args[0] == "contacts" && args[1] == "delete" && args[2] == "--external-id":
            let externalID = args[3]
            let ignoreNotFound = args.contains("--ignore-not-found")
            let normalizedArgs = args.filter { $0 != "--ignore-not-found" }
            let isApply = normalizedArgs.count == 7 && normalizedArgs[4] == "--apply" && normalizedArgs[5] == "--confirm" && normalizedArgs[6] == "DELETE CONTACT"
            guard (normalizedArgs.count == 5 && normalizedArgs[4] == "--dry-run") || isApply else { throw ContactsError.invalidInput("delete requires --dry-run or --apply --confirm \"DELETE CONTACT\"") }
            if isApply {
                do {
                    let deleted = try store.get(externalID: externalID)
                    try store.delete(externalID: externalID)
                    emitJSONSuccess(ContactDeleteResult(contact: deleted))
                } catch ContactsQueryError.notFound where ignoreNotFound {
                    emitJSONSuccess(ContactAlreadyDeletedResult(externalID: externalID))
                }
            }
            else { emitJSONSuccess(try store.get(externalID: externalID)) }
        case let args where args.count >= 7 &&
            args[0] == "contacts" && args[1] == "external-id" && args[2] == "migrate" &&
            args[3] == "--from" && args[5] == "--to":
            let oldID = args[4], newID = args[6]
            let isApply = args.count == 10 && args[7] == "--apply" && args[8] == "--confirm" && args[9] == "CHANGE EXTERNAL ID"
            guard (args.count == 8 && args[7] == "--dry-run") || isApply else { throw ContactsError.externalIDMigrationConfirmationRequired }
            if isApply { try store.migrateExternalID(from: oldID, to: newID); emitJSONSuccess(MigrationResult(from: oldID, to: newID, contact: try store.get(externalID: newID))) }
            else { emitJSONSuccess(MigrationPreview(from: oldID, to: newID, dryRun: true, message: nil)) }
        default: return false
        }
        return true
    }
}
