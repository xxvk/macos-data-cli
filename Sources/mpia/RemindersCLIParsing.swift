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
    static func parseReminderQuery(_ arguments: [String]) throws -> ReminderQuery {
        var status = ReminderQueryStatus.incomplete
        var dueStart: Date?
        var dueEnd: Date?
        var listID: String?
        var title: String?
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        let supported = ["--status", "--due-start", "--due-end", "--list", "--title", "--limit", "--cursor"]

        while index < arguments.count {
            let option = arguments[index]
            guard supported.contains(option), seen.insert(option).inserted, index + 1 < arguments.count else {
                throw ReminderError.invalidInput("reminders query accepts --status, --due-start, --due-end, --list, --title, --limit, and --cursor")
            }
            let value = arguments[index + 1]
            switch option {
            case "--status":
                guard let parsed = ReminderQueryStatus(rawValue: value) else {
                    throw ReminderError.invalidInput("--status requires incomplete, completed, or all")
                }
                status = parsed
            case "--due-start": dueStart = try parseReminderDate(value, option: option)
            case "--due-end": dueEnd = try parseReminderDate(value, option: option)
            case "--list": listID = value
            case "--title": title = value
            case "--limit":
                guard let parsed = Int(value) else { throw ReminderError.invalidInput("--limit requires an integer") }
                limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }

        return try ReminderQuery(
            status: status,
            dueStart: dueStart,
            dueEnd: dueEnd,
            listID: listID,
            title: title,
            limit: limit,
            cursor: cursor
        )
    }

    struct ReminderCreateArguments {
        let data: Data
        let mode: String
        let idempotent: Bool
    }

    static func parseReminderCreateArguments(_ arguments: [String]) throws -> ReminderCreateArguments {
        var inputData: Data?
        var mode: String?
        var idempotent = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--inline-json":
                guard inputData == nil, index + 1 < arguments.count else {
                    throw ReminderError.invalidInput("create accepts exactly one JSON body")
                }
                inputData = Data(arguments[index + 1].utf8)
                index += 2
            case "--dry-run", "--apply":
                guard mode == nil else {
                    throw ReminderError.invalidInput("create accepts exactly one of --dry-run or --apply")
                }
                mode = arguments[index]
                index += 1
            case "--idempotent":
                guard !idempotent else { throw ReminderError.invalidInput("--idempotent may be specified once") }
                idempotent = true
                index += 1
            default:
                throw ReminderError.invalidInput("unsupported create option")
            }
        }
        guard let data = inputData, let mode else {
            throw ReminderError.invalidInput("create requires --body and --dry-run or --apply")
        }
        guard !data.isEmpty else { throw ReminderError.invalidInput("create JSON input is empty") }
        return ReminderCreateArguments(data: data, mode: mode, idempotent: idempotent)
    }

    static func decodeReminder<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(T.self, from: data) }
        catch { throw ReminderError.invalidInput("JSON does not match the Reminders contract") }
    }

    struct ReminderEditArguments {
        let data: Data
        let mode: String
    }

    static func parseReminderEditArguments(_ arguments: [String]) throws -> ReminderEditArguments {
        var inputData: Data?
        var mode: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--inline-json":
                guard inputData == nil, index + 1 < arguments.count else {
                    throw ReminderError.invalidInput("edit accepts exactly one JSON body")
                }
                inputData = Data(arguments[index + 1].utf8)
                index += 2
            case "--dry-run", "--apply":
                guard mode == nil else {
                    throw ReminderError.invalidInput("edit accepts exactly one of --dry-run or --apply")
                }
                mode = arguments[index]
                index += 1
            default:
                throw ReminderError.invalidInput("unsupported edit option")
            }
        }
        guard let data = inputData, let mode else {
            throw ReminderError.invalidInput("edit requires --body and --dry-run or --apply")
        }
        guard !data.isEmpty else { throw ReminderError.invalidInput("edit JSON input is empty") }
        return ReminderEditArguments(data: data, mode: mode)
    }

    static func parseReminderDeleteArguments(_ arguments: [String]) throws -> Bool {
        if arguments == ["--dry-run"] { return false }
        if arguments == ["--apply", "--confirm", "DELETE REMINDER"] { return true }
        throw ReminderError.invalidInput("delete requires --dry-run or --apply --confirm \"DELETE REMINDER\"")
    }

    static func parseReminderStateArguments(_ arguments: [String], command: String) throws -> Bool {
        if arguments == ["--dry-run"] { return false }
        if arguments == ["--apply"] { return true }
        throw ReminderError.invalidInput("\(command) requires exactly one of --dry-run or --apply")
    }

    static func parseReminderDate(_ value: String, option: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw ReminderError.invalidInput("\(option) requires an ISO 8601 timestamp with an explicit offset")
        }
        return date
    }

}
