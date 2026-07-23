import CryptoKit
import Foundation
import SQLite3

public struct MailDatabaseProbeResult: Equatable, Sendable {
    public let readable: Bool
    public let journalMode: String?
    public let quickCheck: String?
    public let schemaFingerprint: String?
    public let requiredSchemaPresent: Bool
    public let timestampRangeValid: Bool

    public init(
        readable: Bool,
        journalMode: String?,
        quickCheck: String?,
        schemaFingerprint: String?,
        requiredSchemaPresent: Bool,
        timestampRangeValid: Bool = true
    ) {
        self.readable = readable
        self.journalMode = journalMode
        self.quickCheck = quickCheck
        self.schemaFingerprint = schemaFingerprint
        self.requiredSchemaPresent = requiredSchemaPresent
        self.timestampRangeValid = timestampRangeValid
    }
}

public protocol MailDatabaseProbing: Sendable {
    func inspect(databaseURL: URL) -> MailDatabaseProbeResult
}

public struct SQLiteMailDatabaseProbe: MailDatabaseProbing {
    private let performQuickCheck: Bool

    public init(performQuickCheck: Bool = true) {
        self.performQuickCheck = performQuickCheck
    }

    public func inspect(databaseURL: URL) -> MailDatabaseProbeResult {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return unavailable()
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else {
            return unavailable()
        }

        let journalMode = scalarText(database, sql: "PRAGMA journal_mode")
        let quickCheck = performQuickCheck ? scalarText(database, sql: "PRAGMA quick_check(1)") : "skipped"
        let schemaRows = rows(database, sql: "SELECT type, name, COALESCE(sql, '') FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name")
        let schemaText = schemaRows.map { $0.joined(separator: ":") }.joined(separator: "\n")
        let fingerprint = schemaText.isEmpty ? nil : SHA256.hash(data: Data(schemaText.utf8)).map { String(format: "%02x", $0) }.joined()

        let requiredColumns: [String: Set<String>] = [
            "messages": ["ROWID", "message_id", "global_message_id", "sender", "subject", "summary", "date_sent", "date_received", "mailbox", "flags", "read", "flagged", "deleted", "size"],
            "message_global_data": ["ROWID", "message_id_header"],
            "mailboxes": ["ROWID", "url", "total_count", "unread_count", "source"],
            "subjects": ["ROWID", "subject"],
            "addresses": ["ROWID", "address"],
            "recipients": ["ROWID", "message", "address", "type", "position"],
            "attachments": ["ROWID", "message", "attachment_id", "name"],
            "summaries": ["ROWID", "summary"]
        ]
        let columnsValid = requiredColumns.allSatisfy { table, expected in
            let actual = Set(rows(database, sql: "PRAGMA table_info(\"\(table)\")").compactMap { $0.count > 1 ? $0[1] : nil })
            return expected.isSubset(of: actual)
        }
        let indexes = Set(rows(database, sql: "SELECT name FROM sqlite_master WHERE type='index'").compactMap(\.first))
        let requiredIndexes: Set<String> = [
            "messages_date_received_index",
            "messages_mailbox_date_received_index",
            "messages_subject_index",
            "recipients_message_position_type_address_index",
            "attachments_message_attachment_id_index"
        ]
        let indexesValid = requiredIndexes.isSubset(of: indexes)
        let timestampRangeValid = validateTimestampRange(database)

        return MailDatabaseProbeResult(
            readable: true,
            journalMode: journalMode,
            quickCheck: quickCheck,
            schemaFingerprint: fingerprint,
            requiredSchemaPresent: columnsValid && indexesValid,
            timestampRangeValid: timestampRangeValid
        )
    }

    private func unavailable() -> MailDatabaseProbeResult {
        MailDatabaseProbeResult(
            readable: false,
            journalMode: nil,
            quickCheck: nil,
            schemaFingerprint: nil,
            requiredSchemaPresent: false,
            timestampRangeValid: false
        )
    }

    private func scalarText(_ database: OpaquePointer, sql: String) -> String? {
        rows(database, sql: sql).first?.first
    }

    private func rows(_ database: OpaquePointer, sql: String) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(statement)).map { index in
                guard let value = sqlite3_column_text(statement, index) else { return "" }
                return String(cString: value)
            })
        }
        return result
    }

    private func validateTimestampRange(_ database: OpaquePointer) -> Bool {
        let values = rows(database, sql: "SELECT MIN(date_received), MAX(date_received) FROM messages WHERE date_received > 0").first
        guard let values, values.count == 2, let minimum = Double(values[0]), let maximum = Double(values[1]) else { return false }
        let upperBound = Date().timeIntervalSince1970 + (366 * 24 * 60 * 60)
        return minimum >= 0 && maximum > 946_684_800 && maximum <= upperBound
    }
}
