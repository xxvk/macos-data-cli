import Foundation
import XCTest
@testable import MailAdapter

final class EmlxReaderTests: XCTestCase {
    func testHashDirectoryUsesVariableDepthReversedThousandsDigits() {
        XCTAssertEqual(EmlxPathResolver.hashDirectoryComponents(rowID: 218), [])
        XCTAssertEqual(EmlxPathResolver.hashDirectoryComponents(rowID: 9_865), ["9"])
        XCTAssertEqual(EmlxPathResolver.hashDirectoryComponents(rowID: 19_926), ["9", "1"])
        XCTAssertEqual(EmlxPathResolver.hashDirectoryComponents(rowID: 262_653), ["2", "6", "2"])
        XCTAssertEqual(EmlxPathResolver.hashDirectoryComponents(rowID: 1_234_567), ["4", "3", "2", "1"])
    }

    func testResolverFindsFullAndPartialFilesAndPrefersFull() throws {
        let fixture = try EmlxFixture(rowID: 262_653, mailboxPath: "Lists/工程")
        defer { fixture.remove() }
        let resolver = EmlxPathResolver(mailStoreURL: fixture.mailStoreURL)

        try fixture.write(message: "Subject: partial\r\n", partial: true)
        var location = try XCTUnwrap(resolver.resolve(rowID: fixture.rowID, mailboxURL: fixture.mailboxURL))
        XCTAssertEqual(location.cacheState, .partial)

        try fixture.write(message: "Subject: full\r\n\r\nhello", partial: false)
        location = try XCTUnwrap(resolver.resolve(rowID: fixture.rowID, mailboxURL: fixture.mailboxURL))
        XCTAssertEqual(location.cacheState, .complete)
        XCTAssertTrue(location.fileURL.lastPathComponent.hasSuffix(".emlx"))
        XCTAssertFalse(location.fileURL.lastPathComponent.hasSuffix(".partial.emlx"))
    }

    func testResolverRejectsTraversalAndSymlinkEscape() throws {
        let fixture = try EmlxFixture(rowID: 42, mailboxPath: "INBOX")
        defer { fixture.remove() }
        let resolver = EmlxPathResolver(mailStoreURL: fixture.mailStoreURL)

        XCTAssertNil(try resolver.resolve(rowID: 42, mailboxURL: "imap://ACCOUNT/../outside"))

        let outside = fixture.rootURL.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let escapedAccount = fixture.mailStoreURL.appendingPathComponent("ESCAPED")
        try FileManager.default.createSymbolicLink(at: escapedAccount, withDestinationURL: outside)
        XCTAssertNil(try resolver.resolve(rowID: 42, mailboxURL: "imap://ESCAPED/INBOX"))
    }

    func testReaderExtractsExactRFC822BytesAndIgnoresTrailingPlist() throws {
        let fixture = try EmlxFixture(rowID: 42, mailboxPath: "INBOX")
        defer { fixture.remove() }
        let message = Data("Subject: 日本語\r\n\r\nhello\r\n".utf8)
        try fixture.write(messageData: message, partial: false, trailer: Data("<plist/>".utf8))
        let location = try XCTUnwrap(EmlxPathResolver(mailStoreURL: fixture.mailStoreURL)
            .resolve(rowID: fixture.rowID, mailboxURL: fixture.mailboxURL))

        let payload = try EmlxReader().read(location: location)

        XCTAssertEqual(payload.rfc822, message)
        XCTAssertEqual(payload.cacheState, .complete)
    }

    func testReaderRejectsMalformedOrTruncatedLengthPrefix() throws {
        let fixture = try EmlxFixture(rowID: 42, mailboxPath: "INBOX")
        defer { fixture.remove() }
        let location = try fixture.writeRaw(Data("100\nshort".utf8), partial: false)

        XCTAssertThrowsError(try EmlxReader().read(location: location)) { error in
            XCTAssertEqual(error as? MailStoreError, .emlxMalformed)
        }
    }

    func testReaderRejectsDeclaredPayloadAboveLimitBeforeReadingBody() throws {
        let fixture = try EmlxFixture(rowID: 42, mailboxPath: "INBOX")
        defer { fixture.remove() }
        let declared = EmlxReader.maximumRFC822Bytes + 1
        let location = try fixture.writeRaw(Data("\(declared)\n".utf8), partial: false)

        XCTAssertThrowsError(try EmlxReader().read(location: location)) { error in
            XCTAssertEqual(error as? MailStoreError, .contentTooLarge)
        }
    }

    func testTextExtractorDecodesMultipartPlainTextAndSkipsAttachment() throws {
        let raw = Data("""
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="outer"\r
        \r
        --outer\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        hello=20=E4=B8=96=E7=95=8C\r
        --outer\r
        Content-Type: text/plain; charset=utf-8; name="secret.txt"\r
        Content-Disposition: attachment; filename="secret.txt"\r
        \r
        attachment text must not appear\r
        --outer--\r
        """.utf8)

        let extracted = try MailTextExtractor().extract(from: raw)

        XCTAssertEqual(extracted.text?.trimmingCharacters(in: .whitespacesAndNewlines), "hello 世界")
        XCTAssertFalse(extracted.text?.contains("attachment text") ?? true)
        XCTAssertFalse(extracted.truncated)
    }

    func testTextExtractorFallsBackToSanitizedHTMLWithoutExecutingResources() throws {
        let html = "<html><style>.x{}</style><script>bad()</script><p>Hello &amp; goodbye</p><img src='https://example.invalid/x'></html>"
        let encoded = Data(html.utf8).base64EncodedString()
        let raw = Data("""
        MIME-Version: 1.0\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: base64\r
        \r
        \(encoded)\r
        """.utf8)

        let extracted = try MailTextExtractor().extract(from: raw)

        XCTAssertEqual(extracted.text?.trimmingCharacters(in: .whitespacesAndNewlines), "Hello & goodbye")
        XCTAssertFalse(extracted.text?.contains("bad()") ?? true)
        XCTAssertFalse(extracted.text?.contains("https://") ?? true)
    }

    func testMultipartBoundaryPrefixInsideBodyDoesNotTruncateText() throws {
        let raw = Data("""
        Content-Type: multipart/mixed; boundary=part\r
        \r
        --part\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        before\r
        --part-extra\r
        after\r
        --part--\r
        """.utf8)

        let extracted = try MailTextExtractor().extract(from: raw)

        XCTAssertTrue(extracted.text?.contains("before") ?? false)
        XCTAssertTrue(extracted.text?.contains("--part-extra") ?? false)
        XCTAssertTrue(extracted.text?.contains("after") ?? false)
    }
}

private final class EmlxFixture {
    let rootURL: URL
    let mailStoreURL: URL
    let rowID: Int64
    let mailboxURL: String
    private let messagesURL: URL

    init(rowID: Int64, mailboxPath: String) throws {
        self.rowID = rowID
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macos-data-emlx-\(UUID().uuidString)", isDirectory: true)
        mailStoreURL = rootURL.appendingPathComponent("V10", isDirectory: true)
        let account = "ACCOUNT"
        let store = "11111111-2222-3333-4444-555555555555"
        var mailboxURLOnDisk = mailStoreURL.appendingPathComponent(account, isDirectory: true)
        for segment in mailboxPath.split(separator: "/") {
            mailboxURLOnDisk.appendPathComponent("\(segment).mbox", isDirectory: true)
        }
        mailboxURLOnDisk.appendPathComponent(store, isDirectory: true)
        mailboxURLOnDisk.appendPathComponent("Data", isDirectory: true)
        EmlxPathResolver.hashDirectoryComponents(rowID: rowID).forEach {
            mailboxURLOnDisk.appendPathComponent($0, isDirectory: true)
        }
        mailboxURLOnDisk.appendPathComponent("Messages", isDirectory: true)
        messagesURL = mailboxURLOnDisk
        try FileManager.default.createDirectory(at: messagesURL, withIntermediateDirectories: true)
        self.mailboxURL = "imap://\(account)/" + mailboxPath
    }

    func write(message: String, partial: Bool) throws {
        try write(messageData: Data(message.utf8), partial: partial)
    }

    func write(messageData: Data, partial: Bool, trailer: Data = Data()) throws {
        var container = Data("\(messageData.count)\n".utf8)
        container.append(messageData)
        container.append(trailer)
        _ = try writeRaw(container, partial: partial)
    }

    func writeRaw(_ data: Data, partial: Bool) throws -> EmlxLocation {
        let suffix = partial ? ".partial.emlx" : ".emlx"
        let fileURL = messagesURL.appendingPathComponent("\(rowID)\(suffix)")
        try data.write(to: fileURL)
        return EmlxLocation(fileURL: fileURL, cacheState: partial ? .partial : .complete)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
