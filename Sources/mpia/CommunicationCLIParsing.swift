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
    struct MessagesRecentRequest {
        let limit: Int
        let cursor: String?
        let service: String?
    }

    static func parseMessagesRecentArguments(_ arguments: [String]) throws -> MessagesRecentRequest {
        var limit = ChatDbReader.defaultLimit
        var cursor: String?
        var service: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--limit", "--cursor", "--service"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else {
                throw MessagesError.invalidArgument("unexpected or repeated option \(option)")
            }
            let value = arguments[index + 1]
            switch option {
            case "--limit":
                guard let parsed = Int(value) else { throw MessagesError.invalidArgument("--limit requires an integer") }
                limit = parsed
            case "--cursor":
                cursor = value
            case "--service":
                guard ["imessage", "sms"].contains(value.lowercased()) else { throw MessagesError.invalidArgument("--service must be imessage or sms") }
                service = value
            default: break
            }
            index += 2
        }
        return MessagesRecentRequest(limit: limit, cursor: cursor, service: service)
    }

    struct PhoneCallsRecentRequest {
        let limit: Int
        let cursor: String?
    }

    static func parsePhoneCallsRecentArguments(_ arguments: [String]) throws -> PhoneCallsRecentRequest {
        var limit = CallHistoryReader.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else {
                throw PhoneCallsError.invalidArgument("unexpected or repeated option \(option)")
            }
            let value = arguments[index + 1]
            switch option {
            case "--limit":
                guard let parsed = Int(value) else { throw PhoneCallsError.invalidArgument("--limit requires an integer") }
                limit = parsed
            case "--cursor":
                cursor = value
            default: break
            }
            index += 2
        }
        return PhoneCallsRecentRequest(limit: limit, cursor: cursor)
    }

}
