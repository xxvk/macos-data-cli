import AppKit
import Foundation

public enum MailAppBridgeError: Error, Equatable, Sendable {
    case automationDenied
    case mailNotRunning
    case timedOut
    case messageNotFound
    case circuitOpen
    case executionFailed
}

public struct MailAppMessageLocator: Equatable, Sendable {
    public let rowID: Int64
    public let accountID: String
    public let mailboxPath: String

    public init(rowID: Int64, accountID: String, mailboxPath: String) {
        self.rowID = rowID
        self.accountID = accountID
        self.mailboxPath = mailboxPath
    }
}

public protocol MailAppleEventExecuting: Sendable {
    func readText(locator: MailAppMessageLocator, timeoutSeconds: Int) throws -> String
    func reveal(locator: MailAppMessageLocator, timeoutSeconds: Int) throws
}

public protocol MailAppBridging: Sendable {
    func readText(locator: MailAppMessageLocator) throws -> String
    func reveal(locator: MailAppMessageLocator) throws
}

public final class MailAppBridge: MailAppBridging, @unchecked Sendable {
    public static let timeoutSeconds = 3
    public static let circuitBreakerSeconds: TimeInterval = 30

    private let executor: any MailAppleEventExecuting
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var circuitOpenUntil: Date?

    public init(
        executor: any MailAppleEventExecuting = SystemMailAppleEventExecutor(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.executor = executor
        self.now = now
    }

    public func readText(locator: MailAppMessageLocator) throws -> String {
        try perform { try executor.readText(locator: locator, timeoutSeconds: Self.timeoutSeconds) }
    }

    public func reveal(locator: MailAppMessageLocator) throws {
        try perform { try executor.reveal(locator: locator, timeoutSeconds: Self.timeoutSeconds) }
    }

    private func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if let circuitOpenUntil, circuitOpenUntil > now() {
            throw MailAppBridgeError.circuitOpen
        }
        do {
            return try operation()
        } catch MailAppBridgeError.timedOut {
            circuitOpenUntil = now().addingTimeInterval(Self.circuitBreakerSeconds)
            throw MailAppBridgeError.timedOut
        }
    }
}

public struct SystemMailAppleEventExecutor: MailAppleEventExecuting {
    private static let executionLock = NSLock()

    public init() {}

    public func readText(locator: MailAppMessageLocator, timeoutSeconds: Int) throws -> String {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else {
            throw MailAppBridgeError.mailNotRunning
        }
        let descriptor = try execute(
            Self.script(locator: locator, operation: .readText, timeoutSeconds: timeoutSeconds)
        )
        guard let text = descriptor.stringValue else { throw MailAppBridgeError.executionFailed }
        return text
    }

    public func reveal(locator: MailAppMessageLocator, timeoutSeconds: Int) throws {
        _ = try execute(Self.script(locator: locator, operation: .reveal, timeoutSeconds: timeoutSeconds))
    }

    enum Operation {
        case readText
        case reveal
    }

    static func script(locator: MailAppMessageLocator, operation: Operation, timeoutSeconds: Int) -> String {
        let account = escape(locator.accountID)
        let segments = locator.mailboxPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let accountReference = "(account id \"\(account)\")"
        let mailboxReference: String
        if segments.count == 1, let name = segments.first {
            mailboxReference = "(first mailbox of \(accountReference) whose name is \"\(escape(name))\")"
        } else {
            mailboxReference = segments.reduce(accountReference) { parent, segment in
                "(mailbox \"\(escape(segment))\" of \(parent))"
            }
        }
        let messageReference = "(first message of \(mailboxReference) whose id is \(locator.rowID))"
        switch operation {
        case .readText:
            return """
            with timeout of \(timeoutSeconds) seconds
                tell application id "com.apple.mail"
                    return (content of \(messageReference)) as text
                end tell
            end timeout
            """
        case .reveal:
            return """
            with timeout of \(timeoutSeconds) seconds
                tell application id "com.apple.mail"
                    set targetMessage to \(messageReference)
                    open targetMessage
                    activate
                    return id of targetMessage
                end tell
            end timeout
            """
        }
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        Self.executionLock.lock()
        defer { Self.executionLock.unlock() }
        guard let script = NSAppleScript(source: source) else { throw MailAppBridgeError.executionFailed }
        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details, let number = details[NSAppleScript.errorNumber] as? NSNumber {
            throw Self.mapError(number.intValue)
        }
        return result
    }

    private static func mapError(_ number: Int) -> MailAppBridgeError {
        switch number {
        case -1743: .automationDenied
        case -1712: .timedOut
        case -600, -609: .mailNotRunning
        case -1728, -1719: .messageNotFound
        default: .executionFailed
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
