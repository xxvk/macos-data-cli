import AppKit
import Core
import Foundation

enum SafariReadingListBridgeError: Error, Equatable, Sendable {
    case automationDenied
    case targetUnavailable
    case timedOut
    case failed
}

protocol SafariReadingListMutationBridging: Sendable {
    func add(url: URL, title: String?, previewText: String?) throws
}

private let safariAppleEventLock = NSLock()

struct SystemSafariReadingListMutationBridge: SafariReadingListMutationBridging {
    static let timeoutSeconds = 5

    func add(url: URL, title: String?, previewText: String?) throws {
        safariAppleEventLock.lock()
        defer { safariAppleEventLock.unlock() }
        guard let script = NSAppleScript(source: Self.script(url: url.absoluteString, title: title, previewText: previewText)) else {
            throw SafariReadingListBridgeError.failed
        }
        var details: NSDictionary?
        _ = script.executeAndReturnError(&details)
        if let details, let number = details[NSAppleScript.errorNumber] as? NSNumber {
            DiagnosticLogger.record(code: "SAFARI_READING_LIST_APPLE_EVENT_ERROR", message: "Safari Reading List Apple Event failed with code \(number.intValue). No URL, title, or preview text was logged.")
            switch number.intValue {
            case -1743: throw SafariReadingListBridgeError.automationDenied
            case -1712: throw SafariReadingListBridgeError.timedOut
            case -600, -609: throw SafariReadingListBridgeError.targetUnavailable
            default: throw SafariReadingListBridgeError.failed
            }
        }
    }

    static func script(url: String, title: String?, previewText: String?) -> String {
        var command = "add reading list item \"\(escape(url))\""
        if let title { command += " with title \"\(escape(title))\"" }
        if let previewText { command += " and preview text \"\(escape(previewText))\"" }
        return """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Safari"
                \(command)
            end tell
        end timeout
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
