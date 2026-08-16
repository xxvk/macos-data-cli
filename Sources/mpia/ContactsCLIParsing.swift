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
    static func parseQuerySet(_ arguments: [String]) throws -> ContactQuerySet {
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

    struct ContactPaginationArguments {
        let conditions: [String]
        let limit: Int
        let cursor: String?
    }

    static func parseContactPagination(_ arguments: [String]) throws -> ContactPaginationArguments {
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

}
