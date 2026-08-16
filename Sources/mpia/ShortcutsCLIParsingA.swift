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
    struct ShortcutsPageArguments {
        let limit: Int
        let cursor: String?
        let folderID: String?
    }

    static func parseShortcutsPageArguments(_ arguments: [String], allowsFolder: Bool) throws -> ShortcutsPageArguments {
        var limit = Pagination.defaultLimit
        var cursor: String?
        var folderID: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            let allowed = allowsFolder ? ["--limit", "--cursor", "--folder-id"] : ["--limit", "--cursor"]
            guard allowed.contains(option), seen.insert(option).inserted, index + 1 < arguments.count else {
                throw ShortcutsError.invalidIdentifier
            }
            let value = arguments[index + 1]
            switch option {
            case "--limit":
                guard let parsed = Int(value), (1...Pagination.maximumLimit).contains(parsed) else { throw ShortcutsError.invalidLimit }
                limit = parsed
            case "--cursor": cursor = value
            case "--folder-id": folderID = value
            default: break
            }
            index += 2
        }
        return ShortcutsPageArguments(limit: limit, cursor: cursor, folderID: folderID)
    }

    struct ShortcutMoveArguments {
        let id: String
        let destinationFolderID: String
        let apply: Bool
    }

    struct ShortcutRunArguments {
        let id: String
        let inputPaths: [URL]
        let outputPath: URL?
        let outputType: String
        let timeoutSeconds: Int
    }

    struct ShortcutAuthorArguments {
        let sourceURL: URL
        let outputURL: URL?
        let signingMode: ShortcutSigningMode
    }

    static func parseShortcutAcquisitionArguments(_ arguments: [String]) throws -> URL {
        guard arguments.count == 2,
              arguments[0] == "--input",
              !arguments[1].contains("://") else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        let inputURL = URL(fileURLWithPath: arguments[1])
        guard ["cherri", "shortcut"].contains(inputURL.pathExtension.lowercased()) else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        return inputURL
    }

    struct ShortcutEditPlanArguments {
        let inputURL: URL
        let patchURL: URL?
    }

    static func parseShortcutEditPlanArguments(_ arguments: [String]) throws -> ShortcutEditPlanArguments {
        var inputURL: URL?
        var patchURL: URL?
        var usesStdin = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--input", "--patch", "--stdin"].contains(option), seen.insert(option).inserted else {
                throw ShortcutsError.editPlanInvalid
            }
            if option == "--stdin" {
                usesStdin = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw ShortcutsError.editPlanInvalid }
            let url = URL(fileURLWithPath: arguments[index + 1])
            if option == "--input" { inputURL = url }
            else { patchURL = url }
            index += 2
        }
        guard let inputURL,
              inputURL.pathExtension.lowercased() == "shortcut",
              usesStdin != (patchURL != nil),
              patchURL?.pathExtension.lowercased() == "json" || patchURL == nil else {
            throw ShortcutsError.editPlanInvalid
        }
        return ShortcutEditPlanArguments(inputURL: inputURL, patchURL: patchURL)
    }

    struct ShortcutSemanticEditArguments {
        let inputURL: URL
        let patchURL: URL?
        let expectedEditorNameSHA256: String
        let apply: Bool
        let confirmation: String?
    }

    static func parseShortcutSemanticEditArguments(_ arguments: [String]) throws -> ShortcutSemanticEditArguments {
        var inputURL: URL?
        var patchURL: URL?
        var usesStdin = false
        var expectedEditorNameSHA256: String?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--input", "--patch", "--stdin", "--expected-editor-name-sha256", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else {
                throw ShortcutsError.editPlanInvalid
            }
            switch option {
            case "--stdin":
                usesStdin = true
                index += 1
            case "--dry-run":
                dryRun = true
                index += 1
            case "--apply":
                apply = true
                index += 1
            default:
                guard index + 1 < arguments.count else { throw ShortcutsError.editPlanInvalid }
                let value = arguments[index + 1]
                if option == "--input" { inputURL = URL(fileURLWithPath: value) }
                else if option == "--patch" { patchURL = URL(fileURLWithPath: value) }
                else if option == "--expected-editor-name-sha256" { expectedEditorNameSHA256 = value }
                else { confirmation = value }
                index += 2
            }
        }
        guard let inputURL,
              inputURL.pathExtension.lowercased() == "shortcut",
              let expectedEditorNameSHA256,
              expectedEditorNameSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              usesStdin != (patchURL != nil),
              patchURL?.pathExtension.lowercased() == "json" || patchURL == nil,
              apply != dryRun,
              apply || confirmation == nil else {
            throw ShortcutsError.editPlanInvalid
        }
        return ShortcutSemanticEditArguments(
            inputURL: inputURL,
            patchURL: patchURL,
            expectedEditorNameSHA256: expectedEditorNameSHA256,
            apply: apply,
            confirmation: confirmation
        )
    }

    struct ShortcutCreateArguments {
        let sourceURL: URL
        let signingMode: ShortcutSigningMode
        let apply: Bool
        let idempotent: Bool
    }

    static func parseShortcutCreateArguments(_ arguments: [String]) throws -> ShortcutCreateArguments {
        var sourceURL: URL?
        var signingMode = ShortcutSigningMode.peopleWhoKnowMe
        var apply = false
        var dryRun = false
        var idempotent = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--source", "--signing-mode", "--dry-run", "--apply", "--idempotent", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw ShortcutsError.authorSourceInvalid }
            switch option {
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            case "--idempotent": idempotent = true; index += 1
            default:
                guard index + 1 < arguments.count else { throw ShortcutsError.authorSourceInvalid }
                let value = arguments[index + 1]
                if option == "--source" { sourceURL = URL(fileURLWithPath: value) }
                else if option == "--signing-mode" {
                    guard let parsed = ShortcutSigningMode(rawValue: value) else { throw ShortcutsError.authorSourceInvalid }
                    signingMode = parsed
                } else { confirmation = value }
                index += 2
            }
        }
        guard let sourceURL, sourceURL.pathExtension.lowercased() == "cherri", !(apply && dryRun) else {
            throw ShortcutsError.authorSourceInvalid
        }
        if apply {
            guard confirmation == "CREATE MANAGED SHORTCUT" else { throw ShortcutsError.authorCreateConfirmationRequired }
        } else if confirmation != nil {
            throw ShortcutsError.authorSourceInvalid
        }
        return ShortcutCreateArguments(sourceURL: sourceURL, signingMode: signingMode, apply: apply, idempotent: idempotent)
    }

}
