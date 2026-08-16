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
    static func parseJSONWriteArguments(_ arguments: [String], command: String) throws -> (Data, String, Bool) {
        var inputData: Data?
        var mode: String?
        var idempotent = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--inline-json":
                guard inputData == nil, index + 1 < arguments.count else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one JSON source")
                }
                inputData = Data(arguments[index + 1].utf8)
                index += 2
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

        guard let data = inputData, let mode else {
            throw ContactsError.invalidInput("\(command) requires --body and --dry-run or --apply")
        }
        guard !data.isEmpty else {
            throw ContactsError.invalidInput("\(command) JSON input is empty")
        }
        return (data, mode, idempotent)
    }

    struct CalendarWriteArguments {
        let data: Data
        let mode: String
        let span: CalendarMutationSpan?
        let idempotent: Bool
    }

    static func parseCalendarWriteArguments(
        _ arguments: [String],
        command: String,
        allowsSpan: Bool
    ) throws -> CalendarWriteArguments {
        var inputData: Data?
        var mode: String?
        var span: CalendarMutationSpan?
        var idempotent = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--inline-json":
                guard inputData == nil, index + 1 < arguments.count else { throw CalendarError.invalidInput("\(command) accepts exactly one JSON body") }
                inputData = Data(arguments[index + 1].utf8)
                index += 2
            case "--dry-run", "--apply":
                guard mode == nil else { throw CalendarError.invalidInput("\(command) accepts exactly one of --dry-run or --apply") }
                mode = arguments[index]
                index += 1
            case "--span":
                guard allowsSpan, span == nil, index + 1 < arguments.count,
                      let value = CalendarMutationSpan(rawValue: arguments[index + 1]) else {
                    throw CalendarError.invalidInput("--span requires this or future")
                }
                span = value
                index += 2
            case "--idempotent":
                guard command == "create", !idempotent else { throw CalendarError.invalidInput("--idempotent is supported only by create") }
                idempotent = true
                index += 1
            default:
                throw CalendarError.invalidInput("unsupported \(command) option: \(arguments[index])")
            }
        }
        guard let data = inputData, let mode else {
            throw CalendarError.invalidInput("\(command) requires --body and --dry-run or --apply")
        }
        guard !data.isEmpty else { throw CalendarError.invalidInput("\(command) JSON input is empty") }
        return CalendarWriteArguments(data: data, mode: mode, span: span, idempotent: idempotent)
    }

    static func parseCalendarDeleteArguments(_ arguments: [String]) throws -> (apply: Bool, span: CalendarMutationSpan?) {
        var apply: Bool?
        var confirmed = false
        var span: CalendarMutationSpan?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--dry-run":
                guard apply == nil else { throw CalendarError.invalidInput("delete accepts exactly one of --dry-run or --apply") }
                apply = false
                index += 1
            case "--apply":
                guard apply == nil else { throw CalendarError.invalidInput("delete accepts exactly one of --dry-run or --apply") }
                apply = true
                index += 1
            case "--confirm":
                guard index + 1 < arguments.count, arguments[index + 1] == "DELETE EVENT" else {
                    throw CalendarError.invalidInput("delete apply requires --confirm \"DELETE EVENT\"")
                }
                confirmed = true
                index += 2
            case "--span":
                guard span == nil, index + 1 < arguments.count, let value = CalendarMutationSpan(rawValue: arguments[index + 1]) else {
                    throw CalendarError.invalidInput("--span requires this or future")
                }
                span = value
                index += 2
            default:
                throw CalendarError.invalidInput("unsupported delete option: \(arguments[index])")
            }
        }
        guard let apply else { throw CalendarError.invalidInput("delete requires --dry-run or --apply") }
        guard !apply || confirmed else { throw CalendarError.invalidInput("delete apply requires --confirm \"DELETE EVENT\"") }
        guard apply || !confirmed else { throw CalendarError.invalidInput("--confirm is valid only with --apply") }
        return (apply, span)
    }

    static func calendarDecoder() -> JSONDecoder {
        CalendarJSON.decoder()
    }

    static func decodeCalendar<T: Decodable>(_ data: Data) throws -> T {
        do { return try calendarDecoder().decode(T.self, from: data) }
        catch { throw CalendarError.invalidInput("JSON does not match the Calendar contract") }
    }

    static func parseCalendarQuery(_ arguments: [String]) throws -> CalendarEventQuery {
        var startDate: Date?
        var endDate: Date?
        var calendarID: String?
        var title: String?
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--start", "--end", "--calendar", "--title", "--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else {
                throw CalendarError.invalidInput("calendar query accepts --start, --end, --calendar, --title, --limit, and --cursor")
            }
            let value = arguments[index + 1]
            switch option {
            case "--start": startDate = try parseCalendarDate(value, option: option)
            case "--end": endDate = try parseCalendarDate(value, option: option)
            case "--calendar": calendarID = value
            case "--title": title = value
            case "--limit": guard let parsed = Int(value) else { throw CalendarError.invalidInput("--limit requires an integer") }; limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }
        guard let startDate, let endDate else { throw CalendarError.invalidInput("calendar query requires --start and --end") }
        do { return try CalendarEventQuery(startDate: startDate, endDate: endDate, calendarID: calendarID, title: title, limit: limit, cursor: cursor) }
        catch let error as PaginationError { throw error }
    }

    static func parseCalendarConflicts(_ arguments: [String]) throws -> CalendarEventQuery {
        var forwarded: [String] = []
        var index = 0
        while index < arguments.count {
            guard ["--start", "--end", "--calendar"].contains(arguments[index]), index + 1 < arguments.count else {
                throw CalendarError.invalidInput("calendar conflicts accepts --start, --end, and --calendar")
            }
            forwarded.append(contentsOf: [arguments[index], arguments[index + 1]])
            index += 2
        }
        return try parseCalendarQuery(forwarded)
    }

    static func parseCalendarDate(_ value: String, option: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = formatter.date(from: value) { return date }
        throw CalendarError.invalidInput("\(option) requires ISO 8601, for example 2026-08-14T09:00:00+09:00")
    }

}
