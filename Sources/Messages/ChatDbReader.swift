import CryptoKit
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Read-only reader over the local Messages `chat.db`. It opens an immutable
/// read-only connection, verifies a bounded structural schema gate, and runs
/// bounded, deadline-limited `recent` queries. Participant handles and raw
/// local IDs never leave this type.
public struct ChatDbReader {
    public static let defaultLimit = 50
    public static let maximumLimit = 200
    public static let maximumTextProjectionLength = 500
    public static let queryDeadlineMilliseconds: UInt64 = 1_000

    private static let appleEpochOffsetSeconds: Double = 978_307_200

    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    /// SHA-256 over the `sqlite_master` schema, for diagnostics and version
    /// gating. Returns nil when the schema cannot be read.
    public func schemaFingerprint() throws -> String {
        try withDatabase { database in
            let rows = try queryStrings(
                database,
                sql: "SELECT type, name, COALESCE(sql, '') FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name"
            )
            let text = rows.map { $0.joined(separator: ":") }.joined(separator: "\n")
            guard !text.isEmpty else { throw MessagesError.schemaUnsupported }
            return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Structural gate: the required tables and columns must exist, otherwise
    /// the fast path is disabled (fail-closed).
    public func verifySchema() throws {
        try withDatabase { database in
            let required = [
                ("message", ["text", "date", "is_from_me", "service", "handle_id"]),
                ("chat", ["chat_identifier"]),
                ("chat_message_join", ["chat_id", "message_id"]),
            ]
            for (table, columns) in required {
                let found = try queryStrings(database, sql: "PRAGMA table_info(\(table))")
                let names = Set(found.compactMap { $0.count > 1 ? $0[1] : nil })
                for column in columns where !names.contains(column) {
                    throw MessagesError.schemaUnsupported
                }
            }
        }
    }

    /// Read-only, newest-first, cursor-paginated recent messages. Text is a
    /// bounded projection; `text` is nil when the message has no plain text.
    public func recent(limit: Int, cursor: String?, service: String?) throws -> MessagesRecentResult {
        guard (1...Self.maximumLimit).contains(limit) else { throw MessagesError.invalidLimit }
        let started = DispatchTime.now().uptimeNanoseconds
        var cursorDate: Int64?
        var cursorRowID: Int64?
        if let cursor, let values = MessagesOpaqueID.cursorValues(cursor) {
            cursorDate = values.date
            cursorRowID = values.rowID
        } else if cursor != nil {
            throw MessagesError.invalidOpaqueID
        }

        let rows: [(rowID: Int64, text: String?, date: Int64, isFromMe: Bool, service: String, chatRowID: Int64)] =
            try withDatabase { database in
                var clauses: [String] = ["m.text IS NOT NULL AND m.text != ''"]
                var bindings: [Any] = []
                if let service {
                    let normalized = Self.normalizeService(service)
                    clauses.append("m.service = ?")
                    bindings.append(normalized)
                }
                if let cursorDate, let cursorRowID {
                    clauses.append("(m.date < ? OR (m.date = ? AND m.ROWID < ?))")
                    bindings.append(contentsOf: [cursorDate, cursorDate, cursorRowID])
                }
                let sql = """
                SELECT m.ROWID, m.text, m.date, m.is_from_me, m.service, c.ROWID
                FROM message m
                LEFT JOIN chat_message_join cj ON cj.message_id = m.ROWID
                LEFT JOIN chat c ON c.ROWID = cj.chat_id
                WHERE \(clauses.joined(separator: " AND "))
                ORDER BY m.date DESC, m.ROWID DESC
                LIMIT ?
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw MessagesError.queryFailed
                }
                defer { sqlite3_finalize(statement) }
                var index: Int32 = 1
                for value in bindings {
                    if let string = value as? String {
                        guard sqlite3_bind_text(statement, index, string, -1, sqliteTransient) == SQLITE_OK else { throw MessagesError.queryFailed }
                    } else if let int = value as? Int64 {
                        guard sqlite3_bind_int64(statement, index, int) == SQLITE_OK else { throw MessagesError.queryFailed }
                    }
                    index += 1
                }
                guard sqlite3_bind_int64(statement, index, Int64(limit + 1)) == SQLITE_OK else { throw MessagesError.queryFailed }

                var result: [(Int64, String?, Int64, Bool, String, Int64)] = []
                while true {
                    let step = sqlite3_step(statement)
                    if step == SQLITE_ROW {
                        let textValue = sqlite3_column_text(statement, 1)
                        let text = textValue.map { String(cString: $0) }
                        result.append((
                            sqlite3_column_int64(statement, 0),
                            text,
                            sqlite3_column_int64(statement, 2),
                            sqlite3_column_int64(statement, 3) != 0,
                            sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "unknown",
                            sqlite3_column_int64(statement, 5)
                        ))
                    } else if step == SQLITE_DONE {
                        break
                    } else {
                        throw MessagesError.queryFailed
                    }
                    if (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000 > Self.queryDeadlineMilliseconds {
                        throw MessagesError.queryFailed
                    }
                }
                return result
            }

        let truncated = rows.count > limit
        let selected = Array(rows.prefix(limit))
        let items = selected.map { row in
            MessagesRecentItem(
                id: MessagesOpaqueID.message(rowID: row.rowID),
                service: row.service,
                isFromMe: row.isFromMe,
                sentAt: Self.iso8601(appleEpochNanoseconds: row.date),
                conversationId: row.chatRowID > 0 ? MessagesOpaqueID.conversation(rowID: row.chatRowID) : "",
                text: Self.projectText(row.text)
            )
        }
        let last = selected.last
        let nextCursor: String? = last.map { MessagesOpaqueID.cursor(date: $0.date, rowID: $0.rowID) }
        return MessagesRecentResult(
            items: items,
            nextCursor: truncated ? nextCursor : nil,
            complete: !truncated,
            truncated: truncated,
            limitations: ["body projected and truncated to \(Self.maximumTextProjectionLength) chars"]
        )
    }

    /// Readability probe: full disk access + schema state, without prompting.
    public func permission() throws -> MessagesPermissionStatus {
        do {
            _ = try MessagesStoreLocator().locate()
        } catch MessagesError.fullDiskAccessRequired {
            return MessagesPermissionStatus(readable: false, fullDiskAccess: false, schemaFingerprint: nil, limitations: ["Full Disk Access required"])
        }
        do {
            let fingerprint = try schemaFingerprint()
            try verifySchema()
            return MessagesPermissionStatus(readable: true, fullDiskAccess: true, schemaFingerprint: fingerprint, limitations: [])
        } catch MessagesError.schemaUnsupported {
            return MessagesPermissionStatus(readable: false, fullDiskAccess: true, schemaFingerprint: try? schemaFingerprint(), limitations: ["Schema unsupported"])
        } catch {
            return MessagesPermissionStatus(readable: false, fullDiskAccess: false, schemaFingerprint: nil, limitations: [(error as? MessagesError)?.description ?? "Unknown error"])
        }
    }

    // MARK: - Helpers

    private static func normalizeService(_ value: String) -> String {
        switch value.lowercased() {
        case "imessage", "imessages": "iMessage"
        case "sms", "text": "SMS"
        default: value
        }
    }

    private static func projectText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if text.count > maximumTextProjectionLength {
            return String(text.prefix(maximumTextProjectionLength))
        }
        return text
    }

    private static func iso8601(appleEpochNanoseconds value: Int64) -> String {
        let seconds = Double(value) / 1_000_000_000 + appleEpochOffsetSeconds
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }

    private func queryStrings(_ database: OpaquePointer, sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MessagesError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let count = sqlite3_column_count(statement)
                var row: [String] = []
                for i in 0..<count {
                    row.append(sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "")
                }
                result.append(row)
            } else if step == SQLITE_DONE {
                break
            } else {
                throw MessagesError.queryFailed
            }
        }
        return result
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            throw MessagesError.databaseUnavailable
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }
}
