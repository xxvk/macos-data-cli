import Foundation
import SQLite3
import XCTest
@testable import MailAdapter

final class MailStoreTests: XCTestCase {
    func testAccountsAreGroupedByMailboxAuthorityWithoutExposingIt() throws {
        let fixture = try MailSQLiteFixture()
        let accounts = try SQLiteMailStore(databaseURL: fixture.databaseURL).accounts()

        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.map(\.kind).sorted(), ["ews", "imap"])
        XCTAssertEqual(accounts.map(\.mailboxCount).sorted(), [1, 2])
        let json = String(decoding: try JSONEncoder().encode(accounts), as: UTF8.self)
        XCTAssertFalse(json.contains("ada@example.test"))
        XCTAssertFalse(json.contains("imap.example.test"))
    }

    func testMailboxesCanBeFilteredByOpaqueAccountID() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)
        let account = try XCTUnwrap(store.accounts().first { $0.kind == "imap" })

        let mailboxes = try store.mailboxes(accountID: account.id)

        XCTAssertEqual(mailboxes.map(\.name).sorted(), ["Archive", "INBOX"])
        XCTAssertTrue(mailboxes.allSatisfy { $0.accountID == account.id })
        XCTAssertEqual(mailboxes.reduce(0) { $0 + $1.totalCount }, 3)
    }

    func testMetadataQueryIsBoundedAndCursorBased() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)

        let first = try store.query(MailQuery(limit: 2))
        XCTAssertEqual(first.messages.count, 2)
        XCTAssertTrue(first.truncated)
        XCTAssertFalse(first.incomplete)
        XCTAssertNil(first.fallbackReason)
        XCTAssertGreaterThanOrEqual(first.elapsedMs, 0)
        XCTAssertNotNil(first.nextCursor)
        XCTAssertEqual(first.messages.map(\.subject), ["Security alert", "Newsletter"])

        let second = try store.query(MailQuery(limit: 2, cursor: first.nextCursor))
        XCTAssertEqual(second.messages.map(\.subject), ["Quarterly report", "Older note"])
        XCTAssertFalse(second.truncated)
        XCTAssertNil(second.nextCursor)
    }

    func testMetadataQueryUsesBoundParameters() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)

        let result = try store.query(MailQuery(subject: "' OR 1=1 --", limit: 50))

        XCTAssertTrue(result.messages.isEmpty)
    }

    func testMetadataQuerySupportsMailboxSenderFlagsAndAttachmentFilters() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)
        let inbox = try XCTUnwrap(store.mailboxes().first { $0.name == "INBOX" })

        let result = try store.query(MailQuery(
            mailboxID: inbox.id,
            from: "bob@example.test",
            unread: true,
            flagged: true,
            hasAttachment: true,
            limit: 10
        ))

        XCTAssertEqual(result.messages.map(\.subject), ["Security alert"])
        XCTAssertEqual(result.messages.first?.cacheState, "metadata_only")
        XCTAssertEqual(result.backend, "sqlite")
    }

    func testInvalidOpaqueMailboxIDFailsClosed() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)

        XCTAssertThrowsError(try store.query(MailQuery(mailboxID: "not-a-mailbox-id"))) { error in
            XCTAssertEqual(error as? MailStoreError, .invalidOpaqueID)
        }
    }

    func testGetDefaultsToMetadataAndTextReadIsExplicit() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)
        let raw = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nprivate body\r\n".utf8)
        try fixture.writeEmlx(rowID: 104, mailboxPath: "INBOX", message: raw)

        let metadata = try store.get(id: message.id)
        XCTAssertNil(metadata.content)
        XCTAssertEqual(metadata.backend, "sqlite")
        XCTAssertEqual(metadata.cacheState, "complete")
        XCTAssertEqual(metadata.message.idScope, "local")
        XCTAssertEqual(metadata.message.messageID, "<security@example.test>")

        let text = try store.get(id: message.id, projection: .text)
        XCTAssertEqual(text.backend, "sqlite_emlx")
        XCTAssertEqual(text.content?.text?.trimmingCharacters(in: .whitespacesAndNewlines), "private body")
        XCTAssertFalse(text.incomplete)

        let rawResult = try store.rawMessage(id: message.id)
        XCTAssertEqual(rawResult.data, raw)
        XCTAssertFalse(rawResult.incomplete)
    }

    func testPartialEmlxWithoutTextFallsBackToMailApp() throws {
        let fixture = try MailSQLiteFixture()
        let bridge = StubMailAppBridge(text: "fallback body")
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL, mailAppBridge: bridge)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)
        try fixture.writeEmlx(
            rowID: 104,
            mailboxPath: "INBOX",
            message: Data("Subject: partial\r\n".utf8),
            partial: true
        )

        let result = try store.get(id: message.id, projection: .text)

        XCTAssertEqual(result.backend, "mail_app")
        XCTAssertEqual(result.cacheState, "unknown")
        XCTAssertFalse(result.incomplete)
        XCTAssertEqual(result.fallbackReason, "partial_emlx")
        XCTAssertEqual(result.content?.text, "fallback body")
        XCTAssertEqual(bridge.readLocators.count, 1)
    }

    func testMissingCachedContentReportsWhyMailAppFallbackWasUnavailable() throws {
        let fixture = try MailSQLiteFixture()
        let bridge = StubMailAppBridge(readError: .mailNotRunning)
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL, mailAppBridge: bridge)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)

        let result = try store.get(id: message.id, projection: .text)

        XCTAssertEqual(result.backend, "sqlite")
        XCTAssertEqual(result.cacheState, "metadata_only")
        XCTAssertTrue(result.incomplete)
        XCTAssertEqual(result.fallbackReason, "mail_app_not_running")
        XCTAssertEqual(result.limitations, ["mail_app_not_running"])
    }

    func testMissingCachedTextUsesMailAppFallbackWithOpaqueLocator() throws {
        let fixture = try MailSQLiteFixture()
        let bridge = StubMailAppBridge(text: "fallback body")
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL, mailAppBridge: bridge)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Newsletter")).messages.first)

        let result = try store.get(id: message.id, projection: .text)

        XCTAssertEqual(result.backend, "mail_app")
        XCTAssertEqual(result.content?.text, "fallback body")
        XCTAssertEqual(result.fallbackReason, "content_not_cached")
        XCTAssertFalse(result.incomplete)
        XCTAssertEqual(
            bridge.readLocators,
            [MailAppMessageLocator(rowID: 103, accountID: "work-account", mailboxPath: "Inbox")]
        )
    }

    func testRevealUsesMailAppBridge() throws {
        let fixture = try MailSQLiteFixture()
        let bridge = StubMailAppBridge()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL, mailAppBridge: bridge)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)

        let result = try store.reveal(id: message.id)

        XCTAssertEqual(result.backend, "mail_app")
        XCTAssertTrue(result.revealed)
        XCTAssertEqual(result.id, message.id)
        XCTAssertEqual(bridge.revealLocators.count, 1)
    }

    func testRevealMapsTimeoutToMailStoreError() throws {
        let fixture = try MailSQLiteFixture()
        let bridge = StubMailAppBridge(revealError: .timedOut)
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL, mailAppBridge: bridge)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)

        XCTAssertThrowsError(try store.reveal(id: message.id)) { error in
            XCTAssertEqual(error as? MailStoreError, .mailAppTimedOut)
        }
    }

    func testAttachmentVerificationMatchesSQLiteAndCompleteMIMECounts() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)
        let message = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)
        let raw = Data("""
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="fixture"\r
        \r
        --fixture\r
        Content-Type: text/plain\r
        \r
        body\r
        --fixture\r
        Content-Type: application/pdf\r
        Content-Disposition: attachment; filename="fixture.pdf"\r
        \r
        bytes\r
        --fixture--\r
        """.utf8)
        try fixture.writeEmlx(rowID: 104, mailboxPath: "INBOX", message: raw)

        let result = try store.verifyAttachments(id: message.id)

        XCTAssertEqual(result.backend, "sqlite_emlx")
        XCTAssertEqual(result.sqliteCount, 1)
        XCTAssertEqual(result.mimeCount, 1)
        XCTAssertTrue(result.matched)
        XCTAssertFalse(result.incomplete)
        XCTAssertTrue(result.limitations.isEmpty)
    }

    func testAttachmentVerificationReportsMismatchAndMissingCache() throws {
        let fixture = try MailSQLiteFixture()
        let store = SQLiteMailStore(databaseURL: fixture.databaseURL)
        let attached = try XCTUnwrap(store.query(MailQuery(subject: "Security alert")).messages.first)
        try fixture.writeEmlx(
            rowID: 104,
            mailboxPath: "INBOX",
            message: Data("Content-Type: text/plain\r\n\r\nbody".utf8)
        )

        let mismatch = try store.verifyAttachments(id: attached.id)
        XCTAssertEqual(mismatch.sqliteCount, 1)
        XCTAssertEqual(mismatch.mimeCount, 0)
        XCTAssertFalse(mismatch.matched)
        XCTAssertTrue(mismatch.limitations.contains("attachment_count_mismatch"))

        let uncached = try XCTUnwrap(store.query(MailQuery(subject: "Newsletter")).messages.first)
        let unavailable = try store.verifyAttachments(id: uncached.id)
        XCTAssertNil(unavailable.mimeCount)
        XCTAssertTrue(unavailable.incomplete)
        XCTAssertEqual(unavailable.limitations, ["attachment_cross_check_unavailable"])
    }
}

private final class StubMailAppBridge: MailAppBridging, @unchecked Sendable {
    private let lock = NSLock()
    private let text: String
    private let readError: MailAppBridgeError?
    private let revealError: MailAppBridgeError?
    private var storedReadLocators: [MailAppMessageLocator] = []
    private var storedRevealLocators: [MailAppMessageLocator] = []

    init(
        text: String = "",
        readError: MailAppBridgeError? = nil,
        revealError: MailAppBridgeError? = nil
    ) {
        self.text = text
        self.readError = readError
        self.revealError = revealError
    }

    var readLocators: [MailAppMessageLocator] {
        lock.withLock { storedReadLocators }
    }

    var revealLocators: [MailAppMessageLocator] {
        lock.withLock { storedRevealLocators }
    }

    func readText(locator: MailAppMessageLocator) throws -> String {
        lock.withLock { storedReadLocators.append(locator) }
        if let readError { throw readError }
        return text
    }

    func reveal(locator: MailAppMessageLocator) throws {
        lock.withLock { storedRevealLocators.append(locator) }
        if let revealError { throw revealError }
    }
}

private final class MailSQLiteFixture {
    let databaseURL: URL
    private let rootURL: URL
    private let mailStoreURL: URL
    private var database: OpaquePointer?

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macos-data-mail-store-\(UUID().uuidString)", isDirectory: true)
        mailStoreURL = rootURL.appendingPathComponent("V10", isDirectory: true)
        let mailDataURL = mailStoreURL.appendingPathComponent("MailData", isDirectory: true)
        try FileManager.default.createDirectory(at: mailDataURL, withIntermediateDirectories: true)
        databaseURL = mailDataURL.appendingPathComponent("Envelope Index")
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw NSError(domain: "MailSQLiteFixture", code: 1)
        }
        try execute("""
        CREATE TABLE mailboxes (
          ROWID INTEGER PRIMARY KEY, url TEXT NOT NULL, total_count INTEGER NOT NULL,
          unread_count INTEGER NOT NULL, deleted_count INTEGER NOT NULL DEFAULT 0,
          unseen_count INTEGER NOT NULL DEFAULT 0,
          unread_count_adjusted_for_duplicates INTEGER NOT NULL DEFAULT 0,
          change_identifier TEXT, source INTEGER, alleged_change_identifier TEXT
        );
        CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT NOT NULL, comment TEXT NOT NULL DEFAULT '');
        CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT NOT NULL);
        CREATE TABLE messages (
          ROWID INTEGER PRIMARY KEY, message_id INTEGER NOT NULL DEFAULT 0,
          global_message_id INTEGER NOT NULL DEFAULT 0, remote_id INTEGER,
          document_id TEXT, sender INTEGER, subject_prefix TEXT, subject INTEGER NOT NULL,
          summary INTEGER, date_sent INTEGER, date_received INTEGER, mailbox INTEGER NOT NULL,
          remote_mailbox INTEGER, flags INTEGER NOT NULL DEFAULT 0, read INTEGER NOT NULL DEFAULT 0,
          flagged INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0,
          size INTEGER NOT NULL DEFAULT 0, conversation_id INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE recipients (ROWID INTEGER PRIMARY KEY, message INTEGER NOT NULL, address INTEGER NOT NULL, type INTEGER, position INTEGER);
        CREATE TABLE attachments (ROWID INTEGER PRIMARY KEY, message INTEGER NOT NULL, attachment_id TEXT, name TEXT);
        CREATE TABLE message_global_data (ROWID INTEGER PRIMARY KEY, message_id_header TEXT);

        INSERT INTO mailboxes (ROWID,url,total_count,unread_count) VALUES
          (10,'imap://ada%40example.test@imap.example.test/INBOX',2,1),
          (11,'imap://ada%40example.test@imap.example.test/Archive',1,0),
          (20,'ews://work-account/Inbox',1,0);
        INSERT INTO addresses (ROWID,address) VALUES
          (1,'ada@example.test'),(2,'bob@example.test'),(3,'news@example.test');
        INSERT INTO subjects (ROWID,subject) VALUES
          (1,'Older note'),(2,'Quarterly report'),(3,'Newsletter'),(4,'Security alert');
        INSERT INTO message_global_data (ROWID,message_id_header) VALUES
          (1,'<older@example.test>'),(2,'<report@example.test>'),
          (3,'<newsletter@example.test>'),(4,'<security@example.test>');
        INSERT INTO messages (ROWID,global_message_id,sender,subject,date_sent,date_received,mailbox,read,flagged,deleted,size) VALUES
          (101,1,1,1,1700000000,1700000000,11,1,0,0,100),
          (102,2,1,2,1700001000,1700001000,10,1,0,0,200),
          (103,3,3,3,1700002000,1700002000,20,1,0,0,300),
          (104,4,2,4,1700003000,1700003000,10,0,1,0,400);
        INSERT INTO recipients (ROWID,message,address,type,position) VALUES (1,104,1,0,0);
        INSERT INTO attachments (ROWID,message,attachment_id,name) VALUES (1,104,'attachment-1','report.pdf');
        """)
    }

    deinit {
        if let database { sqlite3_close(database) }
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeEmlx(rowID: Int64, mailboxPath: String, message: Data, partial: Bool = false) throws {
        let account = "ada@example.test@imap.example.test"
        let store = "11111111-2222-3333-4444-555555555555"
        var directory = mailStoreURL.appendingPathComponent(account, isDirectory: true)
        for segment in mailboxPath.split(separator: "/") {
            directory.appendPathComponent("\(segment).mbox", isDirectory: true)
        }
        directory.appendPathComponent(store, isDirectory: true)
        directory.appendPathComponent("Data", isDirectory: true)
        EmlxPathResolver.hashDirectoryComponents(rowID: rowID).forEach {
            directory.appendPathComponent($0, isDirectory: true)
        }
        directory.appendPathComponent("Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var container = Data("\(message.count)\n".utf8)
        container.append(message)
        let suffix = partial ? ".partial.emlx" : ".emlx"
        try container.write(to: directory.appendingPathComponent("\(rowID)\(suffix)"))
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "MailSQLiteFixture", code: 2)
        }
    }
}
