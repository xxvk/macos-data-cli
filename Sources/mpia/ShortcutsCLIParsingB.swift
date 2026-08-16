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
    struct ShortcutUpdateArguments {
        let id: String
        let sourceURL: URL
        let expectedSourceSHA256: String
        let strategy: ShortcutUpdateStrategy
        let signingMode: ShortcutSigningMode
        let apply: Bool
    }

    static func parseShortcutUpdateArguments(_ arguments: [String]) throws -> ShortcutUpdateArguments {
        var id: String?
        var sourceURL: URL?
        var expectedSourceSHA256: String?
        var strategy: ShortcutUpdateStrategy?
        var signingMode = ShortcutSigningMode.peopleWhoKnowMe
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--source", "--expected-source-sha256", "--strategy", "--signing-mode", "--dry-run", "--apply", "--confirm"].contains(option), seen.insert(option).inserted else {
                throw ShortcutsError.authorSourceInvalid
            }
            if option == "--dry-run" { dryRun = true; index += 1; continue }
            if option == "--apply" { apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw ShortcutsError.authorSourceInvalid }
            let value = arguments[index + 1]
            switch option {
            case "--id": id = value
            case "--source": sourceURL = URL(fileURLWithPath: value)
            case "--expected-source-sha256": expectedSourceSHA256 = value
            case "--strategy": strategy = ShortcutUpdateStrategy(rawValue: value)
            case "--signing-mode": signingMode = ShortcutSigningMode(rawValue: value) ?? signingMode
            case "--confirm": confirmation = value
            default: break
            }
            if option == "--strategy" && strategy == nil { throw ShortcutsError.authorSourceInvalid }
            if option == "--signing-mode" && ShortcutSigningMode(rawValue: value) == nil { throw ShortcutsError.authorSourceInvalid }
            index += 2
        }
        guard let id, ShortcutsOpaqueID.isShortcut(id), let sourceURL, sourceURL.pathExtension.lowercased() == "cherri",
              let expectedSourceSHA256, expectedSourceSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let strategy, !(apply && dryRun) else { throw ShortcutsError.authorSourceInvalid }
        if apply {
            guard confirmation == "UPDATE MANAGED SHORTCUT" else { throw ShortcutsError.authorUpdateConfirmationRequired }
        } else if confirmation != nil { throw ShortcutsError.authorSourceInvalid }
        return ShortcutUpdateArguments(id: id, sourceURL: sourceURL, expectedSourceSHA256: expectedSourceSHA256, strategy: strategy, signingMode: signingMode, apply: apply)
    }

    struct ShortcutManagedForgetArguments { let id: String; let apply: Bool }

    static func parseShortcutManagedForgetArguments(_ arguments: [String]) throws -> ShortcutManagedForgetArguments {
        var id: String?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--dry-run", "--apply", "--confirm"].contains(option), seen.insert(option).inserted else {
                throw ShortcutsError.authorSourceInvalid
            }
            if option == "--dry-run" { dryRun = true; index += 1; continue }
            if option == "--apply" { apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw ShortcutsError.authorSourceInvalid }
            if option == "--id" { id = arguments[index + 1] } else { confirmation = arguments[index + 1] }
            index += 2
        }
        guard let id, ShortcutsOpaqueID.isShortcut(id), !(apply && dryRun) else { throw ShortcutsError.authorSourceInvalid }
        if apply {
            guard confirmation == "FORGET MANAGED SHORTCUT" else { throw ShortcutsError.authorForgetConfirmationRequired }
        } else if confirmation != nil { throw ShortcutsError.authorSourceInvalid }
        return ShortcutManagedForgetArguments(id: id, apply: apply)
    }

    static func parseShortcutAuthorArguments(_ arguments: [String], build: Bool) throws -> ShortcutAuthorArguments {
        var sourceURL: URL?
        var outputURL: URL?
        var signingMode = ShortcutSigningMode.peopleWhoKnowMe
        var seen = Set<String>()
        var index = 0
        let allowed = build ? ["--source", "--output", "--signing-mode"] : ["--source"]
        while index < arguments.count {
            let option = arguments[index]
            guard allowed.contains(option), seen.insert(option).inserted, index + 1 < arguments.count else {
                throw ShortcutsError.authorSourceInvalid
            }
            let value = arguments[index + 1]
            switch option {
            case "--source": sourceURL = URL(fileURLWithPath: value)
            case "--output": outputURL = URL(fileURLWithPath: value)
            case "--signing-mode":
                guard let parsed = ShortcutSigningMode(rawValue: value) else { throw ShortcutsError.authorSourceInvalid }
                signingMode = parsed
            default: break
            }
            index += 2
        }
        guard let sourceURL, sourceURL.pathExtension.lowercased() == "cherri",
              !build || outputURL != nil else { throw ShortcutsError.authorSourceInvalid }
        return ShortcutAuthorArguments(sourceURL: sourceURL, outputURL: outputURL, signingMode: signingMode)
    }

    static func parseShortcutRunArguments(_ arguments: [String]) throws -> ShortcutRunArguments {
        var id: String?
        var inputPaths: [URL] = []
        var outputPath: URL?
        var outputType = "public.utf8-plain-text"
        var timeoutSeconds = 30
        var apply = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--input-path", "--output-path", "--output-type", "--timeout", "--apply", "--confirm"].contains(option) else {
                throw ShortcutsError.invalidRunInput
            }
            if option != "--input-path" && !seen.insert(option).inserted { throw ShortcutsError.invalidRunInput }
            if option == "--apply" { apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw ShortcutsError.invalidRunInput }
            let value = arguments[index + 1]
            switch option {
            case "--id": id = value
            case "--input-path": inputPaths.append(URL(fileURLWithPath: value))
            case "--output-path": outputPath = URL(fileURLWithPath: value)
            case "--output-type": outputType = value
            case "--timeout":
                guard let parsed = Int(value) else { throw ShortcutsError.invalidRunInput }
                timeoutSeconds = parsed
            case "--confirm": confirmation = value
            default: break
            }
            index += 2
        }
        guard apply, confirmation == "RUN SHORTCUT" else { throw ShortcutsError.confirmationRequired }
        guard let id else { throw ShortcutsError.invalidRunInput }
        return ShortcutRunArguments(id: id, inputPaths: inputPaths, outputPath: outputPath, outputType: outputType, timeoutSeconds: timeoutSeconds)
    }

    static func parseShortcutMoveArguments(_ arguments: [String]) throws -> ShortcutMoveArguments {
        var id: String?
        var destinationFolderID: String?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--destination-folder-id", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw ShortcutsError.invalidIdentifier }
            switch option {
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            default:
                guard index + 1 < arguments.count else { throw ShortcutsError.invalidIdentifier }
                let value = arguments[index + 1]
                if option == "--id" { id = value }
                else if option == "--destination-folder-id" { destinationFolderID = value }
                else { confirmation = value }
                index += 2
            }
        }
        guard let id, let destinationFolderID, !(apply && dryRun), !(!apply && confirmation != nil) else {
            throw ShortcutsError.invalidIdentifier
        }
        if apply && confirmation != "MOVE SHORTCUT" { throw ShortcutsError.confirmationRequired }
        return ShortcutMoveArguments(id: id, destinationFolderID: destinationFolderID, apply: apply)
    }

}
