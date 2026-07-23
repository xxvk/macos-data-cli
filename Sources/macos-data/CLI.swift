import Foundation
import Core
import Contacts
import ContactsAdapter
import MailAdapter

@main
struct MacosDataCLI {
    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let jsonRequested = rawArguments.contains("--format") && rawArguments.contains("json")
        var arguments = rawArguments.filter { $0 != "--format" && $0 != "json" }
        var containerSelector: String?
        if let index = arguments.firstIndex(of: "--container") {
            guard index + 1 < arguments.count else {
                report(error: "--container requires iCloud or a container identifier", code: CLIErrorCode.invalidQuery.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            containerSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        if arguments.isEmpty || arguments == ["--help"] || arguments == ["contacts", "--help"] || arguments == ["mail", "--help"] {
            printHelp()
            return
        }

        if arguments == ["--version"] || arguments == ["-v"] {
            print(CLIVersion.current)
            return
        }

        do {
            let permission = ContactsPermission()
            let store = ContactsStore(permission: permission, containerSelector: containerSelector)
            switch arguments {
            case ["resources"]:
                emitJSONSuccess(makeResourcesResult(permission: permission, store: store))
            case ["mail", "doctor"]:
                emitJSONSuccess(MailDoctor().run())
            case ["mail", "accounts"]:
                emitJSONSuccess(try makeValidatedMailStore().accounts())
            case ["mail", "mailboxes"]:
                emitJSONSuccess(try makeValidatedMailStore().mailboxes())
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "threads":
                emitJSONSuccess(try makeValidatedMailStore().threads(limit: parseSimpleLimit(Array(args.dropFirst(2)))))
            case let args where args.count == 4 && args[0] == "mail" && args[1] == "mailboxes" && args[2] == "--account-id":
                emitJSONSuccess(try makeValidatedMailStore().mailboxes(accountID: args[3]))
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "query":
                emitJSONSuccess(try makeValidatedMailStore().query(parseMailQuery(Array(args.dropFirst(2)))))
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "search":
                let request = try parseMailTextSearch(Array(args.dropFirst(2)))
                emitJSONSuccess(try makeValidatedMailStore().searchText(request.text, query: request.query, resultLimit: request.limit))
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "get":
                let request = try parseMailGet(Array(args.dropFirst(2)), jsonRequested: jsonRequested)
                let mailStore = try makeValidatedMailStore()
                if request.projection == .raw {
                    let raw = try mailStore.rawMessage(id: request.id)
                    if request.output == "-" {
                        do { try FileHandle.standardOutput.write(contentsOf: raw.data) }
                        catch { throw MailStoreError.outputFailed }
                    } else {
                        guard let output = request.output else {
                            throw MailStoreError.invalidArgument("Raw content requires --output <file|->.")
                        }
                        do {
                            try raw.data.write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
                        } catch let error as CocoaError where error.code == .fileWriteFileExists {
                            throw MailStoreError.outputAlreadyExists
                        } catch {
                            throw MailStoreError.outputFailed
                        }
                        emitJSONSuccess(MailRawWriteResult(
                            backend: "sqlite_emlx",
                            cacheState: raw.cacheState,
                            id: raw.message.id,
                            output: "file",
                            bytesWritten: raw.data.count,
                            fallbackReason: raw.incomplete ? "partial_emlx" : nil,
                            incomplete: raw.incomplete,
                            limitations: raw.limitations
                        ))
                    }
                } else {
                    emitJSONSuccess(try mailStore.get(id: request.id, projection: request.projection))
                }
            case let args where args.count == 4 && args[0] == "mail" && args[1] == "reveal" && args[2] == "--id":
                emitJSONSuccess(try makeValidatedMailStore().reveal(id: args[3]))
            case let args where args.count == 5 && args[0] == "mail" && args[1] == "attachments" &&
                args[2] == "verify" && args[3] == "--id":
                emitJSONSuccess(try makeValidatedMailStore().verifyAttachments(id: args[4]))
            case let args where args.count == 7 && args[0] == "mail" && args[1] == "attachments" &&
                args[2] == "export" && args[3] == "--id" && args[5] == "--output":
                emitJSONSuccess(try makeValidatedMailStore().exportAttachments(id: args[4], directory: URL(fileURLWithPath: args[6])))
            case ["contacts", "permission"]:
                let granted = try await permission.requestAccess()
                print(granted ? "Contacts permission granted." : "Contacts permission not granted.")
                if !granted { Foundation.exit(2) }
            case ["contacts", "count"]:
                if jsonRequested { emitJSONSuccess(["count": try store.count()]) }
                else { print("{\"count\": \(try store.count())}") }
            case ["contacts", "containers"], ["contacts", "containers", "--format", "json"]:
                emitJSONSuccess(try store.containerDescriptions())
            case ["contacts", "container"]:
                let container = try store.selectedContainerDescription()
                if jsonRequested {
                    emitJSONSuccess(container)
                } else {
                    print("{\"name\":\"\(container.name)\",\"identifier\":\"\(container.identifier)\",\"type\":\"\(container.type)\",\"isICloud\":\(container.isICloud) }")
                }
            case ["contacts", "export"]:
                emitJSONSuccess(try store.list())
            case let args where args.count == 4 && args[0] == "contacts" && args[1] == "export" && args[2] == "--output":
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(store.list()).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
                if jsonRequested { emitJSONSuccess(["message": "Contacts exported.", "output": args[3]]) }
                else { print("Contacts exported.") }
            case let args where args.count >= 2 && args[0] == "contacts" && args[1] == "list":
                let pagination = try parseContactPagination(Array(args.dropFirst(2)))
                emitJSONSuccess(try store.listPage(limit: pagination.limit, cursor: pagination.cursor))
            case let args where (args.count == 4 || args.count == 6) &&
                args[0] == "contacts" && args[1] == "get" && args[2] == "--external-id" &&
                (args.count == 4 || (args[4] == "--format" && args[5] == "json")):
                let externalID = args[3]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if args.count == 6 { emitJSONSuccess(try store.get(externalID: externalID)) } else { print(String(data: try encoder.encode(store.get(externalID: externalID)), encoding: .utf8)!) }
            case let args where args.count == 5 && args[0] == "contacts" && args[1] == "avatar" && args[2] == "verify" && args[3] == "--external-id":
                let verification = try store.verifyImage(externalID: args[4])
                if jsonRequested { emitJSONSuccess(verification) }
                else {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    print(String(data: try encoder.encode(verification), encoding: .utf8)!)
                }
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
                    let preview: [String: Any] = ["externalID": externalID, "originalBytes": imageData.count, "finalBytes": processed.data.count, "width": processed.width, "height": processed.height, "dryRun": true, "operation": "avatar_replace"]
                    if let data = try? JSONSerialization.data(withJSONObject: preview, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
                } else {
                    let verification = try store.replaceImage(externalID: externalID, data: imageData)
                    if jsonRequested { emitJSONSuccess(ContactImageWriteResult(operation: "avatar_replaced", contact: try store.get(externalID: externalID), avatar: verification)) } else { print("Contact avatar replaced (\(verification.status.rawValue)).") }
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
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let preview = ContactsMapper().map(ContactsMapper().makeMutableContact(from: payload))
                    if jsonRequested { emitJSONSuccess(preview) } else { print(String(data: try encoder.encode(preview), encoding: .utf8)!) }
                } else {
                    let existing: ContactPayload?
                    do { existing = try store.get(externalID: payload.externalID!) }
                    catch ContactsQueryError.notFound { existing = nil }
                    if let existing {
                        guard idempotent else { throw ContactsError.duplicateExternalID(payload.externalID!) }
                        guard payload.isEquivalentForIdempotentCreate(to: existing) else { throw ContactsError.idempotencyConflict(payload.externalID!) }
                        if jsonRequested { emitJSONSuccess(ContactWriteResult(operation: "already_exists", contact: existing)) } else { print("Contact already exists.") }
                    } else {
                        try store.create(payload)
                        if jsonRequested { emitJSONSuccess(ContactWriteResult(operation: "created", contact: try store.get(externalID: payload.externalID!))) } else { print("Contact created.") }
                    }
                }
            case let args where args.count >= 6 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && (args.contains("--input") || args.contains("--stdin")):
                let externalID = args[3]
                let (inputData, mode, idempotent) = try parseJSONWriteArguments(Array(args.dropFirst(4)), command: "edit")
                guard !idempotent else { throw ContactsError.invalidInput("--idempotent is supported only by create") }
                let patch = try JSONDecoder().decode(ContactPatch.self, from: inputData)
                if mode == "--apply" { try store.update(externalID: externalID, with: patch); if jsonRequested { emitJSONSuccess(ContactWriteResult(operation: "updated", contact: try store.get(externalID: externalID))) } else { print("Contact updated.") } }
                else { let before = try store.get(externalID: externalID); let mutable = ContactsMapper().makeMutableContact(from: before); try ContactsMapper().update(mutable, from: patch, preservingExternalID: externalID); var after = ContactsMapper().map(mutable); after.imageAvailable = before.imageAvailable; let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(data: try encoder.encode(["before": before, "after": after]), encoding: .utf8)!) }
            case let args where args.count == 7 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && args[4] == "--image":
                let externalID = args[3]
                let imagePath = args[5]
                guard args[6] == "--dry-run" || args[6] == "--apply" else { throw ContactsError.invalidInput("image edit requires --dry-run or --apply") }
                let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                guard !imageData.isEmpty else { throw ContactsError.invalidInput("image file is empty") }
                let processed = try ContactImageProcessor().process(imageData)
                if args[6] == "--apply" { let verification = try store.updateImage(externalID: externalID, data: imageData); if jsonRequested { emitJSONSuccess(ContactImageWriteResult(operation: "image_updated", contact: try store.get(externalID: externalID), avatar: verification)) } else { print("Contact image updated (\(verification.status.rawValue)).") } }
                else { print("{\"externalID\":\"\(externalID)\",\"imagePath\":\"\(imagePath)\",\"originalBytes\":\(imageData.count),\"finalBytes\":\(processed.data.count),\"width\":\(processed.width),\"height\":\(processed.height),\"compressed\":\(processed.wasCompressed),\"dryRun\":true}") }
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
                        if jsonRequested { emitJSONSuccess(ContactDeleteResult(contact: deleted)) } else { print("Contact deleted.") }
                    } catch ContactsQueryError.notFound where ignoreNotFound {
                        if jsonRequested { emitJSONSuccess(ContactAlreadyDeletedResult(externalID: externalID)) } else { print("Contact already deleted.") }
                    }
                }
                else { let preview = try store.get(externalID: externalID); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; if jsonRequested { emitJSONSuccess(preview) } else { print(String(data: try encoder.encode(preview), encoding: .utf8)!) } }
            case let args where args.count >= 7 &&
                args[0] == "contacts" && args[1] == "external-id" && args[2] == "migrate" &&
                args[3] == "--from" && args[5] == "--to":
                let oldID = args[4], newID = args[6]
                let isApply = args.count == 10 && args[7] == "--apply" && args[8] == "--confirm" && args[9] == "CHANGE EXTERNAL ID"
                guard (args.count == 8 && args[7] == "--dry-run") || isApply else { throw ContactsError.externalIDMigrationConfirmationRequired }
                if isApply { try store.migrateExternalID(from: oldID, to: newID); if jsonRequested { emitJSONSuccess(MigrationResult(from: oldID, to: newID, contact: try store.get(externalID: newID))) } else { print("External ID migrated.") } }
                else { if jsonRequested { emitJSONSuccess(MigrationPreview(from: oldID, to: newID, dryRun: true, message: nil)) } else { print("{\"from\":\"\(oldID)\",\"to\":\"\(newID)\",\"dryRun\":true}") } }
            default:
                report(error: "unknown command or invalid arguments", code: CLIErrorCode.invalidQuery.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
        } catch let error as ContactsError {
            report(error: error.description, code: CLIErrorCode.contacts.rawValue, arguments: rawArguments, exitCode: CLIExitCode.contactsFailure.rawValue)
            Foundation.exit(CLIExitCode.contactsFailure.rawValue)
        } catch let error as ContactsQueryError {
            report(error: error.description, code: CLIErrorCode.query.rawValue, arguments: rawArguments, exitCode: CLIExitCode.queryFailure.rawValue)
            Foundation.exit(CLIExitCode.queryFailure.rawValue)
        } catch let error as ContactQuerySetError {
            report(error: error.description, code: CLIErrorCode.invalidQuery.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
            Foundation.exit(CLIExitCode.usage.rawValue)
        } catch let error as MailStoreError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.mailFailure.rawValue)
            Foundation.exit(CLIExitCode.mailFailure.rawValue)
        } catch {
            report(error: error.localizedDescription, code: CLIErrorCode.cli.rawValue, arguments: rawArguments, exitCode: CLIExitCode.genericFailure.rawValue)
            Foundation.exit(CLIExitCode.genericFailure.rawValue)
        }
    }

    private static func report(error: String, code: String, arguments: [String], exitCode: Int32) {
        DiagnosticLogger.record(code: code, message: error)
        if arguments.contains("--format") && arguments.contains("json") {
            let response: [String: Any] = ["ok": false, "contractVersion": JSONContract.version, "error": ["code": code, "message": error]]
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { fputs(text + "\n", stderr) }
        } else {
            fputs("error: \(error)\n", stderr)
        }
    }

    private struct JSONSuccess<T: Encodable>: Encodable { let ok = true; let contractVersion = JSONContract.version; let data: T }
    private struct ContactWriteResult: Encodable { let operation: String; let contact: ContactPayload }
    private struct ContactImageWriteResult: Encodable { let operation: String; let contact: ContactPayload; let avatar: AvatarWriteVerification }
    private struct ContactDeleteResult: Encodable { let operation = "deleted"; let contact: ContactPayload }
    private struct ContactAlreadyDeletedResult: Encodable { let operation = "already_deleted"; let externalID: String }
    private struct MigrationPreview: Encodable { let from: String; let to: String; let dryRun: Bool; let message: String? }
    private struct MigrationResult: Encodable { let from: String; let to: String; let contact: ContactPayload }

    private static func emitJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) { print(text) }
    }

    private static func parseJSONWriteArguments(_ arguments: [String], command: String) throws -> (Data, String, Bool) {
        var inputSource: String?
        var mode: String?
        var idempotent = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--input":
                guard inputSource == nil, index + 1 < arguments.count else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one JSON source")
                }
                inputSource = arguments[index + 1]
                index += 2
            case "--stdin":
                guard inputSource == nil else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one JSON source")
                }
                inputSource = "-"
                index += 1
            case "--dry-run", "--apply":
                guard mode == nil else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one of --dry-run or --apply")
                }
                mode = arguments[index]
                index += 1
            case "--idempotent":
                guard command == "create", !idempotent else {
                    throw ContactsError.invalidInput("--idempotent is supported only by create")
                }
                idempotent = true
                index += 1
            default:
                throw ContactsError.invalidInput("unsupported \(command) option: \(arguments[index])")
            }
        }

        guard let inputSource, let mode else {
            throw ContactsError.invalidInput("\(command) requires JSON input (--input <file> or --stdin) and --dry-run or --apply")
        }

        let data: Data
        if inputSource == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            data = try Data(contentsOf: URL(fileURLWithPath: inputSource))
        }
        guard !data.isEmpty else {
            throw ContactsError.invalidInput("\(command) JSON input is empty")
        }
        return (data, mode, idempotent)
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
            case "--kind":
                guard let kind = ContactKind(rawValue: value.lowercased()) else { throw ContactQuerySetError.invalidConditionCount }
                conditions.append(.kind(kind))
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

    private struct ContactPaginationArguments {
        let conditions: [String]
        let limit: Int
        let cursor: String?
    }

    private static func parseContactPagination(_ arguments: [String]) throws -> ContactPaginationArguments {
        var conditions: [String] = []
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seenLimit = false
        var seenCursor = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--limit":
                guard !seenLimit, index + 1 < arguments.count, let parsed = Int(arguments[index + 1]) else {
                    throw ContactsQueryError.invalidLimit
                }
                limit = parsed
                seenLimit = true
                index += 2
            case "--cursor":
                guard !seenCursor, index + 1 < arguments.count else {
                    throw ContactsQueryError.invalidCursor
                }
                cursor = arguments[index + 1]
                seenCursor = true
                index += 2
            default:
                conditions.append(arguments[index])
                index += 1
            }
        }

        guard (1...Pagination.maximumLimit).contains(limit) else {
            throw ContactsQueryError.invalidLimit
        }
        return ContactPaginationArguments(conditions: conditions, limit: limit, cursor: cursor)
    }

    private enum ValidatedMailStore {
        case sqlite(SQLiteMailStore)
        case mailApp(MailAppMetadataStore)

        func accounts() throws -> MailAccountListResult {
            switch self {
            case .sqlite(let store): MailAccountListResult(accounts: try store.accounts())
            case .mailApp(let store): try store.accounts()
            }
        }

        func mailboxes(accountID: String? = nil) throws -> MailboxListResult {
            switch self {
            case .sqlite(let store): MailboxListResult(mailboxes: try store.mailboxes(accountID: accountID))
            case .mailApp(let store): try store.mailboxes(accountID: accountID)
            }
        }

        func threads(limit: Int) throws -> MailThreadListResult {
            switch self {
            case .sqlite(let store): try store.threads(limit: limit)
            case .mailApp: throw MailStoreError.invalidArgument("Mail threads require the recognized SQLite fast path.")
            }
        }

        func query(_ query: MailQuery) throws -> MailQueryResult {
            switch self {
            case .sqlite(let store): try store.query(query)
            case .mailApp(let store): try store.query(query)
            }
        }

        func searchText(_ text: String, query: MailQuery, resultLimit: Int) throws -> MailTextSearchResult {
            switch self {
            case .sqlite(let store): try store.searchText(text, query: query, resultLimit: resultLimit)
            case .mailApp: throw MailStoreError.invalidArgument("Mail text search requires the recognized SQLite/EMLX fast path; it never falls back to Mail.app.")
            }
        }

        func get(id: String, projection: MailContentProjection) throws -> MailGetResult {
            switch self {
            case .sqlite(let store): try store.get(id: id, projection: projection)
            case .mailApp(let store): try store.get(id: id, projection: projection)
            }
        }

        func rawMessage(id: String) throws -> MailRawMessage {
            switch self {
            case .sqlite(let store): try store.rawMessage(id: id)
            case .mailApp: throw MailStoreError.contentNotCached
            }
        }

        func reveal(id: String) throws -> MailRevealResult {
            switch self {
            case .sqlite(let store): try store.reveal(id: id)
            case .mailApp(let store): try store.reveal(id: id)
            }
        }

        func verifyAttachments(id: String) throws -> MailAttachmentVerificationResult {
            switch self {
            case .sqlite(let store): try store.verifyAttachments(id: id)
            case .mailApp:
                throw MailStoreError.invalidArgument("Attachment verification requires the recognized SQLite/EMLX fast path.")
            }
        }

        func exportAttachments(id: String, directory: URL) throws -> MailAttachmentExportResult {
            switch self {
            case .sqlite(let store): try store.exportAttachments(id: id, to: directory)
            case .mailApp: throw MailStoreError.invalidArgument("Attachment export requires the recognized SQLite/EMLX fast path.")
            }
        }
    }

    private static func makeValidatedMailStore() throws -> ValidatedMailStore {
        let report = MailDoctor(databaseProbe: SQLiteMailDatabaseProbe(performQuickCheck: false)).run()
        let forceMailApp = ProcessInfo.processInfo.environment["MACOS_DATA_MAIL_FORCE_APP_FALLBACK"] == "1"
        switch MailBackendSelector.select(report: report, forceMailAppFallback: forceMailApp) {
        case .sqlite:
            return .sqlite(SQLiteMailStore(databaseURL: try MailStoreLocator().locate().databaseURL))
        case .mailApp(let reason):
            return .mailApp(MailAppMetadataStore(fallbackReason: reason))
        case .unavailable(let error):
            throw error
        }
    }

    private static func makeResourcesResult(
        permission: ContactsPermission,
        store: ContactsStore
    ) -> DataResourcesResult {
        var resources: [DataResource] = []
        var limitations: [String] = []

        switch permission.status {
        case .authorized, .limited:
            do {
                let containers = try store.containerDescriptions()
                let selectedID = try store.selectedContainerDescription().identifier
                resources.append(contentsOf: containers.map { container in
                    ContactsResourceMapper.map(container, selected: container.identifier == selectedID)
                })
            } catch {
                limitations.append("contacts_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("contacts_permission_not_determined")
        case .denied:
            limitations.append("contacts_permission_denied")
        case .restricted:
            limitations.append("contacts_permission_restricted")
        }

        do {
            let mailAccounts = try makeValidatedMailStore().accounts()
            resources.append(contentsOf: mailAccounts.accounts.map { account in
                MailResourceMapper.map(account, selected: false)
            })
            limitations.append(contentsOf: mailAccounts.limitations)
            if !mailAccounts.accounts.isEmpty {
                limitations.append("mail_preferred_aim_tech_account_requires_explicit_verification")
            }
        } catch {
            limitations.append("mail_resource_discovery_unavailable")
        }

        limitations.append("calendar_adapter_not_implemented")
        return DataResourcesResult(resources: resources, limitations: limitations)
    }

    private static func parseMailQuery(_ arguments: [String]) throws -> MailQuery {
        var query = MailQuery()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else {
                throw MailStoreError.invalidArgument("Duplicate Mail query option: \(option)")
            }
            switch option {
            case "--unread": query.unread = true; index += 1
            case "--flagged": query.flagged = true; index += 1
            case "--has-attachment": query.hasAttachment = true; index += 1
            case "--account-id", "--mailbox-id", "--from", "--to", "--subject", "--received-after", "--received-before", "--limit", "--cursor":
                guard index + 1 < arguments.count else {
                    throw MailStoreError.invalidArgument("Mail query option requires a value: \(option)")
                }
                let value = arguments[index + 1]
                switch option {
                case "--account-id": query.accountID = value
                case "--mailbox-id": query.mailboxID = value
                case "--from": query.from = value
                case "--to": query.to = value
                case "--subject": query.subject = value
                case "--received-after": query.receivedAfter = try parseMailDate(value, option: option)
                case "--received-before": query.receivedBefore = try parseMailDate(value, option: option)
                case "--limit":
                    guard let limit = Int(value) else { throw MailStoreError.invalidArgument("--limit requires an integer") }
                    query.limit = limit
                case "--cursor": query.cursor = value
                default: break
                }
                index += 2
            default:
                throw MailStoreError.invalidArgument("Unsupported Mail query option: \(option)")
            }
        }
        return query
    }

    private static func parseMailTextSearch(_ arguments: [String]) throws -> (text: String, query: MailQuery, limit: Int) {
        var text: String?
        var limit = 50
        var queryArguments: [String] = []
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--text":
                guard text == nil, index + 1 < arguments.count else { throw MailStoreError.invalidArgument("Mail text search accepts one --text value.") }
                text = arguments[index + 1]
                index += 2
            case "--limit":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else { throw MailStoreError.invalidLimit }
                limit = value
                index += 2
            default:
                queryArguments.append(arguments[index])
                index += 1
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MailStoreError.invalidArgument("Mail text search requires --text <value>.")
        }
        guard (1...200).contains(limit) else { throw MailStoreError.invalidLimit }
        return (text, try parseMailQuery(queryArguments), limit)
    }

    private static func parseSimpleLimit(_ arguments: [String]) throws -> Int {
        guard arguments.count == 0 || (arguments.count == 2 && arguments[0] == "--limit"),
              let value = arguments.isEmpty ? 50 : Int(arguments[1]),
              (1...200).contains(value) else { throw MailStoreError.invalidLimit }
        return value
    }

    private static func parseMailDate(_ value: String, option: String) throws -> Date {
        let timestampFormatter = ISO8601DateFormatter()
        if let date = timestampFormatter.date(from: value) { return date }
        let dayFormatter = ISO8601DateFormatter()
        dayFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = dayFormatter.date(from: value) { return date }
        throw MailStoreError.invalidArgument("\(option) requires ISO 8601, for example 2026-07-23 or 2026-07-23T00:00:00Z")
    }

    private struct MailGetArguments {
        let id: String
        let projection: MailContentProjection
        let output: String?
    }

    private static func parseMailGet(_ arguments: [String], jsonRequested: Bool) throws -> MailGetArguments {
        var id: String?
        var projection = MailContentProjection.metadata
        var output: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--content", "--output"].contains(option), seen.insert(option).inserted,
                  index + 1 < arguments.count else {
                throw MailStoreError.invalidArgument("mail get accepts --id, --content metadata|text|raw, and --output <file|->.")
            }
            let value = arguments[index + 1]
            switch option {
            case "--id": id = value
            case "--content":
                guard let parsed = MailContentProjection(rawValue: value) else {
                    throw MailStoreError.invalidArgument("--content requires metadata, text, or raw.")
                }
                projection = parsed
            case "--output": output = value
            default: break
            }
            index += 2
        }
        guard let id, !id.isEmpty else { throw MailStoreError.invalidArgument("mail get requires --id <opaque-local-id>.") }
        if projection == .raw, output == nil {
            throw MailStoreError.invalidArgument("Raw content requires --output <file|->.")
        }
        if projection != .raw, output != nil {
            throw MailStoreError.invalidArgument("--output is valid only with --content raw.")
        }
        if projection == .raw, output == "-", jsonRequested {
            throw MailStoreError.invalidArgument("--output - cannot be combined with --format json.")
        }
        return MailGetArguments(id: id, projection: projection, output: output)
    }

    private static func printHelp() {
        print("""
        macos-data \(CLIVersion.current) — local macOS data CLI for agents and developers

        Usage:
          macos-data --version | -v
          macos-data resources --format json
          macos-data contacts <command> [options]
          macos-data mail <command> [options]

        Unified resources:
          resources --format json                List Contacts and Mail resources
                                             with selection, permission, and limitations
                                             Calendar is reported as not implemented

        Mail commands:
          doctor --format json               Inspect Mail store, schema, and permissions
          accounts --format json             List privacy-safe local account scopes
          mailboxes [--account-id <id>] --format json
                                             List mailboxes and local counts
          threads [--limit <1...200>] --format json
                                             List stable conversation groups
          query [filters] [--limit <n>] [--cursor <cursor>] --format json
                                             Query bounded message metadata
          search --text <text> [filters] [--limit <n>] --format json
                                             Search cached local message bodies
          get --id <id> [--content metadata|text] --format json
                                             Read one message; metadata is default
          get --id <id> --content raw --output <file|->
                                             Export exact cached RFC 822 bytes
          reveal --id <id> --format json     Open one message visibly in Mail.app
          attachments verify --id <id> --format json
                                             Compare SQLite and MIME attachment counts
          attachments export --id <id> --output <directory> --format json
                                             Export cached attachments safely

        Mail query filters:
          --account-id <id> --mailbox-id <id> --from <text> --to <text>
          --subject <text> --received-after <iso8601> --received-before <iso8601>
          --unread --flagged --has-attachment --limit <1...200> --cursor <cursor>

        Mail text search:
          Reads only cached EMLX text, scans at most 200 candidates, and has a
          one-second budget. It never falls back to Mail.app or remote content.

        Contacts commands:
          permission                         Check/request Contacts permission
          containers                        List available Contacts containers
          container                          Show the required iCloud container
          count                              Count contacts
          list [--limit <1...200>] [--cursor <cursor>] --format json
                                             List a bounded page of contacts
          get --external-id <id> [--format json]
                                             Read one contact
          avatar verify --external-id <id> [--format json]
                                             Verify avatar read-back without writing
          avatar replace --external-id <id> --image <file> --dry-run
          avatar replace --external-id <id> --image <file> --apply
            --confirm "RECREATE CONTACT"
                                             Recreate a record with a new avatar
          query [conditions] [--limit <1...200>] [--cursor <cursor>] --format json
                                             Search a bounded contact page (max 3 AND conditions)
                                             Supports --kind person|organization
          create --input <file>|--stdin --dry-run|--apply [--idempotent]
                                             Create a person or organization
          edit --external-id <id> --input <file>|--stdin --dry-run|--apply
                                             Partial update; null clears a field
          edit --external-id <id> --image <file> --dry-run|--apply
                                             Set a normalized avatar
          delete --external-id <id> --dry-run
          delete --external-id <id> --apply --confirm "DELETE CONTACT"
                                             Delete one contact
            [--ignore-not-found]             Make repeated deletion safe
          external-id migrate --from <id> --to <id> --dry-run
          external-id migrate --from <id> --to <id> --apply
            --confirm "CHANGE EXTERNAL ID"
                                             Migrate an external ID
          export --format json [--output <file>]
                                             Export a JSON snapshot

        Container selection:
          Add --container iCloud or --container <container-identifier> to a
          Contacts command. The default is the verified iCloud container.
          For create/edit JSON, use --stdin for one document from stdin, or
          --input <file> for a file.

        JSON contract:
          Version: 0.1 (independent from the CLI release version)
          Exit codes: 0 success, 1 unexpected CLI error, 2 Contacts error,
            3 ambiguous/not-found query error, 4 Mail error,
            64 usage or invalid query
          Success: {"ok": true, "contractVersion": "0.1", "data": ...}
          Failure: {"ok": false, "contractVersion": "0.1", "error": {"code": ..., "message": ...}}
          Add --format json to commands that support machine-readable output.

        Safety and limits:
          Mail.app metadata fallback is limited to 25 message candidates,
            always incomplete, and has no cursor; raw remains cache-only.
          Contacts writes target only the verified iCloud container.
          Writes require --dry-run or explicit --apply.
          Avatar input is limited to 10 MB; output is <= 1024 px and 200 KB.
          metadata remains in JSON and is not written to Apple Contacts.
        """)
    }
}
