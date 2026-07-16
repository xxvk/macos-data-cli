import Foundation
import Core
import Contacts
import ContactsAdapter

@main
struct MacosDataCLI {
    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let jsonRequested = rawArguments.contains("--format") && rawArguments.contains("json")
        let arguments = rawArguments.filter { $0 != "--format" && $0 != "json" }

        if arguments.isEmpty || arguments == ["--help"] || arguments == ["contacts", "--help"] {
            printHelp()
            return
        }

        if arguments == ["--version"] || arguments == ["-v"] {
            print("0.1.6")
            return
        }

        do {
            let permission = ContactsPermission()
            let store = ContactsStore(permission: permission)
            switch arguments {
            case ["contacts", "permission"]:
                let granted = try await permission.requestAccess()
                print(granted ? "Contacts permission granted." : "Contacts permission not granted.")
                if !granted { Foundation.exit(2) }
            case ["contacts", "count"]:
                print("{\"count\": \(try store.count())}")
            case ["contacts", "container"]:
                let container = try store.icloudContainer()
                print("{\"name\":\"\(container.name)\",\"identifier\":\"\(container.identifier)\"}")
            case ["contacts", "container", "--format", "json"]:
                let container = try store.icloudContainer()
                emitJSONSuccess(["name": container.name, "identifier": container.identifier])
            case ["contacts", "export"]:
                emitJSONSuccess(try store.list())
            case let args where args.count == 6 && args[0] == "contacts" && args[1] == "export" && args[2] == "--format" && args[3] == "json" && args[4] == "--output":
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(store.list()).write(to: URL(fileURLWithPath: args[5]), options: .atomic)
                print("Contacts exported.")
            case ["contacts", "list"], ["contacts", "list", "--format", "json"]:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if jsonRequested { emitJSONSuccess(try store.list()) } else { print(String(data: try encoder.encode(store.list()), encoding: .utf8)!) }
            case let args where (args.count == 4 || args.count == 6) &&
                args[0] == "contacts" && args[1] == "get" && args[2] == "--external-id" &&
                (args.count == 4 || (args[4] == "--format" && args[5] == "json")):
                let externalID = args[3]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if args.count == 6 { emitJSONSuccess(try store.get(externalID: externalID)) } else { print(String(data: try encoder.encode(store.get(externalID: externalID)), encoding: .utf8)!) }
            case let args where args.count >= 4 && args[0] == "contacts" && args[1] == "query":
                let query = try parseQuerySet(Array(args.dropFirst(2)))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                emitJSONSuccess(try store.query(query))
            case let args where args.count == 5 && args[0] == "contacts" && args[1] == "create":
                let inputPath: String
                let mode: String
                if args[2] == "--input" {
                    inputPath = args[3]
                    mode = args[4]
                } else {
                    mode = args[2]
                    inputPath = args[4]
                }
                guard (mode == "--dry-run" || mode == "--apply") && !inputPath.isEmpty else {
                    fputs("error: create requires exactly --dry-run or --apply, plus --input <file>\n", stderr)
                    Foundation.exit(64)
                }
                let payload = try JSONDecoder().decode(ContactPayload.self, from: Data(contentsOf: URL(fileURLWithPath: inputPath)))
                guard payload.externalID != nil else { throw ContactsError.invalidInput("external_id is required") }
                if mode == "--dry-run" {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let preview = ContactsMapper().map(ContactsMapper().makeMutableContact(from: payload))
                    if jsonRequested { emitJSONSuccess(preview) } else { print(String(data: try encoder.encode(preview), encoding: .utf8)!) }
                } else {
                    try store.create(payload)
                    if jsonRequested { emitJSONSuccess(["message": "Contact created."]) } else { print("Contact created.") }
                }
            case let args where args.count == 7 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && args[4] == "--input":
                let externalID = args[3]
                let patch = try JSONDecoder().decode(ContactPatch.self, from: Data(contentsOf: URL(fileURLWithPath: args[5])))
                guard args[6] == "--dry-run" || args[6] == "--apply" else { throw ContactsError.invalidInput("edit requires --dry-run or --apply") }
                if args[6] == "--apply" { try store.update(externalID: externalID, with: patch); if jsonRequested { emitJSONSuccess(["message": "Contact updated."]) } else { print("Contact updated.") } }
                else { let before = try store.get(externalID: externalID); let mutable = ContactsMapper().makeMutableContact(from: before); try ContactsMapper().update(mutable, from: patch, preservingExternalID: externalID); let after = ContactsMapper().map(mutable); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(data: try encoder.encode(["before": before, "after": after]), encoding: .utf8)!) }
            case let args where args.count == 7 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && args[4] == "--image":
                let externalID = args[3]
                let imagePath = args[5]
                guard args[6] == "--dry-run" || args[6] == "--apply" else { throw ContactsError.invalidInput("image edit requires --dry-run or --apply") }
                let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                guard !imageData.isEmpty else { throw ContactsError.invalidInput("image file is empty") }
                let processed = try ContactImageProcessor().process(imageData)
                if args[6] == "--apply" { try store.updateImage(externalID: externalID, data: imageData); if jsonRequested { emitJSONSuccess(["message": "Contact image updated."]) } else { print("Contact image updated.") } }
                else { print("{\"externalID\":\"\(externalID)\",\"imagePath\":\"\(imagePath)\",\"originalBytes\":\(imageData.count),\"finalBytes\":\(processed.data.count),\"width\":\(processed.width),\"height\":\(processed.height),\"compressed\":\(processed.wasCompressed),\"dryRun\":true}") }
            case let args where args.count >= 4 &&
                args[0] == "contacts" && args[1] == "delete" && args[2] == "--external-id":
                let externalID = args[3]
                let isApply = args.count == 7 && args[4] == "--apply" && args[5] == "--confirm" && args[6] == "DELETE CONTACT"
                guard (args.count == 5 && args[4] == "--dry-run") || isApply else { throw ContactsError.invalidInput("delete requires --dry-run or --apply --confirm \"DELETE CONTACT\"") }
                if isApply { try store.delete(externalID: externalID); if jsonRequested { emitJSONSuccess(["message": "Contact deleted."]) } else { print("Contact deleted.") } }
                else { let preview = try store.get(externalID: externalID); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; if jsonRequested { emitJSONSuccess(preview) } else { print(String(data: try encoder.encode(preview), encoding: .utf8)!) } }
            case let args where args.count >= 7 &&
                args[0] == "contacts" && args[1] == "external-id" && args[2] == "migrate" &&
                args[3] == "--from" && args[5] == "--to":
                let oldID = args[4], newID = args[6]
                let isApply = args.count == 10 && args[7] == "--apply" && args[8] == "--confirm" && args[9] == "CHANGE EXTERNAL ID"
                guard (args.count == 8 && args[7] == "--dry-run") || isApply else { throw ContactsError.externalIDMigrationConfirmationRequired }
                if isApply { try store.migrateExternalID(from: oldID, to: newID); if jsonRequested { emitJSONSuccess(MigrationPreview(from: oldID, to: newID, dryRun: false, message: "External ID migrated.")) } else { print("External ID migrated.") } }
                else { if jsonRequested { emitJSONSuccess(MigrationPreview(from: oldID, to: newID, dryRun: true, message: nil)) } else { print("{\"from\":\"\(oldID)\",\"to\":\"\(newID)\",\"dryRun\":true}") } }
            default:
                fputs("error: unknown command\n", stderr)
                Foundation.exit(64)
            }
        } catch let error as ContactsError {
            report(error: error.description, code: "CONTACTS_ERROR", arguments: rawArguments, exitCode: 2)
            Foundation.exit(2)
        } catch let error as ContactsQueryError {
            report(error: error.description, code: "CONTACT_QUERY_ERROR", arguments: rawArguments, exitCode: 3)
            Foundation.exit(3)
        } catch let error as ContactQuerySetError {
            report(error: error.description, code: "INVALID_QUERY", arguments: rawArguments, exitCode: 64)
            Foundation.exit(64)
        } catch {
            report(error: error.localizedDescription, code: "CLI_ERROR", arguments: rawArguments, exitCode: 1)
            Foundation.exit(1)
        }
    }

    private static func report(error: String, code: String, arguments: [String], exitCode: Int32) {
        DiagnosticLogger.record(code: code, message: error)
        if arguments.contains("--format") && arguments.contains("json") {
            let response: [String: Any] = ["ok": false, "error": ["code": code, "message": error]]
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { fputs(text + "\n", stderr) }
        } else {
            fputs("error: \(error)\n", stderr)
        }
    }

    private struct JSONSuccess<T: Encodable>: Encodable { let ok = true; let data: T }
    private struct MigrationPreview: Encodable { let from: String; let to: String; let dryRun: Bool; let message: String? }

    private static func emitJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) { print(text) }
    }

    private static func parseQuerySet(_ arguments: [String]) throws -> ContactQuerySet {
        var conditions: [ContactQuery] = []
        var fields = Set<String>()
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--format" {
                guard index + 1 < arguments.count, arguments[index + 1] == "json" else { throw ContactQuerySetError.invalidConditionCount }
                index += 2
                continue
            }
            guard index + 1 < arguments.count else { throw ContactQuerySetError.invalidConditionCount }
            let field = arguments[index]
            guard fields.insert(field).inserted else { throw ContactQuerySetError.duplicateField }
            let value = arguments[index + 1]
            switch field {
            case "--name": conditions.append(.name(value))
            case "--phone": conditions.append(.phone(value))
            case "--email": conditions.append(.email(value))
            case "--url": conditions.append(.url(value))
            case "--organization": conditions.append(.organization(value))
            case "--postal-code": conditions.append(.postalCode(value))
            default: throw ContactQuerySetError.invalidConditionCount
            }
            index += 2
        }
        return try ContactQuerySet(conditions)
    }

    private static func printHelp() {
        print("""
        macos-data 0.1.6 — local macOS data CLI for agents and developers

        Usage:
          macos-data --version | -v
          macos-data contacts <command> [options]

        Contacts commands:
          permission                         Check/request Contacts permission
          container                          Show the required iCloud container
          count                              Count contacts
          list [--format json]              List contacts
          get --external-id <id> [--format json]
                                             Read one contact
          query [conditions] --format json  Search contacts (max 3 AND conditions)
          create --input <file> --dry-run|--apply
                                             Create a person or organization
          edit --external-id <id> --input <file> --dry-run|--apply
                                             Partial update; null clears a field
          edit --external-id <id> --image <file> --dry-run|--apply
                                             Set a normalized avatar
          delete --external-id <id> --dry-run
          delete --external-id <id> --apply --confirm "DELETE CONTACT"
                                             Delete one contact
          external-id migrate --from <id> --to <id> --dry-run
          external-id migrate --from <id> --to <id> --apply
            --confirm "CHANGE EXTERNAL ID"
                                             Migrate an external ID
          export --format json [--output <file>]
                                             Export a JSON snapshot

        JSON contract:
          Success: {"ok": true, "data": ...}
          Failure: {"ok": false, "error": {"code": ..., "message": ...}}
          Add --format json to commands that support machine-readable output.

        Safety and limits:
          Writes target only the iCloud Contacts container in 0.1.6.
          Writes require --dry-run or explicit --apply.
          Avatar input is limited to 10 MB; output is <= 1024 px and 200 KB.
          metadata remains in JSON and is not written to Apple Contacts.
        """)
    }
}
