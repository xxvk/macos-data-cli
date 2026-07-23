import Foundation
import XCTest
@testable import MailAdapter

final class MailDoctorTests: XCTestCase {
    func testDoctorSelectsHighestNumericMailStoreVersion() throws {
        let root = try makeFixtureRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("V9"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("V10"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("V2"), withIntermediateDirectories: true)

        let report = doctor(root: root, databaseProbe: .supported).run()

        XCTAssertEqual(report.mailStoreVersion, "V10")
    }

    func testDoctorEnablesFastPathOnlyForRecognizedReadableSchema() throws {
        let root = try makeFixtureRoot()
        let data = root.appendingPathComponent("V10/MailData")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: data.appendingPathComponent("Envelope Index").path, contents: Data())
        FileManager.default.createFile(atPath: data.appendingPathComponent("Envelope Index-wal").path, contents: Data())
        FileManager.default.createFile(atPath: data.appendingPathComponent("Envelope Index-shm").path, contents: Data())

        let report = doctor(root: root, databaseProbe: .supported).run()

        XCTAssertEqual(report.sqlite.status, .available)
        XCTAssertEqual(report.schema.status, .supported)
        XCTAssertEqual(report.fullDiskAccess, .available)
        XCTAssertEqual(report.automation, .requiresConsent)
        XCTAssertTrue(report.fastPathAvailable)
    }

    func testDoctorFailsClosedForUnknownSchema() throws {
        let root = try makeFixtureRoot()
        let data = root.appendingPathComponent("V10/MailData")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: data.appendingPathComponent("Envelope Index").path, contents: Data())

        let report = doctor(root: root, databaseProbe: .unsupported).run()

        XCTAssertEqual(report.schema.status, .unsupported)
        XCTAssertFalse(report.fastPathAvailable)
        XCTAssertTrue(report.limitations.contains("mail_schema_unsupported"))
    }

    func testDoctorDoesNotReportPersonalMailData() throws {
        let root = try makeFixtureRoot()
        let data = root.appendingPathComponent("V10/MailData")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: data.appendingPathComponent("Envelope Index").path, contents: Data())

        let report = doctor(root: root, databaseProbe: .supported).run()
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)

        XCTAssertFalse(json.contains(root.path))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("subject"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("sender"))
    }

    private func makeFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macos-data-mail-tests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func doctor(root: URL, databaseProbe: StubDatabaseProbe) -> MailDoctor {
        MailDoctor(
            mailRoot: root,
            databaseProbe: databaseProbe,
            automationProbe: StubAutomationProbe(result: .requiresConsent)
        )
    }
}

private struct StubAutomationProbe: MailAutomationProbing {
    let result: MailAutomationStatus
    func status() -> MailAutomationStatus { result }
}

private struct StubDatabaseProbe: MailDatabaseProbing {
    let result: MailDatabaseProbeResult

    func inspect(databaseURL: URL) -> MailDatabaseProbeResult { result }

    static let supported = StubDatabaseProbe(result: MailDatabaseProbeResult(
        readable: true,
        journalMode: "wal",
        quickCheck: "ok",
        schemaFingerprint: "fixture-supported",
        requiredSchemaPresent: true
    ))

    static let unsupported = StubDatabaseProbe(result: MailDatabaseProbeResult(
        readable: true,
        journalMode: "wal",
        quickCheck: "ok",
        schemaFingerprint: "fixture-unknown",
        requiredSchemaPresent: false
    ))
}
