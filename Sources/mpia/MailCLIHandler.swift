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
    static func handleMail(_ arguments: [String]) throws -> Bool {

        switch arguments {
        case ["mail", "doctor"]:
            emitJSONSuccess(MailDoctor().run())
        case ["mail", "accounts"]:
            emitJSONSuccess(try makeValidatedMailStore().accounts())
        case ["mail", "mailboxes"]:
            emitJSONSuccess(try makeValidatedMailStore().mailboxes())
        case let args where args.count >= 2 && args[0] == "mail" && args[1] == "threads":
            emitJSONSuccess(try makeValidatedMailStore().threads(limit: parseSimpleLimit(Array(args.dropFirst(2)))))
        case let args where args.count == 4 && args[0] == "mail" && args[1] == "mailboxes" && args[2] == "--account-id":
            emitJSONSuccess(try makeValidatedMailStore().mailboxes(accountID: args[3]))
        case let args where args.count >= 2 && args[0] == "mail" && args[1] == "query":
            emitJSONSuccess(try makeValidatedMailStore().query(parseMailQuery(Array(args.dropFirst(2)))))
        case let args where args.count >= 2 && args[0] == "mail" && args[1] == "search":
            let request = try parseMailTextSearch(Array(args.dropFirst(2)))
            emitJSONSuccess(try makeValidatedMailStore().searchText(request.text, query: request.query, resultLimit: request.limit))
        case let args where args.count >= 2 && args[0] == "mail" && args[1] == "get":
            let request = try parseMailGet(Array(args.dropFirst(2)), jsonRequested: true)
            let mailStore = try makeValidatedMailStore()
            if request.projection == .raw {
                let raw = try mailStore.rawMessage(id: request.id)
                if request.output == "-" {
                    do { try FileHandle.standardOutput.write(contentsOf: raw.data) }
                    catch { throw MailStoreError.outputFailed }
                } else {
                    guard let output = request.output else {
                        throw MailStoreError.invalidArgument("Raw content requires --output <file|->.")
                    }
                    do {
                        try raw.data.write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
                    } catch let error as CocoaError where error.code == .fileWriteFileExists {
                        throw MailStoreError.outputAlreadyExists
                    } catch {
                        throw MailStoreError.outputFailed
                    }
                    emitJSONSuccess(MailRawWriteResult(
                        backend: "sqlite_emlx",
                        cacheState: raw.cacheState,
                        id: raw.message.id,
                        output: "file",
                        bytesWritten: raw.data.count,
                        fallbackReason: raw.incomplete ? "partial_emlx" : nil,
                        incomplete: raw.incomplete,
                        limitations: raw.limitations
                    ))
                }
            } else {
                emitJSONSuccess(try mailStore.get(id: request.id, projection: request.projection))
            }
        case let args where args.count == 4 && args[0] == "mail" && args[1] == "reveal" && args[2] == "--id":
            emitJSONSuccess(try makeValidatedMailStore().reveal(id: args[3]))
        case let args where args.count == 5 && args[0] == "mail" && args[1] == "attachments" &&
            args[2] == "verify" && args[3] == "--id":
            emitJSONSuccess(try makeValidatedMailStore().verifyAttachments(id: args[4]))
        case let args where args.count == 7 && args[0] == "mail" && args[1] == "attachments" &&
            args[2] == "export" && args[3] == "--id" && args[5] == "--output":
            emitJSONSuccess(try makeValidatedMailStore().exportAttachments(id: args[4], directory: URL(fileURLWithPath: args[6])))
        default: return false
        }
        return true
    }
}
