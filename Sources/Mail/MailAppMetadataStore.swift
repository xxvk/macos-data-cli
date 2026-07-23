import Foundation

public struct MailAppAccountRecord: Equatable, Sendable {
    public let key: String
    public let kind: String

    public init(key: String, kind: String) {
        self.key = key
        self.kind = kind
    }
}

public struct MailAppMailboxRecord: Equatable, Sendable {
    public let accountKey: String
    public let path: String
    public let name: String
    public let totalCount: Int
    public let unreadCount: Int

    public init(accountKey: String, path: String, name: String, totalCount: Int, unreadCount: Int) {
        self.accountKey = accountKey
        self.path = path
        self.name = name
        self.totalCount = totalCount
        self.unreadCount = unreadCount
    }
}

public struct MailAppMessageRecord: Equatable, Sendable {
    public let locator: MailAppMessageLocator
    public let messageID: String?
    public let subject: String
    public let sender: String
    public let sentAt: Date?
    public let receivedAt: Date?
    public let read: Bool
    public let flagged: Bool
    public let attachmentCount: Int
    public let sizeBytes: Int
    public let to: [String]

    public init(
        locator: MailAppMessageLocator,
        messageID: String?,
        subject: String,
        sender: String,
        sentAt: Date?,
        receivedAt: Date?,
        read: Bool,
        flagged: Bool,
        attachmentCount: Int,
        sizeBytes: Int,
        to: [String]
    ) {
        self.locator = locator
        self.messageID = messageID
        self.subject = subject
        self.sender = sender
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.read = read
        self.flagged = flagged
        self.attachmentCount = attachmentCount
        self.sizeBytes = sizeBytes
        self.to = to
    }
}

public struct MailAppMetadataSnapshot: Equatable, Sendable {
    public let accounts: [MailAppAccountRecord]
    public let mailboxes: [MailAppMailboxRecord]
    public let messages: [MailAppMessageRecord]
    public let accountLimitReached: Bool
    public let mailboxLimitReached: Bool
    public let messageLimitReached: Bool

    public init(
        accounts: [MailAppAccountRecord],
        mailboxes: [MailAppMailboxRecord],
        messages: [MailAppMessageRecord],
        accountLimitReached: Bool = false,
        mailboxLimitReached: Bool = false,
        messageLimitReached: Bool = false
    ) {
        self.accounts = accounts
        self.mailboxes = mailboxes
        self.messages = messages
        self.accountLimitReached = accountLimitReached
        self.mailboxLimitReached = mailboxLimitReached
        self.messageLimitReached = messageLimitReached
    }
}

public protocol MailAppMetadataBridging: Sendable {
    func snapshot(maximumAccounts: Int, maximumMailboxes: Int, maximumMessages: Int) throws -> MailAppMetadataSnapshot
    func metadata(locator: MailAppMessageLocator) throws -> MailAppMessageRecord
}

public struct MailAppMetadataStore {
    public static let maximumAccounts = 32
    public static let maximumMailboxes = 200
    public static let maximumMessages = 25

    private let metadataBridge: any MailAppMetadataBridging
    private let contentBridge: any MailAppBridging
    private let fallbackReason: String

    public init(
        metadataBridge: any MailAppMetadataBridging = SystemMailAppMetadataBridge(),
        contentBridge: any MailAppBridging = MailAppBridge(),
        fallbackReason: String
    ) {
        self.metadataBridge = metadataBridge
        self.contentBridge = contentBridge
        self.fallbackReason = fallbackReason
    }

    public func accounts() throws -> MailAccountListResult {
        let snapshot = try loadSnapshot(maximumMessages: 0)
        let accounts = snapshot.accounts.map { account in
            let boxes = snapshot.mailboxes.filter { $0.accountKey == account.key }
            return MailAccountSummary(
                id: MailOpaqueID.account(key: account.key),
                kind: normalizedKind(account.kind),
                mailboxCount: boxes.count,
                totalCount: boxes.reduce(0) { $0 + $1.totalCount },
                unreadCount: boxes.reduce(0) { $0 + $1.unreadCount }
            )
        }.sorted { ($0.kind, $0.id) < ($1.kind, $1.id) }
        return MailAccountListResult(backend: "mail_app", accounts: accounts, limitations: limitations(snapshot))
    }

    public func mailboxes(accountID: String? = nil) throws -> MailboxListResult {
        let snapshot = try loadSnapshot(maximumMessages: 0)
        if let accountID, !snapshot.accounts.contains(where: { MailOpaqueID.account(key: $0.key) == accountID }) {
            throw MailStoreError.accountNotFound
        }
        let boxes = snapshot.mailboxes.compactMap { box -> MailboxSummary? in
            let opaqueAccount = MailOpaqueID.account(key: box.accountKey)
            guard accountID == nil || opaqueAccount == accountID else { return nil }
            return MailboxSummary(
                id: MailOpaqueID.mailAppMailbox(accountKey: box.accountKey, mailboxPath: box.path),
                accountID: opaqueAccount,
                name: box.name,
                totalCount: box.totalCount,
                unreadCount: box.unreadCount
            )
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return MailboxListResult(backend: "mail_app", mailboxes: boxes, limitations: limitations(snapshot))
    }

    public func query(_ query: MailQuery) throws -> MailQueryResult {
        let started = DispatchTime.now().uptimeNanoseconds
        guard (1...200).contains(query.limit) else { throw MailStoreError.invalidLimit }
        guard query.cursor == nil else { throw MailStoreError.invalidOpaqueID }
        let snapshot = try loadSnapshot(maximumMessages: Self.maximumMessages)

        if let accountID = query.accountID,
           !snapshot.accounts.contains(where: { MailOpaqueID.account(key: $0.key) == accountID }) {
            throw MailStoreError.accountNotFound
        }
        if let mailboxID = query.mailboxID,
           !snapshot.mailboxes.contains(where: { MailOpaqueID.mailAppMailbox(accountKey: $0.accountKey, mailboxPath: $0.path) == mailboxID }) {
            throw MailStoreError.invalidOpaqueID
        }

        let filtered = snapshot.messages.filter { message in
            let accountID = MailOpaqueID.account(key: message.locator.accountID)
            let mailboxID = MailOpaqueID.mailAppMailbox(
                accountKey: message.locator.accountID,
                mailboxPath: message.locator.mailboxPath
            )
            if let expected = query.accountID, expected != accountID { return false }
            if let expected = query.mailboxID, expected != mailboxID { return false }
            if let value = query.from, !message.sender.localizedCaseInsensitiveContains(value) { return false }
            if let value = query.to, !message.to.contains(where: { $0.localizedCaseInsensitiveContains(value) }) { return false }
            if let value = query.subject, !message.subject.localizedCaseInsensitiveContains(value) { return false }
            if let value = query.receivedAfter, !(message.receivedAt.map { $0 >= value } ?? false) { return false }
            if let value = query.receivedBefore, !(message.receivedAt.map { $0 < value } ?? false) { return false }
            if let value = query.unread, (!message.read) != value { return false }
            if let value = query.flagged, message.flagged != value { return false }
            if let value = query.hasAttachment, (message.attachmentCount > 0) != value { return false }
            return true
        }.sorted {
            let lhsDate = $0.receivedAt ?? .distantPast
            let rhsDate = $1.receivedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return $0.locator.rowID > $1.locator.rowID
        }
        let selected = Array(filtered.prefix(query.limit))
        return MailQueryResult(
            backend: "mail_app",
            cacheState: MailCacheState.unknown.rawValue,
            messages: selected.map(makeMetadata),
            truncated: snapshot.messageLimitReached || filtered.count > query.limit,
            nextCursor: nil,
            elapsedMs: elapsedMilliseconds(since: started),
            fallbackReason: fallbackReason,
            incomplete: true,
            limitations: limitations(snapshot) + ["mail_app_query_cursor_unavailable"]
        )
    }

    public func get(id: String, projection: MailContentProjection = .metadata) throws -> MailGetResult {
        let started = DispatchTime.now().uptimeNanoseconds
        guard projection != .raw else { throw MailStoreError.contentNotCached }
        let locator = try resolveLocator(id: id)
        let record: MailAppMessageRecord
        do {
            record = try metadataBridge.metadata(locator: locator)
        } catch let error as MailAppBridgeError {
            throw mapMailAppError(error)
        }
        guard record.locator == locator else { throw MailStoreError.staleLocalID }
        let metadata = makeMetadata(record)
        if projection == .metadata {
            return MailGetResult(
                backend: "mail_app",
                cacheState: MailCacheState.unknown.rawValue,
                message: metadata,
                content: nil,
                elapsedMs: elapsedMilliseconds(since: started),
                fallbackReason: fallbackReason,
                incomplete: true,
                limitations: ["mail_app_metadata_fallback"]
            )
        }
        do {
            let text = try contentBridge.readText(locator: locator)
            let maximumBytes = 2 * 1_024 * 1_024
            let truncated = text.utf8.count > maximumBytes
            let boundedText = truncated ? String(decoding: text.utf8.prefix(maximumBytes), as: UTF8.self) : text
            var resultLimitations = ["mail_app_text_fallback"]
            if truncated { resultLimitations.append("text_truncated") }
            return MailGetResult(
                backend: "mail_app",
                cacheState: MailCacheState.unknown.rawValue,
                message: metadata,
                content: MailTextContent(text: boundedText, truncated: truncated),
                elapsedMs: elapsedMilliseconds(since: started),
                fallbackReason: fallbackReason,
                incomplete: truncated,
                limitations: resultLimitations
            )
        } catch let error as MailAppBridgeError {
            throw mapMailAppError(error)
        }
    }

    public func reveal(id: String) throws -> MailRevealResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let locator = try resolveLocator(id: id)
        do {
            try contentBridge.reveal(locator: locator)
        } catch let error as MailAppBridgeError {
            throw mapMailAppError(error)
        }
        return MailRevealResult(
            backend: "mail_app",
            id: id,
            revealed: true,
            elapsedMs: elapsedMilliseconds(since: started),
            limitations: ["visible_mail_app_navigation", "mail_app_metadata_fallback"]
        )
    }

    private func resolveLocator(id: String) throws -> MailAppMessageLocator {
        guard let values = MailOpaqueID.mailAppMessageValues(id) else { throw MailStoreError.invalidOpaqueID }
        let snapshot = try loadSnapshot(maximumMessages: 0)
        guard let box = snapshot.mailboxes.first(where: {
            MailOpaqueID.matchesMailAppTokens(
                accountKey: $0.accountKey,
                mailboxPath: $0.path,
                accountToken: values.accountToken,
                mailboxToken: values.mailboxToken
            )
        }) else { throw MailStoreError.staleLocalID }
        return MailAppMessageLocator(rowID: values.rowID, accountID: box.accountKey, mailboxName: box.path)
    }

    private func loadSnapshot(maximumMessages: Int) throws -> MailAppMetadataSnapshot {
        do {
            return try metadataBridge.snapshot(
                maximumAccounts: Self.maximumAccounts,
                maximumMailboxes: Self.maximumMailboxes,
                maximumMessages: maximumMessages
            )
        } catch let error as MailAppBridgeError {
            throw mapMailAppError(error)
        }
    }

    private func makeMetadata(_ record: MailAppMessageRecord) -> MailMessageMetadata {
        MailMessageMetadata(
            id: MailOpaqueID.mailAppMessage(
                rowID: record.locator.rowID,
                accountKey: record.locator.accountID,
                mailboxPath: record.locator.mailboxPath
            ),
            idScope: "mail_app_local",
            messageID: record.messageID,
            accountID: MailOpaqueID.account(key: record.locator.accountID),
            mailboxID: MailOpaqueID.mailAppMailbox(
                accountKey: record.locator.accountID,
                mailboxPath: record.locator.mailboxPath
            ),
            subject: record.subject,
            sender: record.sender,
            sentAt: iso8601(record.sentAt),
            receivedAt: iso8601(record.receivedAt),
            unread: !record.read,
            flagged: record.flagged,
            hasAttachment: record.attachmentCount > 0,
            sizeBytes: record.sizeBytes,
            cacheState: MailCacheState.unknown.rawValue
        )
    }

    private func limitations(_ snapshot: MailAppMetadataSnapshot) -> [String] {
        var values = ["mail_app_bounded_fallback", "mail_app_top_level_mailboxes_only"]
        if snapshot.accountLimitReached { values.append("mail_app_account_limit_reached") }
        if snapshot.mailboxLimitReached { values.append("mail_app_mailbox_limit_reached") }
        if snapshot.messageLimitReached { values.append("mail_app_message_limit_reached") }
        return values
    }

    private func normalizedKind(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " account", with: "").replacingOccurrences(of: " ", with: "_")
    }

    private func iso8601(_ value: Date?) -> String? {
        guard let value else { return nil }
        return ISO8601DateFormatter().string(from: value)
    }

    private func elapsedMilliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private func mapMailAppError(_ error: MailAppBridgeError) -> MailStoreError {
        switch error {
        case .automationDenied: .automationDenied
        case .mailNotRunning: .mailAppNotRunning
        case .timedOut: .mailAppTimedOut
        case .messageNotFound: .mailAppMessageNotFound
        case .circuitOpen: .mailAppCircuitOpen
        case .executionFailed: .mailAppExecutionFailed
        }
    }
}
