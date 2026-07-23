import AppKit
import Foundation

private let systemMailAppleEventExecutionLock = NSLock()

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
    public let mailboxPathIsLiteral: Bool

    public init(rowID: Int64, accountID: String, mailboxPath: String) {
        self.rowID = rowID
        self.accountID = accountID
        self.mailboxPath = mailboxPath
        self.mailboxPathIsLiteral = false
    }

    public init(rowID: Int64, accountID: String, mailboxName: String) {
        self.rowID = rowID
        self.accountID = accountID
        self.mailboxPath = mailboxName
        self.mailboxPathIsLiteral = true
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
        let messageReference = messageReference(locator: locator)
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
        systemMailAppleEventExecutionLock.lock()
        defer { systemMailAppleEventExecutionLock.unlock() }
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

    static func messageReference(locator: MailAppMessageLocator) -> String {
        let account = escape(locator.accountID)
        let segments = locator.mailboxPathIsLiteral
            ? [locator.mailboxPath]
            : locator.mailboxPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let accountReference = "(account id \"\(account)\")"
        let mailboxReference: String
        if segments.count == 1, let name = segments.first {
            mailboxReference = "(first mailbox of \(accountReference) whose name is \"\(escape(name))\")"
        } else {
            mailboxReference = segments.reduce(accountReference) { parent, segment in
                "(mailbox \"\(escape(segment))\" of \(parent))"
            }
        }
        return "(first message of \(mailboxReference) whose id is \(locator.rowID))"
    }
}

public final class SystemMailAppMetadataBridge: MailAppMetadataBridging, @unchecked Sendable {
    public static let timeoutSeconds = 5

    private let lock = NSLock()
    private var circuitOpenUntil: Date?
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func snapshot(
        maximumAccounts: Int,
        maximumMailboxes: Int,
        maximumMessages: Int
    ) throws -> MailAppMetadataSnapshot {
        guard (1...32).contains(maximumAccounts), (1...200).contains(maximumMailboxes),
              (0...25).contains(maximumMessages) else {
            throw MailAppBridgeError.executionFailed
        }
        return try perform {
            let descriptor = try execute(Self.snapshotScript(
                maximumAccounts: maximumAccounts,
                maximumMailboxes: maximumMailboxes,
                maximumMessages: maximumMessages,
                timeoutSeconds: Self.timeoutSeconds
            ))
            return try Self.parseSnapshot(descriptor)
        }
    }

    public func metadata(locator: MailAppMessageLocator) throws -> MailAppMessageRecord {
        try perform {
            let descriptor = try execute(Self.metadataScript(locator: locator, timeoutSeconds: Self.timeoutSeconds))
            return try Self.parseMessage(descriptor, accountKey: locator.accountID, mailboxPath: locator.mailboxPath)
        }
    }

    private func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if let circuitOpenUntil, circuitOpenUntil > now() { throw MailAppBridgeError.circuitOpen }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else {
            throw MailAppBridgeError.mailNotRunning
        }
        do {
            return try operation()
        } catch MailAppBridgeError.timedOut {
            circuitOpenUntil = now().addingTimeInterval(MailAppBridge.circuitBreakerSeconds)
            throw MailAppBridgeError.timedOut
        }
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        systemMailAppleEventExecutionLock.lock()
        defer { systemMailAppleEventExecutionLock.unlock() }
        guard let script = NSAppleScript(source: source) else { throw MailAppBridgeError.executionFailed }
        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details, let number = details[NSAppleScript.errorNumber] as? NSNumber {
            throw Self.mapError(number.intValue)
        }
        return result
    }

    static func snapshotScript(
        maximumAccounts: Int,
        maximumMailboxes: Int,
        maximumMessages: Int,
        timeoutSeconds: Int
    ) -> String {
        """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.mail"
                set accountRows to {}
                set mailboxRows to {}
                set messageRows to {}
                set accountLimitReached to false
                set mailboxLimitReached to false
                set messageLimitReached to false
                set accountCounter to 0
                set mailboxCounter to 0
                set messageCounter to 0
                set accountItems to every account
                repeat with accountItem in accountItems
                    if accountCounter is greater than or equal to \(maximumAccounts) then
                        set accountLimitReached to true
                    else
                        set accountCounter to accountCounter + 1
                        set accountKey to (id of accountItem) as text
                        set accountKind to "unknown"
                        try
                            set accountKind to (account type of accountItem) as text
                        end try
                        copy {accountKey, accountKind} to end of accountRows
                        set mailboxItems to every mailbox of accountItem
                        repeat with mailboxItem in mailboxItems
                            if mailboxCounter is greater than or equal to \(maximumMailboxes) then
                                set mailboxLimitReached to true
                            else
                                set mailboxCounter to mailboxCounter + 1
                                set mailboxName to (name of mailboxItem) as text
                                set mailboxPath to mailboxName
                                set totalValue to 0
                                set unreadValue to 0
                                try
                                    set totalValue to count of messages of mailboxItem
                                end try
                                try
                                    set unreadValue to unread count of mailboxItem
                                end try
                                copy {accountKey, mailboxPath, mailboxName, totalValue, unreadValue} to end of mailboxRows
                                if \(maximumMessages) is greater than 0 then
                                    set remainingCount to \(maximumMessages) - messageCounter
                                    if remainingCount is greater than 0 then
                                        set mailboxMessages to messages of mailboxItem
                                        set mailboxMessageCount to count of mailboxMessages
                                        set takeCount to mailboxMessageCount
                                        if takeCount is greater than remainingCount then
                                            set takeCount to remainingCount
                                            set messageLimitReached to true
                                        end if
                                        repeat with messageIndex from 1 to takeCount
                                            set messageItem to item messageIndex of mailboxMessages
                                            set messageRow to my metadataRow(messageItem)
                                            copy {accountKey, mailboxPath, messageRow} to end of messageRows
                                            set messageCounter to messageCounter + 1
                                        end repeat
                                    else if totalValue is greater than 0 then
                                        set messageLimitReached to true
                                    end if
                                end if
                            end if
                        end repeat
                    end if
                end repeat
                return {accountRows, mailboxRows, messageRows, accountLimitReached, mailboxLimitReached, messageLimitReached}
            end tell
        end timeout

        on metadataRow(messageItem)
            using terms from application "Mail"
                tell application id "com.apple.mail"
                    set messageIdentifier to id of messageItem
                    set rfcMessageID to ""
                    set subjectValue to ""
                    set senderValue to ""
                    set sentValue to missing value
                    set receivedValue to missing value
                    set readValue to false
                    set flaggedValue to false
                    set attachmentValue to 0
                    set sizeValue to 0
                    set recipientValues to {}
                    try
                        set rfcMessageID to (message id of messageItem) as text
                    end try
                    try
                        set subjectValue to (subject of messageItem) as text
                    end try
                    try
                        set senderValue to (sender of messageItem) as text
                    end try
                    try
                        set sentValue to date sent of messageItem
                    end try
                    try
                        set receivedValue to date received of messageItem
                    end try
                    try
                        set readValue to read status of messageItem
                    end try
                    try
                        set flaggedValue to flagged status of messageItem
                    end try
                    try
                        set attachmentValue to count of mail attachments of messageItem
                    end try
                    try
                        set sizeValue to message size of messageItem
                    end try
                    try
                        repeat with recipientItem in to recipients of messageItem
                            copy ((address of recipientItem) as text) to end of recipientValues
                        end repeat
                    end try
                    return {messageIdentifier, rfcMessageID, subjectValue, senderValue, sentValue, receivedValue, readValue, flaggedValue, attachmentValue, sizeValue, recipientValues}
                end tell
            end using terms from
        end metadataRow
        """
    }

    static func metadataScript(locator: MailAppMessageLocator, timeoutSeconds: Int) -> String {
        let reference = SystemMailAppleEventExecutor.messageReference(locator: locator)
        return """
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.mail"
                set messageItem to \(reference)
                set messageIdentifier to id of messageItem
                set rfcMessageID to ""
                set subjectValue to ""
                set senderValue to ""
                set sentValue to missing value
                set receivedValue to missing value
                set readValue to false
                set flaggedValue to false
                set attachmentValue to 0
                set sizeValue to 0
                set recipientValues to {}
                try
                    set rfcMessageID to (message id of messageItem) as text
                end try
                try
                    set subjectValue to (subject of messageItem) as text
                end try
                try
                    set senderValue to (sender of messageItem) as text
                end try
                try
                    set sentValue to date sent of messageItem
                end try
                try
                    set receivedValue to date received of messageItem
                end try
                try
                    set readValue to read status of messageItem
                end try
                try
                    set flaggedValue to flagged status of messageItem
                end try
                try
                    set attachmentValue to count of mail attachments of messageItem
                end try
                try
                    set sizeValue to message size of messageItem
                end try
                try
                    repeat with recipientItem in to recipients of messageItem
                        copy ((address of recipientItem) as text) to end of recipientValues
                    end repeat
                end try
                return {messageIdentifier, rfcMessageID, subjectValue, senderValue, sentValue, receivedValue, readValue, flaggedValue, attachmentValue, sizeValue, recipientValues}
            end tell
        end timeout
        """
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) throws -> MailAppMetadataSnapshot {
        guard descriptor.numberOfItems == 6,
              let accountRows = descriptor.atIndex(1),
              let mailboxRows = descriptor.atIndex(2),
              let messageRows = descriptor.atIndex(3) else {
            throw MailAppBridgeError.executionFailed
        }
        var accounts: [MailAppAccountRecord] = []
        for offset in 0..<accountRows.numberOfItems {
            guard let row = accountRows.atIndex(offset + 1), row.numberOfItems == 2,
                  let key = row.atIndex(1)?.stringValue, !key.isEmpty else { continue }
            accounts.append(MailAppAccountRecord(key: key, kind: row.atIndex(2)?.stringValue ?? "unknown"))
        }
        var mailboxes: [MailAppMailboxRecord] = []
        for offset in 0..<mailboxRows.numberOfItems {
            guard let row = mailboxRows.atIndex(offset + 1), row.numberOfItems == 5,
                  let accountKey = row.atIndex(1)?.stringValue, !accountKey.isEmpty,
                  let path = row.atIndex(2)?.stringValue, !path.isEmpty,
                  let name = row.atIndex(3)?.stringValue else { continue }
            mailboxes.append(MailAppMailboxRecord(
                accountKey: accountKey,
                path: path,
                name: name,
                totalCount: max(0, Int(row.atIndex(4)?.int32Value ?? 0)),
                unreadCount: max(0, Int(row.atIndex(5)?.int32Value ?? 0))
            ))
        }
        var messages: [MailAppMessageRecord] = []
        for offset in 0..<messageRows.numberOfItems {
            guard let row = messageRows.atIndex(offset + 1), row.numberOfItems == 3,
                  let accountKey = row.atIndex(1)?.stringValue,
                  let mailboxPath = row.atIndex(2)?.stringValue,
                  let messageRow = row.atIndex(3) else { continue }
            if let message = try? parseMessage(messageRow, accountKey: accountKey, mailboxPath: mailboxPath) {
                messages.append(message)
            }
        }
        return MailAppMetadataSnapshot(
            accounts: accounts,
            mailboxes: mailboxes,
            messages: messages,
            accountLimitReached: descriptor.atIndex(4)?.booleanValue ?? false,
            mailboxLimitReached: descriptor.atIndex(5)?.booleanValue ?? false,
            messageLimitReached: descriptor.atIndex(6)?.booleanValue ?? false
        )
    }

    static func parseMessage(
        _ row: NSAppleEventDescriptor,
        accountKey: String,
        mailboxPath: String
    ) throws -> MailAppMessageRecord {
        guard row.numberOfItems == 11 else { throw MailAppBridgeError.executionFailed }
        let rowID = Int64(row.atIndex(1)?.int32Value ?? 0)
        guard rowID > 0 else { throw MailAppBridgeError.messageNotFound }
        let recipients = row.atIndex(11)
        var to: [String] = []
        if let recipients {
            for offset in 0..<recipients.numberOfItems {
                if let value = recipients.atIndex(offset + 1)?.stringValue { to.append(value) }
            }
        }
        let rawMessageID = row.atIndex(2)?.stringValue
        return MailAppMessageRecord(
            locator: MailAppMessageLocator(rowID: rowID, accountID: accountKey, mailboxName: mailboxPath),
            messageID: rawMessageID.flatMap { $0.isEmpty ? nil : $0 },
            subject: row.atIndex(3)?.stringValue ?? "",
            sender: row.atIndex(4)?.stringValue ?? "",
            sentAt: row.atIndex(5)?.dateValue,
            receivedAt: row.atIndex(6)?.dateValue,
            read: row.atIndex(7)?.booleanValue ?? false,
            flagged: row.atIndex(8)?.booleanValue ?? false,
            attachmentCount: max(0, Int(row.atIndex(9)?.int32Value ?? 0)),
            sizeBytes: max(0, Int(row.atIndex(10)?.int32Value ?? 0)),
            to: to
        )
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
}
