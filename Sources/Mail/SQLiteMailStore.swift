import Foundation
import SQLite3

public struct SQLiteMailStore {
    public static let maximumTextSearchCandidates = 200
    public static let textSearchDeadlineMilliseconds: UInt64 = 1_000
    private let databaseURL: URL
    private let mailStoreURL: URL
    private let mailAppBridge: any MailAppBridging

    public init(
        databaseURL: URL,
        mailStoreURL: URL? = nil,
        mailAppBridge: any MailAppBridging = MailAppBridge()
    ) {
        self.databaseURL = databaseURL
        self.mailStoreURL = mailStoreURL ?? databaseURL.deletingLastPathComponent().deletingLastPathComponent()
        self.mailAppBridge = mailAppBridge
    }

    public func accounts() throws -> [MailAccountSummary] {
        let mailboxes = try loadMailboxRows()
        var grouped: [String: (kind: String, mailboxCount: Int, totalCount: Int, unreadCount: Int)] = [:]
        for mailbox in mailboxes {
            let accountID = MailOpaqueID.account(key: mailbox.accountKey)
            var value = grouped[accountID] ?? (mailbox.kind, 0, 0, 0)
            value.mailboxCount += 1
            value.totalCount += mailbox.totalCount
            value.unreadCount += mailbox.unreadCount
            grouped[accountID] = value
        }
        return grouped.map { id, value in
            MailAccountSummary(
                id: id,
                kind: value.kind,
                mailboxCount: value.mailboxCount,
                totalCount: value.totalCount,
                unreadCount: value.unreadCount
            )
        }.sorted { ($0.kind, $0.id) < ($1.kind, $1.id) }
    }

    public func threads(limit: Int = 50) throws -> MailThreadListResult {
        guard (1...200).contains(limit) else { throw MailStoreError.invalidLimit }
        let rows: [(id: Int64, count: Int, latest: Int64)] = try withDatabase { database in
            let sql = "SELECT conversation_id, COUNT(*), MAX(COALESCE(date_received, 0)) FROM messages WHERE deleted = 0 AND conversation_id > 0 GROUP BY conversation_id ORDER BY MAX(COALESCE(date_received, 0)) DESC, conversation_id DESC LIMIT ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw MailStoreError.queryFailed }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, Int64(limit + 1)) == SQLITE_OK else { throw MailStoreError.queryFailed }
            var result: [(Int64, Int, Int64)] = []
            while sqlite3_step(statement) == SQLITE_ROW { result.append((sqlite3_column_int64(statement, 0), Int(sqlite3_column_int64(statement, 1)), sqlite3_column_int64(statement, 2))) }
            return result
        }
        let truncated = rows.count > limit
        let selected = Array(rows.prefix(limit))
        return MailThreadListResult(
            backend: "sqlite",
            items: selected.map { MailThreadSummary(id: MailOpaqueID.conversation($0.id), messageCount: $0.count, latestReceivedAt: iso8601(epochSeconds: $0.latest)) },
            limit: limit,
            truncated: truncated,
            complete: !truncated,
            limitations: []
        )
    }

    public func mailboxes(accountID: String? = nil) throws -> [MailboxSummary] {
        let rows = try loadMailboxRows()
        if let accountID, !rows.contains(where: { MailOpaqueID.account(key: $0.accountKey) == accountID }) {
            throw MailStoreError.accountNotFound
        }
        return rows.compactMap { row in
            let rowAccountID = MailOpaqueID.account(key: row.accountKey)
            guard accountID == nil || accountID == rowAccountID else { return nil }
            return MailboxSummary(
                id: MailOpaqueID.mailbox(rowID: row.rowID),
                accountID: rowAccountID,
                name: row.name,
                totalCount: row.totalCount,
                unreadCount: row.unreadCount
            )
        }.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }
    }

    public func query(_ query: MailQuery) throws -> MailQueryResult {
        let started = DispatchTime.now().uptimeNanoseconds
        guard (1...200).contains(query.limit) else { throw MailStoreError.invalidLimit }
        let mailboxRows = try loadMailboxRows()
        let mailboxByID = Dictionary(uniqueKeysWithValues: mailboxRows.map { ($0.rowID, $0) })
        var conditions = ["m.deleted = 0"]
        var bindings: [SQLiteBinding] = []

        if let accountID = query.accountID {
            let rowIDs = mailboxRows.filter { MailOpaqueID.account(key: $0.accountKey) == accountID }.map(\.rowID)
            guard !rowIDs.isEmpty else { throw MailStoreError.accountNotFound }
            conditions.append("m.mailbox IN (\(Array(repeating: "?", count: rowIDs.count).joined(separator: ",")))")
            bindings.append(contentsOf: rowIDs.map(SQLiteBinding.integer))
        }
        if let mailboxID = query.mailboxID {
            guard let rowID = MailOpaqueID.mailboxRowID(mailboxID), mailboxByID[rowID] != nil else {
                throw MailStoreError.invalidOpaqueID
            }
            conditions.append("m.mailbox = ?")
            bindings.append(.integer(rowID))
        }
        if let from = query.from {
            conditions.append("a.address LIKE ? COLLATE NOCASE")
            bindings.append(.text("%\(from)%"))
        }
        if let to = query.to {
            conditions.append("EXISTS (SELECT 1 FROM recipients r JOIN addresses ra ON ra.ROWID = r.address WHERE r.message = m.ROWID AND ra.address LIKE ? COLLATE NOCASE)")
            bindings.append(.text("%\(to)%"))
        }
        if let subject = query.subject {
            conditions.append("s.subject LIKE ? COLLATE NOCASE")
            bindings.append(.text("%\(subject)%"))
        }
        if let receivedAfter = query.receivedAfter {
            conditions.append("m.date_received >= ?")
            bindings.append(.integer(Int64(receivedAfter.timeIntervalSince1970)))
        }
        if let receivedBefore = query.receivedBefore {
            conditions.append("m.date_received < ?")
            bindings.append(.integer(Int64(receivedBefore.timeIntervalSince1970)))
        }
        if let unread = query.unread {
            conditions.append(unread ? "m.read = 0" : "m.read != 0")
        }
        if let flagged = query.flagged {
            conditions.append(flagged ? "m.flagged != 0" : "m.flagged = 0")
        }
        if let hasAttachment = query.hasAttachment {
            conditions.append(hasAttachment
                ? "EXISTS (SELECT 1 FROM attachments af WHERE af.message = m.ROWID)"
                : "NOT EXISTS (SELECT 1 FROM attachments af WHERE af.message = m.ROWID)")
        }
        if let cursor = query.cursor {
            guard let (received, rowID) = MailOpaqueID.cursorValues(cursor) else { throw MailStoreError.invalidOpaqueID }
            guard try cursorExists(received: received, rowID: rowID) else { throw MailStoreError.invalidOpaqueID }
            conditions.append("(COALESCE(m.date_received, 0) < ? OR (COALESCE(m.date_received, 0) = ? AND m.ROWID < ?))")
            bindings.append(contentsOf: [.integer(received), .integer(received), .integer(rowID)])
        }

        let sql = """
        SELECT m.ROWID, m.mailbox, COALESCE(m.date_sent, 0), COALESCE(m.date_received, 0),
               m.read, m.flagged, m.size, s.subject, COALESCE(a.address, ''),
               EXISTS (SELECT 1 FROM attachments ax WHERE ax.message = m.ROWID),
               NULLIF(g.message_id_header, '')
        FROM messages m
        JOIN subjects s ON s.ROWID = m.subject
        LEFT JOIN addresses a ON a.ROWID = m.sender
        LEFT JOIN message_global_data g ON g.ROWID = m.global_message_id
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY m.date_received DESC, m.ROWID DESC
        LIMIT ?
        """
        bindings.append(.integer(Int64(query.limit + 1)))

        let rows = try withDatabase { database in
            try queryRows(database: database, sql: sql, bindings: bindings, deadlineMilliseconds: 250)
        }
        let truncated = rows.count > query.limit
        let selectedRows = Array(rows.prefix(query.limit))
        let messages = selectedRows.compactMap { row -> MailMessageMetadata? in
            guard let mailbox = mailboxByID[row.mailboxRowID] else { return nil }
            return MailMessageMetadata(
                id: MailOpaqueID.message(rowID: row.rowID),
                idScope: "local",
                messageID: row.messageID,
                accountID: MailOpaqueID.account(key: mailbox.accountKey),
                mailboxID: MailOpaqueID.mailbox(rowID: mailbox.rowID),
                subject: row.subject,
                sender: row.sender,
                sentAt: iso8601(epochSeconds: row.dateSent),
                receivedAt: iso8601(epochSeconds: row.dateReceived),
                unread: !row.read,
                flagged: row.flagged,
                hasAttachment: row.attachmentCount > 0,
                sizeBytes: row.size,
                cacheState: "metadata_only"
            )
        }
        let nextCursor: String?
        if truncated, let last = selectedRows.last {
            nextCursor = MailOpaqueID.cursor(received: last.dateReceived, rowID: last.rowID)
        } else {
            nextCursor = nil
        }
        return MailQueryResult(
            backend: "sqlite",
            cacheState: "metadata_only",
            messages: messages,
            truncated: truncated,
            nextCursor: nextCursor,
            elapsedMs: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
            fallbackReason: nil,
            incomplete: false,
            limitations: []
        )
    }

    public func searchText(_ term: String, query: MailQuery = MailQuery(), resultLimit: Int = 50) throws -> MailTextSearchResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else { throw MailStoreError.invalidArgument("Mail text search requires a non-empty --text value.") }
        guard (1...200).contains(resultLimit) else { throw MailStoreError.invalidLimit }
        guard query.cursor == nil else { throw MailStoreError.invalidOpaqueID }

        var boundedQuery = query
        boundedQuery.limit = Self.maximumTextSearchCandidates
        let candidates = try self.query(boundedQuery)
        let deadline = started + Self.textSearchDeadlineMilliseconds * 1_000_000
        var matches: [MailMessageMetadata] = []
        var scanned = 0
        var limitations = Set<String>()

        for candidate in candidates.messages {
            guard DispatchTime.now().uptimeNanoseconds <= deadline else {
                limitations.insert("mail_text_search_timeout")
                break
            }
            scanned += 1
            let extracted: MailExtractedText?
            do {
                extracted = try cachedText(for: candidate.id)
            } catch {
                limitations.insert("mail_text_search_cache_unreadable")
                continue
            }
            guard let extracted else {
                limitations.insert("mail_text_search_cache_miss")
                continue
            }
            if extracted.truncated { limitations.insert("text_truncated") }
            if let body = extracted.text, body.localizedCaseInsensitiveContains(normalizedTerm) {
                matches.append(candidate)
                if matches.count >= resultLimit { break }
            }
        }

        if candidates.truncated { limitations.insert("mail_text_search_candidate_cap_reached") }
        let truncated = candidates.truncated || matches.count >= resultLimit
        let complete = !truncated && !limitations.contains("mail_text_search_timeout")
        return MailTextSearchResult(
            backend: "sqlite_emlx",
            items: matches,
            text: normalizedTerm,
            scanned: scanned,
            limit: resultLimit,
            truncated: truncated,
            complete: complete,
            elapsedMs: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
            limitations: limitations.sorted()
        )
    }

    public func get(id: String, projection: MailContentProjection = .metadata) throws -> MailGetResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let resolved = try resolveMessage(id: id)
        let location = try EmlxPathResolver(mailStoreURL: mailStoreURL)
            .resolve(rowID: resolved.row.rowID, mailboxURL: resolved.mailboxURL)
        let cacheState = location?.cacheState ?? .metadataOnly
        let metadata = makeMetadata(row: resolved.row, mailbox: resolved.mailbox, cacheState: cacheState)

        guard projection != .raw else {
            throw MailStoreError.invalidArgument("Raw content requires --output <file|->.")
        }
        guard projection == .text else {
            return MailGetResult(
                backend: "sqlite",
                cacheState: cacheState.rawValue,
                message: metadata,
                content: nil,
                elapsedMs: elapsedMilliseconds(since: started),
                fallbackReason: nil,
                incomplete: cacheState == .partial,
                limitations: cacheState == .partial ? ["partial_emlx"] : []
            )
        }
        guard let location else {
            return try mailAppTextFallback(
                resolved: resolved,
                originalCacheState: .metadataOnly,
                fallbackReason: "content_not_cached",
                started: started
            )
        }

        let payload: EmlxPayload
        do {
            payload = try EmlxReader().read(location: location)
        } catch MailStoreError.contentNotCached {
            return try mailAppTextFallback(
                resolved: resolved,
                originalCacheState: .metadataOnly,
                fallbackReason: "content_not_cached",
                started: started
            )
        }
        let extracted = try MailTextExtractor().extract(from: payload.rfc822)
        if payload.cacheState == .partial, extracted.text == nil {
            return try mailAppTextFallback(
                resolved: resolved,
                originalCacheState: .partial,
                fallbackReason: "partial_emlx",
                started: started
            )
        }
        var limitations: [String] = []
        if payload.cacheState == .partial { limitations.append("partial_emlx") }
        if extracted.truncated { limitations.append("text_truncated") }
        return MailGetResult(
            backend: "sqlite_emlx",
            cacheState: payload.cacheState.rawValue,
            message: metadata,
            content: MailTextContent(text: extracted.text, truncated: extracted.truncated),
            elapsedMs: elapsedMilliseconds(since: started),
            fallbackReason: payload.cacheState == .partial ? "partial_emlx" : nil,
            incomplete: payload.cacheState == .partial || extracted.truncated,
            limitations: limitations
        )
    }

    private func cachedText(for id: String) throws -> MailExtractedText? {
        let resolved = try resolveMessage(id: id)
        guard let location = try EmlxPathResolver(mailStoreURL: mailStoreURL)
            .resolve(rowID: resolved.row.rowID, mailboxURL: resolved.mailboxURL) else { return nil }
        let payload = try EmlxReader().read(location: location)
        return try MailTextExtractor().extract(from: payload.rfc822)
    }

    public func reveal(id: String) throws -> MailRevealResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let resolved = try resolveMessage(id: id)
        guard let locator = resolved.mailAppLocator else { throw MailStoreError.mailAppMessageNotFound }
        do {
            try mailAppBridge.reveal(locator: locator)
        } catch let error as MailAppBridgeError {
            throw mapMailAppError(error)
        }
        return MailRevealResult(
            backend: "mail_app",
            id: id,
            revealed: true,
            elapsedMs: elapsedMilliseconds(since: started),
            limitations: ["visible_mail_app_navigation"]
        )
    }

    public func verifyAttachments(id: String) throws -> MailAttachmentVerificationResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let resolved = try resolveMessage(id: id)
        let sqliteCount = resolved.row.attachmentCount
        guard let location = try EmlxPathResolver(mailStoreURL: mailStoreURL)
            .resolve(rowID: resolved.row.rowID, mailboxURL: resolved.mailboxURL) else {
            return MailAttachmentVerificationResult(
                backend: "sqlite",
                id: id,
                cacheState: MailCacheState.metadataOnly.rawValue,
                sqliteCount: sqliteCount,
                mimeCount: nil,
                matched: false,
                elapsedMs: elapsedMilliseconds(since: started),
                incomplete: true,
                limitations: ["attachment_cross_check_unavailable"]
            )
        }

        let payload: EmlxPayload
        do {
            payload = try EmlxReader().read(location: location)
        } catch MailStoreError.contentNotCached {
            return MailAttachmentVerificationResult(
                backend: "sqlite",
                id: id,
                cacheState: MailCacheState.metadataOnly.rawValue,
                sqliteCount: sqliteCount,
                mimeCount: nil,
                matched: false,
                elapsedMs: elapsedMilliseconds(since: started),
                incomplete: true,
                limitations: ["attachment_cross_check_unavailable"]
            )
        }
        let mimeCount = try MailAttachmentInspector().inspect(payload.rfc822).attachmentCount
        let matched = payload.cacheState == .complete && sqliteCount == mimeCount
        var limitations: [String] = []
        if payload.cacheState == .partial { limitations.append("partial_emlx") }
        if sqliteCount != mimeCount { limitations.append("attachment_count_mismatch") }
        return MailAttachmentVerificationResult(
            backend: "sqlite_emlx",
            id: id,
            cacheState: payload.cacheState.rawValue,
            sqliteCount: sqliteCount,
            mimeCount: mimeCount,
            matched: matched,
            elapsedMs: elapsedMilliseconds(since: started),
            incomplete: !matched,
            limitations: limitations
        )
    }

    public func exportAttachments(id: String, to directory: URL) throws -> MailAttachmentExportResult {
        let resolved = try resolveMessage(id: id)
        guard let location = try EmlxPathResolver(mailStoreURL: mailStoreURL)
            .resolve(rowID: resolved.row.rowID, mailboxURL: resolved.mailboxURL) else {
            throw MailStoreError.contentNotCached
        }
        let payload = try EmlxReader().read(location: location)
        let attachments = try MailAttachmentExtractor().extract(payload.rfc822)
        let outputDirectory = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let safeNames = try attachments.map { attachment -> (MailAttachment, URL) in
            let filename = attachment.filename
            guard !filename.isEmpty, filename != ".", filename != "..",
                  filename == URL(fileURLWithPath: filename).lastPathComponent,
                  !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0") else {
                throw MailStoreError.invalidArgument("Attachment filename is unsafe.")
            }
            let target = outputDirectory.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
            guard target.deletingLastPathComponent().path == outputDirectory.path else { throw MailStoreError.invalidArgument("Attachment path escapes the output directory.") }
            guard !FileManager.default.fileExists(atPath: target.path) else { throw MailStoreError.outputAlreadyExists }
            return (attachment, target)
        }
        for (attachment, target) in safeNames {
            try attachment.data.write(to: target, options: .withoutOverwriting)
        }
        return MailAttachmentExportResult(
            backend: "sqlite_emlx",
            id: id,
            outputDirectory: outputDirectory.path,
            files: safeNames.map { attachment, target in
                MailAttachmentExportItem(filename: attachment.filename, path: target.path, bytes: attachment.data.count, contentType: attachment.contentType)
            },
            incomplete: payload.cacheState == .partial,
            limitations: payload.cacheState == .partial ? ["partial_emlx"] : []
        )
    }

    public func rawMessage(id: String) throws -> MailRawMessage {
        let resolved = try resolveMessage(id: id)
        guard let location = try EmlxPathResolver(mailStoreURL: mailStoreURL)
            .resolve(rowID: resolved.row.rowID, mailboxURL: resolved.mailboxURL) else {
            throw MailStoreError.contentNotCached
        }
        let payload = try EmlxReader().read(location: location)
        let metadata = makeMetadata(row: resolved.row, mailbox: resolved.mailbox, cacheState: payload.cacheState)
        return MailRawMessage(
            data: payload.rfc822,
            cacheState: payload.cacheState.rawValue,
            message: metadata,
            incomplete: payload.cacheState == .partial,
            limitations: payload.cacheState == .partial ? ["partial_emlx"] : []
        )
    }

    private func resolveMessage(id: String) throws -> ResolvedMessage {
        guard let rowID = MailOpaqueID.messageRowID(id) else { throw MailStoreError.invalidOpaqueID }
        return try withDatabase { database in
            let sql = """
            SELECT m.ROWID, m.mailbox, COALESCE(m.date_sent, 0), COALESCE(m.date_received, 0),
                   m.read, m.flagged, m.size, s.subject, COALESCE(a.address, ''),
                   (SELECT COUNT(*) FROM attachments ax WHERE ax.message = m.ROWID),
                   NULLIF(g.message_id_header, ''), mb.url, mb.total_count, mb.unread_count
            FROM messages m
            JOIN mailboxes mb ON mb.ROWID = m.mailbox
            JOIN subjects s ON s.ROWID = m.subject
            LEFT JOIN addresses a ON a.ROWID = m.sender
            LEFT JOIN message_global_data g ON g.ROWID = m.global_message_id
            WHERE m.ROWID = ? AND m.deleted = 0
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw MailStoreError.queryFailed
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, rowID) == SQLITE_OK else { throw MailStoreError.queryFailed }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw MailStoreError.staleLocalID }
            let mailboxURL = columnText(statement, 11)
            let parsed = parseMailboxURL(mailboxURL)
            let mailbox = MailboxRow(
                rowID: sqlite3_column_int64(statement, 1),
                accountKey: parsed.accountKey,
                kind: parsed.kind,
                name: parsed.name,
                totalCount: Int(sqlite3_column_int64(statement, 12)),
                unreadCount: Int(sqlite3_column_int64(statement, 13))
            )
            return ResolvedMessage(
                row: messageRow(statement),
                mailbox: mailbox,
                mailboxURL: mailboxURL,
                mailAppLocator: makeMailAppLocator(rowID: rowID, mailboxURL: mailboxURL)
            )
        }
    }

    private func mailAppTextFallback(
        resolved: ResolvedMessage,
        originalCacheState: MailCacheState,
        fallbackReason: String,
        started: UInt64
    ) throws -> MailGetResult {
        guard let locator = resolved.mailAppLocator else {
            return unavailableFallbackResult(
                resolved: resolved,
                cacheState: originalCacheState,
                fallbackReason: "mail_app_locator_unavailable",
                limitation: "mail_app_locator_unavailable",
                started: started
            )
        }
        do {
            let text = try mailAppBridge.readText(locator: locator)
            let maximumBytes = 2 * 1_024 * 1_024
            let truncated = text.utf8.count > maximumBytes
            let boundedText = truncated
                ? String(decoding: text.utf8.prefix(maximumBytes), as: UTF8.self)
                : text
            var limitations = ["mail_app_text_fallback"]
            if truncated { limitations.append("text_truncated") }
            return MailGetResult(
                backend: "mail_app",
                cacheState: MailCacheState.unknown.rawValue,
                message: makeMetadata(row: resolved.row, mailbox: resolved.mailbox, cacheState: .unknown),
                content: MailTextContent(text: boundedText, truncated: truncated),
                elapsedMs: elapsedMilliseconds(since: started),
                fallbackReason: fallbackReason,
                incomplete: truncated,
                limitations: limitations
            )
        } catch let error as MailAppBridgeError {
            switch error {
            case .timedOut, .circuitOpen:
                throw mapMailAppError(error)
            case .automationDenied:
                return unavailableFallbackResult(
                    resolved: resolved,
                    cacheState: originalCacheState,
                    fallbackReason: "automation_denied",
                    limitation: "mail_app_automation_denied",
                    started: started
                )
            case .mailNotRunning:
                return unavailableFallbackResult(
                    resolved: resolved,
                    cacheState: originalCacheState,
                    fallbackReason: "mail_app_not_running",
                    limitation: "mail_app_not_running",
                    started: started
                )
            case .messageNotFound:
                return unavailableFallbackResult(
                    resolved: resolved,
                    cacheState: originalCacheState,
                    fallbackReason: "mail_app_message_not_found",
                    limitation: "mail_app_message_not_found",
                    started: started
                )
            case .executionFailed:
                return unavailableFallbackResult(
                    resolved: resolved,
                    cacheState: originalCacheState,
                    fallbackReason: "mail_app_execution_failed",
                    limitation: "mail_app_execution_failed",
                    started: started
                )
            }
        }
    }

    private func unavailableFallbackResult(
        resolved: ResolvedMessage,
        cacheState: MailCacheState,
        fallbackReason: String,
        limitation: String,
        started: UInt64
    ) -> MailGetResult {
        MailGetResult(
            backend: "sqlite",
            cacheState: cacheState.rawValue,
            message: makeMetadata(row: resolved.row, mailbox: resolved.mailbox, cacheState: cacheState),
            content: MailTextContent(text: nil, truncated: false),
            elapsedMs: elapsedMilliseconds(since: started),
            fallbackReason: fallbackReason,
            incomplete: true,
            limitations: [limitation]
        )
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

    private func makeMetadata(row: MessageRow, mailbox: MailboxRow, cacheState: MailCacheState) -> MailMessageMetadata {
        MailMessageMetadata(
            id: MailOpaqueID.message(rowID: row.rowID),
            idScope: "local",
            messageID: row.messageID,
            accountID: MailOpaqueID.account(key: mailbox.accountKey),
            mailboxID: MailOpaqueID.mailbox(rowID: mailbox.rowID),
            subject: row.subject,
            sender: row.sender,
            sentAt: iso8601(epochSeconds: row.dateSent),
            receivedAt: iso8601(epochSeconds: row.dateReceived),
            unread: !row.read,
            flagged: row.flagged,
            hasAttachment: row.attachmentCount > 0,
            sizeBytes: row.size,
            cacheState: cacheState.rawValue
        )
    }

    private func loadMailboxRows() throws -> [MailboxRow] {
        try withDatabase { database in
            let sql = "SELECT ROWID, url, total_count, unread_count FROM mailboxes ORDER BY ROWID"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw MailStoreError.queryFailed
            }
            defer { sqlite3_finalize(statement) }
            var result: [MailboxRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let rowID = sqlite3_column_int64(statement, 0)
                guard let rawURL = sqlite3_column_text(statement, 1) else { continue }
                let parsed = parseMailboxURL(String(cString: rawURL))
                result.append(MailboxRow(
                    rowID: rowID,
                    accountKey: parsed.accountKey,
                    kind: parsed.kind,
                    name: parsed.name,
                    totalCount: Int(sqlite3_column_int64(statement, 2)),
                    unreadCount: Int(sqlite3_column_int64(statement, 3))
                ))
            }
            return result
        }
    }

    private func cursorExists(received: Int64, rowID: Int64) throws -> Bool {
        try withDatabase { database in
            let sql = "SELECT 1 FROM messages WHERE ROWID = ? AND COALESCE(date_received, 0) = ? AND deleted = 0 LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw MailStoreError.queryFailed
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, rowID) == SQLITE_OK,
                  sqlite3_bind_int64(statement, 2, received) == SQLITE_OK else {
                throw MailStoreError.queryFailed
            }
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw MailStoreError.databaseUnavailable
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else {
            throw MailStoreError.databaseUnavailable
        }
        sqlite3_busy_timeout(database, 100)
        return try body(database)
    }

    private func queryRows(
        database: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding],
        deadlineMilliseconds: UInt64
    ) throws -> [MessageRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MailStoreError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch binding {
            case .integer(let value): status = sqlite3_bind_int64(statement, index, value)
            case .text(let value): status = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            }
            guard status == SQLITE_OK else { throw MailStoreError.queryFailed }
        }

        let deadline = SQLiteDeadline(milliseconds: deadlineMilliseconds)
        let context = Unmanaged.passRetained(deadline)
        sqlite3_progress_handler(database, 1_000, mailSQLiteProgressCallback, context.toOpaque())
        defer {
            sqlite3_progress_handler(database, 0, nil, nil)
            context.release()
        }

        var rows: [MessageRow] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw MailStoreError.queryFailed }
            rows.append(messageRow(statement))
        }
        return rows
    }

    private func messageRow(_ statement: OpaquePointer) -> MessageRow {
        MessageRow(
            rowID: sqlite3_column_int64(statement, 0),
            mailboxRowID: sqlite3_column_int64(statement, 1),
            dateSent: sqlite3_column_int64(statement, 2),
            dateReceived: sqlite3_column_int64(statement, 3),
            read: sqlite3_column_int(statement, 4) != 0,
            flagged: sqlite3_column_int(statement, 5) != 0,
            size: Int(sqlite3_column_int64(statement, 6)),
            subject: columnText(statement, 7),
            sender: columnText(statement, 8),
            attachmentCount: Int(sqlite3_column_int64(statement, 9)),
            messageID: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : columnText(statement, 10)
        )
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map(String.init(cString:)) ?? ""
    }

    private func parseMailboxURL(_ value: String) -> (accountKey: String, kind: String, name: String) {
        let scheme = value.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() ?? "unknown"
        let marker = "://"
        let remainder = value.range(of: marker).map { String(value[$0.upperBound...]) } ?? value
        let slash = remainder.firstIndex(of: "/")
        let authority = slash.map { String(remainder[..<$0]) } ?? remainder
        let path = slash.map { String(remainder[remainder.index(after: $0)...]) } ?? ""
        let decodedName = path.split(separator: "/").last.map(String.init)?.removingPercentEncoding
        let name = decodedName.flatMap { $0.isEmpty ? nil : $0 } ?? scheme
        return (
            accountKey: scheme + "://" + (authority.isEmpty ? "local" : authority.lowercased()),
            kind: scheme,
            name: name
        )
    }

    private func makeMailAppLocator(rowID: Int64, mailboxURL: String) -> MailAppMessageLocator? {
        guard let marker = mailboxURL.range(of: "://") else { return nil }
        let remainder = String(mailboxURL[marker.upperBound...])
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let encodedAccountID = String(remainder[..<slash])
        let encodedPath = String(remainder[remainder.index(after: slash)...])
        guard
            let accountID = encodedAccountID.removingPercentEncoding,
            let mailboxPath = encodedPath.removingPercentEncoding,
            !accountID.isEmpty,
            !mailboxPath.isEmpty,
            !mailboxPath.split(separator: "/", omittingEmptySubsequences: true).isEmpty
        else { return nil }
        return MailAppMessageLocator(rowID: rowID, accountID: accountID, mailboxPath: mailboxPath)
    }

    private func elapsedMilliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private func iso8601(epochSeconds: Int64) -> String? {
        guard epochSeconds > 0 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }
}

private struct MailboxRow {
    let rowID: Int64
    let accountKey: String
    let kind: String
    let name: String
    let totalCount: Int
    let unreadCount: Int
}

private struct MessageRow {
    let rowID: Int64
    let mailboxRowID: Int64
    let dateSent: Int64
    let dateReceived: Int64
    let read: Bool
    let flagged: Bool
    let size: Int
    let subject: String
    let sender: String
    let attachmentCount: Int
    let messageID: String?
}

private struct ResolvedMessage {
    let row: MessageRow
    let mailbox: MailboxRow
    let mailboxURL: String
    let mailAppLocator: MailAppMessageLocator?
}

private enum SQLiteBinding {
    case integer(Int64)
    case text(String)
}

private final class SQLiteDeadline {
    let deadline: UInt64
    init(milliseconds: UInt64) {
        deadline = DispatchTime.now().uptimeNanoseconds + milliseconds * 1_000_000
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func mailSQLiteProgressCallback(_ context: UnsafeMutableRawPointer?) -> Int32 {
    guard let context else { return 1 }
    let deadline = Unmanaged<SQLiteDeadline>.fromOpaque(context).takeUnretainedValue()
    return DispatchTime.now().uptimeNanoseconds >= deadline.deadline ? 1 : 0
}
