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

@main
struct MpiaCLI {
    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())

        if rawArguments.isEmpty || rawArguments == ["--help"] {
            printHelp()
            return
        }
        if rawArguments == ["--version"] || rawArguments == ["-v"] {
            print(CLIVersion.current)
            return
        }

        let manifest = CommandRegistry.standard(version: CLIVersion.current)
        let request: RESTCLIRequest
        do {
            request = try RESTCLIRequestParser.parse(rawArguments, manifest: manifest)
        } catch let error as RESTCLIError {
            reportREST(error)
            Foundation.exit(CLIExitCode.usage.rawValue)
        } catch {
            reportREST(.invalidRequest("Unable to parse REST-style CLI request."))
            Foundation.exit(CLIExitCode.usage.rawValue)
        }
        DiagnosticLogger.record(code: "REST_REQUEST", message: request.diagnosticSummary)

        var arguments = request.internalArguments
        let diagnosticArguments = ["--format", "json"]
        var containerSelector: String?
        if let index = arguments.firstIndex(of: "--container") {
            guard index + 1 < arguments.count else {
                report(error: "--container requires iCloud or a container identifier", code: CLIErrorCode.invalidQuery.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            containerSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        var calendarSourceSelector: String?
        if arguments.first == "calendar", let index = arguments.firstIndex(of: "--source") {
            guard index + 1 < arguments.count else {
                report(error: "--source requires iCloud or a source identifier", code: CLIErrorCode.calendar.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            calendarSourceSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        var remindersSourceSelector: String?
        if arguments.first == "reminders", let index = arguments.firstIndex(of: "--source") {
            guard index + 1 < arguments.count else {
                report(error: "--source requires iCloud or a source identifier", code: CLIErrorCode.reminders.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            remindersSourceSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        do {
            let handled = try await dispatch(
                arguments,
                manifest: manifest,
                containerSelector: containerSelector,
                calendarSourceSelector: calendarSourceSelector,
                remindersSourceSelector: remindersSourceSelector
            )
            guard handled else {
                report(error: "unknown command or invalid arguments", code: CLIErrorCode.invalidQuery.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
        } catch let error as ContactsError {
            report(error: error.description, code: CLIErrorCode.contacts.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.contactsFailure.rawValue)
            Foundation.exit(CLIExitCode.contactsFailure.rawValue)
        } catch let error as ContactsQueryError {
            report(error: error.description, code: CLIErrorCode.query.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.queryFailure.rawValue)
            Foundation.exit(CLIExitCode.queryFailure.rawValue)
        } catch let error as ContactQuerySetError {
            report(error: error.description, code: CLIErrorCode.invalidQuery.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.usage.rawValue)
            Foundation.exit(CLIExitCode.usage.rawValue)
        } catch let error as MailStoreError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.mailFailure.rawValue)
            Foundation.exit(CLIExitCode.mailFailure.rawValue)
        } catch let error as CalendarError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.calendarFailure.rawValue)
            Foundation.exit(CLIExitCode.calendarFailure.rawValue)
        } catch let error as ReminderError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.remindersFailure.rawValue)
            Foundation.exit(CLIExitCode.remindersFailure.rawValue)
        } catch let error as PhotoError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.photosFailure.rawValue)
            Foundation.exit(CLIExitCode.photosFailure.rawValue)
        } catch let error as NotesError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.notesFailure.rawValue)
            Foundation.exit(CLIExitCode.notesFailure.rawValue)
        } catch let error as ShortcutsError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.shortcutsFailure.rawValue)
            Foundation.exit(CLIExitCode.shortcutsFailure.rawValue)
        } catch let error as SafariError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.safariFailure.rawValue)
            Foundation.exit(CLIExitCode.safariFailure.rawValue)
        } catch let error as MessagesError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.messagesFailure.rawValue)
            Foundation.exit(CLIExitCode.messagesFailure.rawValue)
        } catch let error as PhoneCallsError {
            report(error: error.description, code: error.machineCode, arguments: diagnosticArguments, exitCode: CLIExitCode.phoneCallsFailure.rawValue)
            Foundation.exit(CLIExitCode.phoneCallsFailure.rawValue)
        } catch let error as PaginationError {
            if arguments.first == "reminders" {
                report(error: error == .invalidLimit ? "Reminder limit must be between 1 and 200." : "Reminder cursor is invalid or stale.", code: CLIErrorCode.reminders.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.remindersFailure.rawValue)
                Foundation.exit(CLIExitCode.remindersFailure.rawValue)
            } else if arguments.first == "photos" {
                report(error: error == .invalidLimit ? "Photos limit must be between 1 and 200." : "Photos cursor is invalid or stale.", code: CLIErrorCode.photos.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.photosFailure.rawValue)
                Foundation.exit(CLIExitCode.photosFailure.rawValue)
            } else if arguments.first == "notes" {
                report(error: error == .invalidLimit ? "Notes limit must be between 1 and 200." : "Notes cursor is invalid or stale.", code: CLIErrorCode.notes.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.notesFailure.rawValue)
                Foundation.exit(CLIExitCode.notesFailure.rawValue)
            } else if arguments.first == "shortcuts" {
                report(error: error == .invalidLimit ? "Shortcuts limit must be between 1 and 200." : "Shortcuts cursor is invalid or stale.", code: CLIErrorCode.shortcuts.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.shortcutsFailure.rawValue)
                Foundation.exit(CLIExitCode.shortcutsFailure.rawValue)
            } else if arguments.first == "safari" {
                report(error: error == .invalidLimit ? "Safari limit must be between 1 and 200." : "Safari cursor is invalid or stale.", code: CLIErrorCode.safari.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.safariFailure.rawValue)
                Foundation.exit(CLIExitCode.safariFailure.rawValue)
            } else {
                report(error: error == .invalidLimit ? "Calendar limit must be between 1 and 200." : "Calendar cursor is invalid or stale.", code: CLIErrorCode.calendar.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.calendarFailure.rawValue)
                Foundation.exit(CLIExitCode.calendarFailure.rawValue)
            }
        } catch {
            report(error: error.localizedDescription, code: CLIErrorCode.cli.rawValue, arguments: diagnosticArguments, exitCode: CLIExitCode.genericFailure.rawValue)
            Foundation.exit(CLIExitCode.genericFailure.rawValue)
        }
    }

    static func printHelp() { print(restUsage) }
}
