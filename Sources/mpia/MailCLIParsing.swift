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
    static func parseMailQuery(_ arguments: [String]) throws -> MailQuery {
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

    static func parseMailTextSearch(_ arguments: [String]) throws -> (text: String, query: MailQuery, limit: Int) {
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

    static func parseSimpleLimit(_ arguments: [String]) throws -> Int {
        guard arguments.count == 0 || (arguments.count == 2 && arguments[0] == "--limit"),
              let value = arguments.isEmpty ? 50 : Int(arguments[1]),
              (1...200).contains(value) else { throw MailStoreError.invalidLimit }
        return value
    }

    static func parseMailDate(_ value: String, option: String) throws -> Date {
        let timestampFormatter = ISO8601DateFormatter()
        if let date = timestampFormatter.date(from: value) { return date }
        let dayFormatter = ISO8601DateFormatter()
        dayFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = dayFormatter.date(from: value) { return date }
        throw MailStoreError.invalidArgument("\(option) requires ISO 8601, for example 2026-07-23 or 2026-07-23T00:00:00Z")
    }

    struct MailGetArguments {
        let id: String
        let projection: MailContentProjection
        let output: String?
    }

    static func parseMailGet(_ arguments: [String], jsonRequested: Bool) throws -> MailGetArguments {
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

}
