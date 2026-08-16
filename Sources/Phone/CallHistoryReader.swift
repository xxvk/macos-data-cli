import CryptoKit
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Read-only reader over the local Call History `CallHistory.storedata` Core
/// Data SQLite store. It opens an immutable read-only connection, verifies a
/// bounded structural schema gate, and runs bounded, deadline-limited `recent`
/// queries. Counterparty numbers, names, locations, carriers, and raw local
/// IDs never leave this type.
public struct CallHistoryReader {
    public static let defaultLimit = 50
    public static let maximumLimit = 200
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
            guard !text.isEmpty else { throw PhoneCallsError.schemaUnsupported }
            return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Structural gate: the required table and columns must exist, otherwise
    /// the fast path is disabled (fail-closed). Counterparty PII columns are
    /// intentionally not required — they are never read.
    public func verifySchema() throws {
        try withDatabase { database in
            let required = [
                ("ZCALLRECORD", ["Z_PK", "ZDATE", "ZDURATION", "ZORIGINATED", "ZANSWERED", "ZCALLTYPE"]),
            ]
            for (table, columns) in required {
                let found = try queryStrings(database, sql: "PRAGMA table_info(\(table))")
                let names = Set(found.compactMap { $0.count > 1 ? $0[1] : nil })
                for column in columns where !names.contains(column) {
                    throw PhoneCallsError.schemaUnsupported
                }
            }
        }
    }

    /// Read-only, newest-first, cursor-paginated recent calls. Direction, kind,
    /// answered/missed state, duration, and timestamp are metadata only; no
    /// counterparty identifier is returned.
    public func recent(limit: Int, cursor: String?) throws -> PhoneCallsRecentResult {
        guard (1...Self.maximumLimit).contains(limit) else { throw PhoneCallsError.invalidLimit }
        let started = DispatchTime.now().uptimeNanoseconds
        var cursorDate: Double?
        var cursorPrimaryKey: Int64?
        if let cursor, let values = PhoneOpaqueID.cursorValues(cursor) {
            cursorDate = Double(values.dateMicros) / 1_000_000
            cursorPrimaryKey = values.primaryKey
        } else if cursor != nil {
            throw PhoneCallsError.invalidOpaqueID
        }

        let rows: [(primaryKey: Int64, date: Double, duration: Double, originated: Bool, answeredFlag: Bool, callType: Int64)] =
            try withDatabase { database in
                var clauses: [String] = []
                var bindings: [(kind: BindingKind, value: Any)] = []
                if let cursorDate, let cursorPrimaryKey {
                    clauses.append("(ZDATE < ? OR (ZDATE = ? AND Z_PK < ?))")
                    bindings.append(contentsOf: [
                        (.double, cursorDate), (.double, cursorDate), (.int64, cursorPrimaryKey),
                    ])
                }
                let whereClause = clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))"
                let sql = """
                SELECT Z_PK, ZDATE, ZDURATION, ZORIGINATED, ZANSWERED, ZCALLTYPE
                FROM ZCALLRECORD
                \(whereClause)
                ORDER BY ZDATE DESC, Z_PK DESC
                LIMIT ?
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw PhoneCallsError.queryFailed
                }
                defer { sqlite3_finalize(statement) }
                var index: Int32 = 1
                for binding in bindings {
                    switch binding.kind {
                    case .double:
                        guard sqlite3_bind_double(statement, index, binding.value as? Double ?? 0) == SQLITE_OK else { throw PhoneCallsError.queryFailed }
                    case .int64:
                        guard sqlite3_bind_int64(statement, index, binding.value as? Int64 ?? 0) == SQLITE_OK else { throw PhoneCallsError.queryFailed }
                    }
                    index += 1
                }
                guard sqlite3_bind_int64(statement, index, Int64(limit + 1)) == SQLITE_OK else { throw PhoneCallsError.queryFailed }

                var result: [(Int64, Double, Double, Bool, Bool, Int64)] = []
                while true {
                    let step = sqlite3_step(statement)
                    if step == SQLITE_ROW {
                        result.append((
                            sqlite3_column_int64(statement, 0),
                            sqlite3_column_double(statement, 1),
                            sqlite3_column_double(statement, 2),
                            sqlite3_column_int64(statement, 3) != 0,
                            sqlite3_column_int64(statement, 4) != 0,
                            sqlite3_column_int64(statement, 5)
                        ))
                    } else if step == SQLITE_DONE {
                        break
                    } else {
                        throw PhoneCallsError.queryFailed
                    }
                    if (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000 > Self.queryDeadlineMilliseconds {
                        throw PhoneCallsError.queryFailed
                    }
                }
                return result
            }

        let truncated = rows.count > limit
        let selected = Array(rows.prefix(limit))
        let items = selected.map { row in
            let incoming = !row.originated
            let answered = incoming ? row.answeredFlag : row.duration > 0
            return PhoneCallItem(
                id: PhoneOpaqueID.call(primaryKey: row.primaryKey),
                direction: incoming ? "incoming" : "outgoing",
                kind: Self.kind(callType: row.callType),
                answered: answered,
                missed: incoming && !answered,
                durationSeconds: Self.roundedDuration(row.duration),
                at: Self.iso8601(appleEpochSeconds: row.date)
            )
        }
        let last = selected.last
        let nextCursor: String? = last.map {
            PhoneOpaqueID.cursor(dateMicros: Int64(($0.date * 1_000_000).rounded()), primaryKey: $0.primaryKey)
        }
        return PhoneCallsRecentResult(
            items: items,
            nextCursor: truncated ? nextCursor : nil,
            complete: !truncated,
            truncated: truncated,
            limitations: ["counterparty numbers, names, and identifiers are never returned"]
        )
    }

    /// Readability probe: full disk access + schema state, without prompting.
    public func permission() throws -> PhoneCallsPermissionStatus {
        do {
            _ = try PhoneStoreLocator().locate()
        } catch PhoneCallsError.fullDiskAccessRequired {
            return PhoneCallsPermissionStatus(readable: false, fullDiskAccess: false, schemaFingerprint: nil, limitations: ["Full Disk Access required"])
        }
        do {
            let fingerprint = try schemaFingerprint()
            try verifySchema()
            return PhoneCallsPermissionStatus(readable: true, fullDiskAccess: true, schemaFingerprint: fingerprint, limitations: [])
        } catch PhoneCallsError.schemaUnsupported {
            return PhoneCallsPermissionStatus(readable: false, fullDiskAccess: true, schemaFingerprint: try? schemaFingerprint(), limitations: ["Schema unsupported"])
        } catch {
            return PhoneCallsPermissionStatus(readable: false, fullDiskAccess: false, schemaFingerprint: nil, limitations: [(error as? PhoneCallsError)?.description ?? "Unknown error"])
        }
    }

    // MARK: - Helpers

    private static func kind(callType: Int64) -> String {
        switch callType {
        case 1: "audio"
        case 8: "video"
        default: "unknown"
        }
    }

    private static func roundedDuration(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func iso8601(appleEpochSeconds value: Double) -> String {
        let seconds = value + appleEpochOffsetSeconds
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }

    private enum BindingKind {
        case double, int64
    }

    private func queryStrings(_ database: OpaquePointer, sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PhoneCallsError.queryFailed
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
                throw PhoneCallsError.queryFailed
            }
        }
        return result
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            throw PhoneCallsError.databaseUnavailable
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }
}
