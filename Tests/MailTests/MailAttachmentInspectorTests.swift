import Foundation
import XCTest
@testable import MailAdapter

final class MailAttachmentInspectorTests: XCTestCase {
    func testCountsNamedAndInlineResourcePartsWithoutDecodingPayloads() throws {
        let message = Data("""
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="outer"\r
        \r
        --outer\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Disposition: inline\r
        \r
        body\r
        --outer\r
        Content-Type: application/pdf\r
        Content-Disposition: attachment; filename="report.pdf"\r
        Content-Transfer-Encoding: base64\r
        \r
        bm90LWRlY29kZWQ=\r
        --outer\r
        Content-Type: image/png\r
        Content-Disposition: inline\r
        Content-ID: <image-1>\r
        \r
        not-decoded\r
        --outer--\r
        """.utf8)

        let result = try MailAttachmentInspector().inspect(message)

        XCTAssertEqual(result.attachmentCount, 2)
    }

    func testCountsRFC2231FilenameParameter() throws {
        let message = Data("""
        Content-Type: application/octet-stream\r
        Content-Disposition: attachment; filename*=utf-8''example.bin\r
        \r
        payload\r
        """.utf8)

        XCTAssertEqual(try MailAttachmentInspector().inspect(message).attachmentCount, 1)
    }

    func testRejectsMultipartWithoutBoundary() {
        let message = Data("Content-Type: multipart/mixed\r\n\r\nbody".utf8)

        XCTAssertThrowsError(try MailAttachmentInspector().inspect(message)) { error in
            XCTAssertEqual(error as? MailStoreError, .emlxMalformed)
        }
    }

    func testExtractorDecodesAttachmentAndPreservesSafeFilename() throws {
        let message = Data("""
        Content-Type: multipart/mixed; boundary="x"

        --x
        Content-Type: text/plain

        body
        --x
        Content-Type: application/octet-stream
        Content-Disposition: attachment; filename="report.bin"
        Content-Transfer-Encoding: base64

        aGVsbG8=
        --x--
        """.replacingOccurrences(of: "\n", with: "\r\n").utf8)

        let result = try MailAttachmentExtractor().extract(message)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.filename, "report.bin")
        XCTAssertEqual(result.first?.data, Data("hello".utf8))
    }

    func testExtractorPreservesFilenameForExporterValidation() throws {
        let message = Data("""
        Content-Type: application/octet-stream
        Content-Disposition: attachment; filename="../secret.txt"

        data
        """.replacingOccurrences(of: "\n", with: "\r\n").utf8)

        XCTAssertEqual(try MailAttachmentExtractor().extract(message).first?.filename, "../secret.txt")
    }
}
