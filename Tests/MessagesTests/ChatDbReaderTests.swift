import SQLite3
import XCTest
@testable import MessagesAdapter

/// Builds a synthetic `chat.db` in a temporary directory so tests never touch
/// real Messages data.
final class MessagesFixture {
    let directoryURL: URL
    let databaseURL: URL

    init() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpia-messages-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directoryURL = dir
        self.databaseURL = dir.appendingPathComponent("chat.db")

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
        CREATE TABLE message (
            ROWID INTEGER PRIMARY KEY,
            text TEXT,
            date INTEGER,
            is_from_me INTEGER,
            service TEXT,
            handle_id INTEGER
        )
        """)
        try exec("""
        CREATE TABLE chat (
            ROWID INTEGER PRIMARY KEY,
            chat_identifier TEXT
        )
        """)
        try exec("""
        CREATE TABLE chat_message_join (
            chat_id INTEGER,
            message_id INTEGER
        )
        """)
        try exec("CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT, service TEXT)")
    }

    func addMessage(
        rowID: Int64,
        text: String,
        date: Int64,
        isFromMe: Bool,
        service: String,
        chatRowID: Int64
    ) throws {
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
        try exec("INSERT INTO message (ROWID, text, date, is_from_me, service, handle_id) VALUES (\(rowID), '\(text)', \(date), \(isFromMe ? 1 : 0), '\(service)', 1)")
        try exec("INSERT OR IGNORE INTO chat (ROWID, chat_identifier) VALUES (\(chatRowID), 'chat-\(chatRowID)')")
        try exec("INSERT INTO chat_message_join (chat_id, message_id) VALUES (\(chatRowID), \(rowID))")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    enum FixtureError: Error { case openFailed, execFailed(String) }
}

final class ChatDbReaderTests: XCTestCase {
    func testRecentReturnsMetadataAndBoundedText() throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        try fixture.addMessage(rowID: 1, text: "hello world", date: 808_372_829_326_352_000, isFromMe: false, service: "iMessage", chatRowID: 10)
        try fixture.addMessage(rowID: 2, text: "hi", date: 808_372_829_000_000_000, isFromMe: true, service: "SMS", chatRowID: 11)

        let reader = ChatDbReader(databaseURL: fixture.databaseURL)
        let result = try reader.recent(limit: 10, cursor: nil, service: nil)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.complete)
        XCTAssertFalse(result.truncated)
        XCTAssertTrue(result.items[0].id.hasPrefix("msg_"))
        XCTAssertEqual(result.items[0].text, "hello world")
        XCTAssertEqual(result.items[0].service, "iMessage")
        XCTAssertFalse(result.items[0].isFromMe)
        XCTAssertTrue(result.items[0].conversationId.hasPrefix("chat_"))
        XCTAssertEqual(result.items[1].text, "hi")
        XCTAssertTrue(result.items[1].isFromMe)
        XCTAssertEqual(result.items[1].service, "SMS")
    }

    func testRecentTruncatesLongText() throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let longText = String(repeating: "a", count: 800)
        try fixture.addMessage(rowID: 1, text: longText, date: 808_372_829_326_352_000, isFromMe: false, service: "iMessage", chatRowID: 10)

        let reader = ChatDbReader(databaseURL: fixture.databaseURL)
        let result = try reader.recent(limit: 10, cursor: nil, service: nil)

        XCTAssertEqual(result.items[0].text?.count, ChatDbReader.maximumTextProjectionLength)
    }

    func testRecentFiltersByService() throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        try fixture.addMessage(rowID: 1, text: "im", date: 808_372_829_326_352_000, isFromMe: false, service: "iMessage", chatRowID: 10)
        try fixture.addMessage(rowID: 2, text: "sms", date: 808_372_829_000_000_000, isFromMe: false, service: "SMS", chatRowID: 11)

        let reader = ChatDbReader(databaseURL: fixture.databaseURL)
        let result = try reader.recent(limit: 10, cursor: nil, service: "sms")

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].service, "SMS")
        XCTAssertEqual(result.items[0].text, "sms")
    }

    func testRecentCursorPaginates() throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        for i in 1...5 {
            try fixture.addMessage(rowID: Int64(i), text: "msg \(i)", date: 808_372_829_326_352_000 - Int64(i) * 1_000_000_000, isFromMe: false, service: "iMessage", chatRowID: 10)
        }

        let reader = ChatDbReader(databaseURL: fixture.databaseURL)
        let first = try reader.recent(limit: 3, cursor: nil, service: nil)
        XCTAssertEqual(first.items.count, 3)
        XCTAssertTrue(first.truncated)
        XCTAssertNotNil(first.nextCursor)

        let second = try reader.recent(limit: 3, cursor: first.nextCursor, service: nil)
        XCTAssertEqual(second.items.count, 2)
        XCTAssertFalse(second.truncated)
        XCTAssertNil(second.nextCursor)

        // No overlap between pages.
        let firstIDs = Set(first.items.map(\.id))
        let secondIDs = Set(second.items.map(\.id))
        XCTAssertTrue(firstIDs.isDisjoint(with: secondIDs))
    }

    func testPermissionReportsReadableAndFingerprint() throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        try fixture.addMessage(rowID: 1, text: "hello", date: 808_372_829_326_352_000, isFromMe: false, service: "iMessage", chatRowID: 10)

        let reader = ChatDbReader(databaseURL: fixture.databaseURL)
        let status = try reader.permission()

        XCTAssertTrue(status.readable)
        XCTAssertTrue(status.fullDiskAccess)
        XCTAssertNotNil(status.schemaFingerprint)
    }

    func testVerifySchemaFailsClosedOnMissingColumn() throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }

        // Rebuild the message table without the required `text` column.
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.databaseURL.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("open failed") }
        sqlite3_exec(database, "DROP TABLE message", nil, nil, nil)
        sqlite3_exec(database, "CREATE TABLE message (ROWID INTEGER PRIMARY KEY, date INTEGER)", nil, nil, nil)
        sqlite3_close(database)

        let reader = ChatDbReader(databaseURL: fixture.databaseURL)
        XCTAssertThrowsError(try reader.verifySchema()) { error in
            XCTAssertEqual(error as? MessagesError, .schemaUnsupported)
        }
    }
}
