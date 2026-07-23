import Foundation
import XCTest
@testable import MailAdapter

final class MailAppMetadataStoreTests: XCTestCase {
    func testMailResourceMapperKeepsAccountOpaqueAndReadOnly() {
        let account = MailAccountSummary(id: "mail-account-opaque-001", kind: "imap", mailboxCount: 3, totalCount: 10, unreadCount: 2)

        let resource = MailResourceMapper.map(account, selected: true, displayName: "aim-tech.jp work account")

        XCTAssertEqual(resource.kind, .mailAccount)
        XCTAssertEqual(resource.provider, .mail)
        XCTAssertEqual(resource.id, "mail-account-opaque-001")
        XCTAssertEqual(resource.displayName, "aim-tech.jp work account")
        XCTAssertTrue(resource.capabilities.readable)
        XCTAssertFalse(resource.capabilities.writable)
        XCTAssertTrue(resource.capabilities.selected)
    }

    func testFallbackListsOpaqueAccountsAndTopLevelMailboxes() throws {
        let bridge = FixtureMailAppMetadataBridge()
        let store = MailAppMetadataStore(
            metadataBridge: bridge,
            contentBridge: bridge,
            fallbackReason: "mail_schema_unsupported"
        )

        let accounts = try store.accounts()
        let mailboxes = try store.mailboxes(accountID: accounts.accounts.first?.id)

        XCTAssertEqual(accounts.backend, "mail_app")
        XCTAssertEqual(accounts.accounts.first?.kind, "imap")
        XCTAssertEqual(accounts.accounts.first?.mailboxCount, 1)
        XCTAssertEqual(mailboxes.backend, "mail_app")
        XCTAssertEqual(mailboxes.mailboxes.first?.name, "Inbox")
        XCTAssertTrue(mailboxes.mailboxes.first?.id.hasPrefix("ambx_") == true)
        let json = String(decoding: try JSONEncoder().encode(mailboxes), as: UTF8.self)
        XCTAssertFalse(json.contains("fixture-account-key"))
        XCTAssertFalse(json.contains("Private/Inbox"))
    }

    func testFallbackQueryIsBoundedFilteredAndExplicitlyIncomplete() throws {
        let bridge = FixtureMailAppMetadataBridge(messageLimitReached: true)
        let store = MailAppMetadataStore(
            metadataBridge: bridge,
            contentBridge: bridge,
            fallbackReason: "full_disk_access_required"
        )

        let result = try store.query(MailQuery(
            from: "sender@example.test",
            unread: true,
            hasAttachment: true,
            limit: 10
        ))

        XCTAssertEqual(result.backend, "mail_app")
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.items, result.messages)
        XCTAssertTrue(result.messages[0].id.hasPrefix("appmsg_"))
        XCTAssertEqual(result.messages[0].idScope, "mail_app_local")
        XCTAssertEqual(result.fallbackReason, "full_disk_access_required")
        XCTAssertTrue(result.incomplete)
        XCTAssertTrue(result.truncated)
        XCTAssertNil(result.nextCursor)
        XCTAssertTrue(result.limitations.contains("mail_app_message_limit_reached"))
        XCTAssertTrue(result.limitations.contains("mail_app_query_cursor_unavailable"))
    }

    func testFallbackIDSupportsTargetedMetadataTextAndReveal() throws {
        let bridge = FixtureMailAppMetadataBridge()
        let store = MailAppMetadataStore(
            metadataBridge: bridge,
            contentBridge: bridge,
            fallbackReason: "mail_schema_unsupported"
        )
        let id = try XCTUnwrap(store.query(MailQuery(limit: 1)).messages.first?.id)

        let metadata = try store.get(id: id)
        let text = try store.get(id: id, projection: .text)
        let reveal = try store.reveal(id: id)

        XCTAssertNil(metadata.content)
        XCTAssertTrue(metadata.incomplete)
        XCTAssertEqual(text.content?.text, "fallback body")
        XCTAssertFalse(text.incomplete)
        XCTAssertTrue(reveal.revealed)
        XCTAssertEqual(bridge.metadataLocators, [bridge.message.locator, bridge.message.locator])
        XCTAssertEqual(bridge.readLocators, [bridge.message.locator])
        XCTAssertEqual(bridge.revealLocators, [bridge.message.locator])
    }

    func testFallbackRejectsSQLiteIDsAndRawContent() throws {
        let bridge = FixtureMailAppMetadataBridge()
        let store = MailAppMetadataStore(
            metadataBridge: bridge,
            contentBridge: bridge,
            fallbackReason: "mail_schema_unsupported"
        )
        let id = try XCTUnwrap(store.query(MailQuery(limit: 1)).messages.first?.id)

        XCTAssertThrowsError(try store.get(id: "msg_AAAAAAAAAAE")) { error in
            XCTAssertEqual(error as? MailStoreError, .invalidOpaqueID)
        }
        XCTAssertThrowsError(try store.get(id: id, projection: .raw)) { error in
            XCTAssertEqual(error as? MailStoreError, .contentNotCached)
        }
        XCTAssertThrowsError(try store.query(MailQuery(limit: 1, cursor: "cur_invalid"))) { error in
            XCTAssertEqual(error as? MailStoreError, .invalidOpaqueID)
        }
    }

    func testTargetedMetadataFailureKeepsStableMailError() throws {
        let bridge = FixtureMailAppMetadataBridge(metadataError: .messageNotFound)
        let store = MailAppMetadataStore(
            metadataBridge: bridge,
            contentBridge: bridge,
            fallbackReason: "mail_schema_unsupported"
        )
        let id = try XCTUnwrap(store.query(MailQuery(limit: 1)).messages.first?.id)

        XCTAssertThrowsError(try store.get(id: id)) { error in
            XCTAssertEqual(error as? MailStoreError, .mailAppMessageNotFound)
            XCTAssertEqual((error as? MailStoreError)?.machineCode, "MAIL_APP_MESSAGE_NOT_FOUND")
        }
    }

    func testMetadataAppleScriptsCompileWithoutExecuting() throws {
        let locator = MailAppMessageLocator(rowID: 42, accountID: "account-key", mailboxPath: "Inbox")
        let sources = [
            SystemMailAppMetadataBridge.snapshotScript(
                maximumAccounts: 32,
                maximumMailboxes: 200,
                maximumMessages: 25,
                timeoutSeconds: 5
            ),
            SystemMailAppMetadataBridge.metadataScript(locator: locator, timeoutSeconds: 5)
        ]

        for source in sources {
            let script = try XCTUnwrap(NSAppleScript(source: source))
            var details: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&details), "\(details ?? [:])")
        }
    }
}

private final class FixtureMailAppMetadataBridge: MailAppMetadataBridging, MailAppBridging, @unchecked Sendable {
    private let lock = NSLock()
    private let messageLimitReached: Bool
    private let metadataError: MailAppBridgeError?
    private var storedMetadataLocators: [MailAppMessageLocator] = []
    private var storedReadLocators: [MailAppMessageLocator] = []
    private var storedRevealLocators: [MailAppMessageLocator] = []

    let message = MailAppMessageRecord(
        locator: MailAppMessageLocator(rowID: 42, accountID: "fixture-account-key", mailboxName: "Private/Inbox"),
        messageID: "<fixture@example.test>",
        subject: "Fixture subject",
        sender: "Sender <sender@example.test>",
        sentAt: Date(timeIntervalSince1970: 1_700_000_000),
        receivedAt: Date(timeIntervalSince1970: 1_700_000_100),
        read: false,
        flagged: true,
        attachmentCount: 1,
        sizeBytes: 1234,
        to: ["recipient@example.test"]
    )

    init(messageLimitReached: Bool = false, metadataError: MailAppBridgeError? = nil) {
        self.messageLimitReached = messageLimitReached
        self.metadataError = metadataError
    }

    var metadataLocators: [MailAppMessageLocator] { lock.withLock { storedMetadataLocators } }
    var readLocators: [MailAppMessageLocator] { lock.withLock { storedReadLocators } }
    var revealLocators: [MailAppMessageLocator] { lock.withLock { storedRevealLocators } }

    func snapshot(maximumAccounts: Int, maximumMailboxes: Int, maximumMessages: Int) throws -> MailAppMetadataSnapshot {
        MailAppMetadataSnapshot(
            accounts: [MailAppAccountRecord(key: "fixture-account-key", kind: "imap account")],
            mailboxes: [MailAppMailboxRecord(
                accountKey: "fixture-account-key",
                path: "Private/Inbox",
                name: "Inbox",
                totalCount: 10,
                unreadCount: 2
            )],
            messages: maximumMessages > 0 ? [message] : [],
            messageLimitReached: maximumMessages > 0 && messageLimitReached
        )
    }

    func metadata(locator: MailAppMessageLocator) throws -> MailAppMessageRecord {
        lock.withLock { storedMetadataLocators.append(locator) }
        if let metadataError { throw metadataError }
        guard locator == message.locator else { throw MailAppBridgeError.messageNotFound }
        return message
    }

    func readText(locator: MailAppMessageLocator) throws -> String {
        lock.withLock { storedReadLocators.append(locator) }
        return "fallback body"
    }

    func reveal(locator: MailAppMessageLocator) throws {
        lock.withLock { storedRevealLocators.append(locator) }
    }
}
