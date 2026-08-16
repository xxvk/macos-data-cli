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
    static func handleCommunication(_ arguments: [String]) throws -> Bool {

        switch arguments {
        case ["messages", "permission"]:
            let reader = ChatDbReader(databaseURL: try MessagesStoreLocator().locate().databaseURL)
            emitJSONSuccess(try reader.permission())
        case let args where args.count >= 2 && args[0] == "messages" && args[1] == "recent":
            let request = try parseMessagesRecentArguments(Array(args.dropFirst(2)))
            let reader = ChatDbReader(databaseURL: try MessagesStoreLocator().locate().databaseURL)
            emitJSONSuccess(try reader.recent(limit: request.limit, cursor: request.cursor, service: request.service))
        case ["phone-calls", "permission"]:
            let reader = CallHistoryReader(databaseURL: try PhoneStoreLocator().locate().databaseURL)
            emitJSONSuccess(try reader.permission())
        case let args where args.count >= 2 && args[0] == "phone-calls" && args[1] == "recent":
            let request = try parsePhoneCallsRecentArguments(Array(args.dropFirst(2)))
            let reader = CallHistoryReader(databaseURL: try PhoneStoreLocator().locate().databaseURL)
            emitJSONSuccess(try reader.recent(limit: request.limit, cursor: request.cursor))
        default: return false
        }
        return true
    }
}
