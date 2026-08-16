import SQLite3
import XCTest
@testable import PhoneAdapter

/// Builds a synthetic `CallHistory.storedata` schema in a temporary directory so
/// tests never touch real call history. Only the columns the reader requires are
/// created; counterparty PII columns are intentionally absent.
final class PhoneFixture {
    let directoryURL: URL
    let databaseURL: URL

    init() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpia-phone-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directoryURL = dir
        self.databaseURL = dir.appendingPathComponent("CallHistory.storedata")

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw FixtureError.openFailed
        }
        defer { sqlite3_close(database) }

        func exec(_ sql: String) throws {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(error)
                throw FixtureError.execFailed(message)
            }
        }

        try exec("""
        CREATE TABLE ZCALLRECORD (
            Z_PK INTEGER PRIMARY KEY,
            ZDATE REAL,
            ZDURATION REAL,
            ZORIGINATED INTEGER,
            ZANSWERED INTEGER,
            ZCALLTYPE INTEGER,
            ZHANDLE_TYPE INTEGER
        )
        """)
    }

    func addCall(
        primaryKey: Int64,
        date: Double,
        duration: Double,
        originated: Bool,
        answered: Bool,
        callType: Int64 = 1
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw FixtureError.openFailed
        }
        defer { sqlite3_close(database) }

        var error: UnsafeMutablePointer<CChar>?
        let sql = "INSERT INTO ZCALLRECORD (Z_PK, ZDATE, ZDURATION, ZORIGINATED, ZANSWERED, ZCALLTYPE, ZHANDLE_TYPE) VALUES (\(primaryKey), \(date), \(duration), \(originated ? 1 : 0), \(answered ? 1 : 0), \(callType), 1)"
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw FixtureError.execFailed(message)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    enum FixtureError: Error { case openFailed, execFailed(String) }
}

final class CallHistoryReaderTests: XCTestCase {
    func testRecentReturnsMetadataWithoutCounterparty() throws {
        let fixture = try PhoneFixture()
        defer { fixture.remove() }
        try fixture.addCall(primaryKey: 1, date: 808_281_506.208977, duration: 0, originated: false, answered: false)
        try fixture.addCall(primaryKey: 2, date: 808_223_934.018633, duration: 104.477429986, originated: true, answered: false)

        let reader = CallHistoryReader(databaseURL: fixture.databaseURL)
        let result = try reader.recent(limit: 10, cursor: nil)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.complete)
        XCTAssertFalse(result.truncated)

        // Newest first.
        let first = result.items[0]
        XCTAssertTrue(first.id.hasPrefix("call_"))
        XCTAssertEqual(first.direction, "incoming")
        XCTAssertEqual(first.kind, "audio")
        XCTAssertFalse(first.answered)
        XCTAssertTrue(first.missed)
        XCTAssertEqual(first.durationSeconds, 0.0)

        let second = result.items[1]
        XCTAssertEqual(second.direction, "outgoing")
        XCTAssertTrue(second.answered, "outgoing connected call is answered=true")
        XCTAssertFalse(second.missed)
        XCTAssertEqual(second.durationSeconds, 104.5)

        // No counterparty PII is present in the item JSON. The typed struct only
        // carries opaque metadata; the reader never selects ZADDRESS/ZNAME.
        let itemText = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
        XCTAssertFalse(itemText.contains("address"))
        XCTAssertFalse(itemText.contains("ZADDRESS"))
        XCTAssertFalse(itemText.contains("number"))
        XCTAssertFalse(itemText.contains("ZNAME"))
        XCTAssertFalse(itemText.contains("participant"))
    }

    func testRecentCursorPaginates() throws {
        let fixture = try PhoneFixture()
        defer { fixture.remove() }
        for i in 1...5 {
            try fixture.addCall(primaryKey: Int64(i), date: 808_281_506.0 - Double(i), duration: 0, originated: false, answered: false)
        }

        let reader = CallHistoryReader(databaseURL: fixture.databaseURL)
        let first = try reader.recent(limit: 3, cursor: nil)
        XCTAssertEqual(first.items.count, 3)
        XCTAssertTrue(first.truncated)
        XCTAssertNotNil(first.nextCursor)

        let second = try reader.recent(limit: 3, cursor: first.nextCursor)
        XCTAssertEqual(second.items.count, 2)
        XCTAssertFalse(second.truncated)
        XCTAssertNil(second.nextCursor)

        let firstIDs = Set(first.items.map(\.id))
        let secondIDs = Set(second.items.map(\.id))
        XCTAssertTrue(firstIDs.isDisjoint(with: secondIDs))
    }

    func testPermissionReportsReadableAndFingerprint() throws {
        let fixture = try PhoneFixture()
        defer { fixture.remove() }
        try fixture.addCall(primaryKey: 1, date: 808_281_506.0, duration: 0, originated: false, answered: false)

        let reader = CallHistoryReader(databaseURL: fixture.databaseURL)
        let status = try reader.permission()

        XCTAssertTrue(status.readable)
        XCTAssertTrue(status.fullDiskAccess)
        XCTAssertNotNil(status.schemaFingerprint)
    }

    func testVerifySchemaFailsClosedOnMissingColumn() throws {
        let fixture = try PhoneFixture()
        defer { fixture.remove() }

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.databaseURL.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("open failed") }
        sqlite3_exec(database, "DROP TABLE ZCALLRECORD", nil, nil, nil)
        sqlite3_exec(database, "CREATE TABLE ZCALLRECORD (Z_PK INTEGER PRIMARY KEY, ZDATE REAL)", nil, nil, nil)
        sqlite3_close(database)

        let reader = CallHistoryReader(databaseURL: fixture.databaseURL)
        XCTAssertThrowsError(try reader.verifySchema()) { error in
            XCTAssertEqual(error as? PhoneCallsError, .schemaUnsupported)
        }
    }
}
