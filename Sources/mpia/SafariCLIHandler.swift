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
    static func handleSafari(_ arguments: [String]) throws -> Bool {
        let safariPermission = SafariPermissionService()
        let safariStore = SafariStore()
        switch arguments {
        case ["safari", "permission"]:
            emitSafariJSONSuccess(safariPermission.check(requestConsent: false))
        case ["safari", "permission", "--request"]:
            let result = safariPermission.check(requestConsent: true)
            emitSafariJSONSuccess(result)
            if result.automation != .available { Foundation.exit(CLIExitCode.safariFailure.rawValue) }
        case let args where args.count >= 3 && args[0] == "safari" && args[1] == "bookmarks" && ["list", "query"].contains(args[2]):
            let request = try parseSafariBookmarkPageArguments(Array(args.dropFirst(3)))
            emitSafariJSONSuccess(try safariStore.bookmarks(query: request.query, limit: request.limit, cursor: request.cursor))
        case let args where args.count == 5 && args[0] == "safari" && args[1] == "bookmarks" && args[2] == "get" && args[3] == "--id":
            emitSafariJSONSuccess(try safariStore.bookmark(id: args[4]))
        case let args where args.count >= 3 && args[0] == "safari" && ["bookmarks", "folders"].contains(args[1]) && ["create", "edit", "rename", "move", "delete"].contains(args[2]):
            let command = try safariLocalMutationCommand(collection: args[1], action: args[2])
            let request = try parseSafariLocalMutationArguments(Array(args.dropFirst(3)))
            let input = try SafariLocalMutationInput.decode(request.data, command: command)
            emitSafariJSONSuccess(try safariStore.mutateLocally(input, apply: request.apply, confirmation: request.confirmation))
        case let args where args.count >= 3 && args[0] == "safari" && args[1] == "reading-list" && ["list", "query"].contains(args[2]):
            let request = try parseSafariReadingListPageArguments(Array(args.dropFirst(3)))
            emitSafariJSONSuccess(try safariStore.readingList(query: request.query, limit: request.limit, cursor: request.cursor))
        case let args where args.count == 5 && args[0] == "safari" && args[1] == "reading-list" && args[2] == "get" && args[3] == "--id":
            emitSafariJSONSuccess(try safariStore.readingListItem(id: args[4]))
        case let args where args.count >= 3 && args[0] == "safari" && args[1] == "reading-list" && args[2] == "add":
            let request = try parseSafariReadingListAddArguments(Array(args.dropFirst(3)))
            emitSafariJSONSuccess(try safariStore.addReadingList(SafariReadingListAddInput.decode(request.data), apply: request.apply))
        default: return false
        }
        return true
    }
}
