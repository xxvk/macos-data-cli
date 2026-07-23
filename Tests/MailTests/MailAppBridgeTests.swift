import Foundation
import XCTest
@testable import MailAdapter

final class MailAppBridgeTests: XCTestCase {
    func testScriptUsesValidatedIntegerAndEscapesMailboxLocator() {
        let locator = MailAppMessageLocator(
            rowID: 123,
            accountID: "account\"\nvalue",
            mailboxPath: "Parent/Child\"Box"
        )

        let script = SystemMailAppleEventExecutor.script(
            locator: locator,
            operation: .readText,
            timeoutSeconds: 3
        )

        XCTAssertTrue(script.contains("whose id is 123"))
        XCTAssertTrue(script.contains("account id \"account\\\"\\nvalue\""))
        XCTAssertTrue(script.contains("mailbox \"Parent\" of (account id"))
        XCTAssertTrue(script.contains("mailbox \"Child\\\"Box\" of (mailbox \"Parent\""))
        XCTAssertFalse(script.contains("account\"\nvalue"))
    }

    func testReadTextDoesNotRequestReveal() throws {
        let executor = FakeMailAppleEventExecutor(text: "body")
        let bridge = MailAppBridge(executor: executor)
        let locator = MailAppMessageLocator(rowID: 1, accountID: "A", mailboxPath: "INBOX")

        XCTAssertEqual(try bridge.readText(locator: locator), "body")
        XCTAssertEqual(executor.readCount, 1)
        XCTAssertEqual(executor.revealCount, 0)
    }

    func testFallbackLiteralMailboxNameDoesNotBecomeNestedPath() {
        let locator = MailAppMessageLocator(rowID: 7, accountID: "A", mailboxName: "Receipts/2026")
        let script = SystemMailAppleEventExecutor.script(locator: locator, operation: .readText, timeoutSeconds: 3)

        XCTAssertTrue(script.contains("whose name is \"Receipts/2026\""))
        XCTAssertFalse(script.contains("mailbox \"2026\" of"))
    }

    func testTimeoutOpensThirtySecondCircuitBreaker() throws {
        let executor = FakeMailAppleEventExecutor(error: .timedOut)
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let bridge = MailAppBridge(executor: executor, now: { clock.value })
        let locator = MailAppMessageLocator(rowID: 1, accountID: "A", mailboxPath: "INBOX")

        XCTAssertThrowsError(try bridge.readText(locator: locator)) { error in
            XCTAssertEqual(error as? MailAppBridgeError, .timedOut)
        }
        XCTAssertThrowsError(try bridge.readText(locator: locator)) { error in
            XCTAssertEqual(error as? MailAppBridgeError, .circuitOpen)
        }
        XCTAssertEqual(executor.readCount, 1)

        clock.value = clock.value.addingTimeInterval(31)
        XCTAssertThrowsError(try bridge.readText(locator: locator))
        XCTAssertEqual(executor.readCount, 2)
    }
}

private final class TestClock: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}

private final class FakeMailAppleEventExecutor: MailAppleEventExecuting, @unchecked Sendable {
    private let text: String
    private let error: MailAppBridgeError?
    private(set) var readCount = 0
    private(set) var revealCount = 0

    init(text: String = "", error: MailAppBridgeError? = nil) {
        self.text = text
        self.error = error
    }

    func readText(locator: MailAppMessageLocator, timeoutSeconds: Int) throws -> String {
        readCount += 1
        if let error { throw error }
        return text
    }

    func reveal(locator: MailAppMessageLocator, timeoutSeconds: Int) throws {
        revealCount += 1
        if let error { throw error }
    }
}
