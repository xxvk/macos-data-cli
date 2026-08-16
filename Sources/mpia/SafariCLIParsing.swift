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
    static func parseSafariBookmarkPageArguments(_ arguments: [String]) throws -> SafariBookmarkPageArguments {
        var query = SafariBookmarkQuery()
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--text", "--url", "--folder-id", "--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else { throw SafariError.invalidInput }
            let value = arguments[index + 1]
            switch option {
            case "--text": guard !value.isEmpty && value.count <= 500 else { throw SafariError.invalidInput }; query.text = value
            case "--url": guard validSafariHTTPURL(value) else { throw SafariError.invalidInput }; query.url = value
            case "--folder-id": query.folderID = value
            case "--limit": guard let parsed = Int(value) else { throw SafariError.invalidInput }; limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }
        return .init(query: query, limit: limit, cursor: cursor)
    }

    static func parseSafariReadingListPageArguments(_ arguments: [String]) throws -> SafariReadingListPageArguments {
        var query = SafariReadingListQuery()
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--text", "--url", "--read", "--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else { throw SafariError.invalidInput }
            let value = arguments[index + 1]
            switch option {
            case "--text": guard !value.isEmpty && value.count <= 500 else { throw SafariError.invalidInput }; query.text = value
            case "--url": guard validSafariHTTPURL(value) else { throw SafariError.invalidInput }; query.url = value
            case "--read":
                guard let parsed = ["true": true, "false": false][value] else { throw SafariError.invalidInput }
                query.read = parsed
            case "--limit": guard let parsed = Int(value) else { throw SafariError.invalidInput }; limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }
        return .init(query: query, limit: limit, cursor: cursor)
    }

    static func parseSafariReadingListAddArguments(_ arguments: [String]) throws -> SafariReadingListAddArguments {
        var inputData: Data?
        var apply = false
        var dryRun = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--inline-json", "--dry-run", "--apply"].contains(option), seen.insert(option).inserted else {
                throw SafariError.invalidInput
            }
            switch option {
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            case "--inline-json":
                guard index + 1 < arguments.count else { throw SafariError.invalidInput }
                inputData = Data(arguments[index + 1].utf8)
                index += 2
            default: throw SafariError.invalidInput
            }
        }
        guard let data = inputData, apply != dryRun else { throw SafariError.invalidInput }
        guard !data.isEmpty, data.count <= SafariReadingListAddInput.maximumInputBytes else { throw SafariError.invalidInput }
        return .init(data: data, apply: apply)
    }

    static func safariLocalMutationCommand(collection: String, action: String) throws -> SafariLocalMutationCommand {
        switch (collection, action) {
        case ("bookmarks", "create"): .bookmarkCreate
        case ("bookmarks", "edit"): .bookmarkEdit
        case ("bookmarks", "move"): .bookmarkMove
        case ("bookmarks", "delete"): .bookmarkDelete
        case ("folders", "create"): .folderCreate
        case ("folders", "rename"): .folderRename
        case ("folders", "move"): .folderMove
        case ("folders", "delete"): .folderDelete
        default: throw SafariError.invalidInput
        }
    }

    static func parseSafariLocalMutationArguments(_ arguments: [String]) throws -> SafariLocalMutationArguments {
        var inputData: Data?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--inline-json", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw SafariError.invalidInput }
            switch option {
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            case "--inline-json", "--confirm":
                guard index + 1 < arguments.count else { throw SafariError.invalidInput }
                if option == "--inline-json" { inputData = Data(arguments[index + 1].utf8) }
                else { confirmation = arguments[index + 1] }
                index += 2
            default: throw SafariError.invalidInput
            }
        }
        guard let data = inputData, !(apply && dryRun), !(!apply && confirmation != nil) else {
            throw SafariError.invalidInput
        }
        guard !data.isEmpty, data.count <= SafariLocalMutationInput.maximumInputBytes else { throw SafariError.invalidInput }
        return .init(data: data, apply: apply, confirmation: confirmation)
    }

    static func validSafariHTTPURL(_ value: String) -> Bool {
        guard value.utf8.count <= 4_096, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return false }
        return true
    }

    static let restUsage = """
    mpia \(CLIVersion.current) — REST-style local macOS data CLI

    Usage:
      mpia METHOD "/command/path" [--params JSON] [--body JSON]
        [--dry-run|--apply] [--confirm PHRASE]
      mpia --help
      mpia --version | -v

    Discovery:
      mpia GET "/agent/manifest"
      mpia OPTIONS "/resources"

    Examples:
      mpia GET "/contacts/get" --params '{"external-id":"person_123"}'
      mpia PATCH "/reminders/edit" --params '{"id":"reminder_123"}' \
        --body '{"title":"Updated"}' --dry-run

    Rules:
      REST-style routes always emit JSON.
      --params and --body accept strict inline JSON objects only.
      Inline JSON may be visible in shell history and process arguments;
      never include passwords, API keys, or other secrets.
      Use the manifest for every route, method, parameter, schema, safety rule,
      and exit code. Legacy adapter/subcommand syntax was removed in 0.9.3.
    """

}
