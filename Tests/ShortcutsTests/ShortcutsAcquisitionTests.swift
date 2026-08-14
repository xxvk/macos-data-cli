import Foundation
import XCTest
import Core
@testable import ShortcutsAdapter

final class ShortcutsAcquisitionTests: XCTestCase {
    func testUnsignedAllowlistedArtifactIsAPlanCandidateButNeverApplyCapable() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "hello"]),
            action("is.workflow.actions.output"),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)

        XCTAssertEqual(result.artifactKind, .unsignedShortcut)
        XCTAssertEqual(result.parseStatus, .artifactParsed)
        XCTAssertEqual(result.capability, .semanticEditCandidate)
        XCTAssertEqual(result.actionCount, 1)
        XCTAssertEqual(result.unsupportedActionCount, 0)
        XCTAssertTrue(result.canGenerateEditPlan)
        XCTAssertFalse(result.canApplySemanticEdit)
        XCTAssertFalse(result.requiresManualMigration)
        XCTAssertTrue(result.reasons.isEmpty)
    }

    func testUnknownActionFailsClosedWithoutReturningItsIdentifier() throws {
        let identifier = "com.example.private-action"
        let fixture = try makeShortcut(actions: [action(identifier)])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)
        let encoded = try String(data: JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertEqual(result.capability, .manualMigrationRequired)
        XCTAssertEqual(result.unsupportedActionCount, 1)
        XCTAssertTrue(result.requiresManualMigration)
        XCTAssertTrue(result.reasons.contains(.unsupportedAction))
        XCTAssertFalse(encoded.contains(identifier))
    }

    func testSensitiveParameterFailsClosedAndIsRedacted() throws {
        let secret = "do-not-return-this-value"
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["apiKey": secret]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)
        let encoded = try String(data: JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertTrue(result.sensitiveValueDetected)
        XCTAssertEqual(result.capability, .manualMigrationRequired)
        XCTAssertTrue(result.reasons.contains(.sensitiveValue))
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("apikey"))
    }

    func testCredentialBearingURLFailsClosedWithoutEchoingURL() throws {
        let url = "https://user:password@example.invalid/path?access_token=private"
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": url]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)
        let encoded = try String(data: JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertTrue(result.sensitiveValueDetected)
        XCTAssertEqual(result.capability, .manualMigrationRequired)
        XCTAssertFalse(encoded.contains(url))
        XCTAssertFalse(encoded.contains("example.invalid"))
    }

    func testDeviceBoundReferenceFailsClosed() throws {
        let fixture = try makeShortcut(actions: [action("is.workflow.actions.homeaccessory")])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)

        XCTAssertTrue(result.deviceBoundReferenceDetected)
        XCTAssertEqual(result.capability, .manualMigrationRequired)
        XCTAssertTrue(result.reasons.contains(.deviceBoundReference))
    }

    func testNestedMagicVariableOrAttachmentStructureFailsClosed() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: [
                "WFTextActionText": ["WFSerializationType": "WFTextTokenString", "WFTextTokenAttachment": ["OutputUUID": "fixture"]],
            ]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)

        XCTAssertTrue(result.unsupportedStructureDetected)
        XCTAssertEqual(result.capability, .manualMigrationRequired)
        XCTAssertTrue(result.reasons.contains(.unsupportedStructure))
        XCTAssertFalse(result.canGenerateEditPlan)
    }

    func testOpaqueShortcutRequiresManualMigrationWithoutEchoingBytes() throws {
        let fixture = try makeRawShortcut(Data("opaque signed payload".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: fixture.url)
        let encoded = try String(data: JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertEqual(result.artifactKind, .opaqueShortcut)
        XCTAssertEqual(result.parseStatus, .opaque)
        XCTAssertEqual(result.capability, .manualMigrationRequired)
        XCTAssertTrue(result.reasons.contains(.opaqueOrSignedArtifact))
        XCTAssertFalse(encoded.contains("opaque signed payload"))
    }

    func testValidCherriUsesManagedSourceRouteWithoutReturningNameOrSource() throws {
        let source = "#define name Private Fixture\noutput(\"private body\")"
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.cherri")
        try Data(source.utf8).write(to: url)

        let result = try ShortcutAcquisitionClassifier().inspect(inputURL: url)
        let encoded = try String(data: JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertEqual(result.artifactKind, .cherriSource)
        XCTAssertEqual(result.parseStatus, .sourceValidated)
        XCTAssertEqual(result.capability, .managedSourceRoute)
        XCTAssertFalse(result.canGenerateEditPlan)
        XCTAssertFalse(result.canApplySemanticEdit)
        XCTAssertFalse(result.requiresManualMigration)
        XCTAssertFalse(encoded.contains("Private Fixture"))
        XCTAssertFalse(encoded.contains("private body"))
    }

    func testSymlinkAndUnknownExtensionAreRejectedBeforeReading() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.shortcut")
        try Data("opaque".utf8).write(to: target)
        let link = directory.appendingPathComponent("link.shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try ShortcutAcquisitionClassifier().inspect(inputURL: link)) { error in
            XCTAssertEqual(error as? ShortcutsError, .acquisitionInputInvalid)
        }
        let unknown = directory.appendingPathComponent("fixture.zip")
        try Data("opaque".utf8).write(to: unknown)
        XCTAssertThrowsError(try ShortcutAcquisitionClassifier().inspect(inputURL: unknown)) { error in
            XCTAssertEqual(error as? ShortcutsError, .acquisitionInputInvalid)
        }
    }

    func testNetworkURLIsRejectedBeforeItsPathCanAliasALocalShortcut() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "local-only"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.invalid"
        components.path = fixture.url.path
        let remoteURL = try XCTUnwrap(components.url)

        XCTAssertThrowsError(try ShortcutAcquisitionClassifier().inspect(inputURL: remoteURL)) { error in
            XCTAssertEqual(error as? ShortcutsError, .acquisitionInputInvalid)
        }
    }

    func testOversizedInputIsRejectedBeforeAllocationBeyondPolicy() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("oversized.shortcut")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ShortcutAcquisitionClassifier.maximumInputBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try ShortcutAcquisitionClassifier().inspect(inputURL: url)) { error in
            XCTAssertEqual(error as? ShortcutsError, .acquisitionInputTooLarge)
        }
    }

    func testAcquisitionErrorsHaveStableMachineCodesWithoutPrivateContext() {
        XCTAssertEqual(ShortcutsError.acquisitionInputInvalid.machineCode, "SHORTCUTS_ACQUISITION_INPUT_INVALID")
        XCTAssertEqual(ShortcutsError.acquisitionInputTooLarge.machineCode, "SHORTCUTS_ACQUISITION_INPUT_TOO_LARGE")
        XCTAssertFalse(ShortcutsError.acquisitionInputInvalid.description.contains("/"))
        XCTAssertFalse(ShortcutsError.acquisitionInputTooLarge.description.localizedCaseInsensitiveContains("name"))
    }

    private func action(_ identifier: String, parameters: [String: Any] = [:]) -> [String: Any] {
        ["WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": parameters]
    }

    private func makeShortcut(actions: [[String: Any]]) throws -> (directory: URL, url: URL) {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["WFWorkflowActions": actions, "WFWorkflowClientVersion": "fixture"],
            format: .binary,
            options: 0
        )
        return try makeRawShortcut(data)
    }

    private func makeRawShortcut(_ data: Data) throws -> (directory: URL, url: URL) {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("fixture.shortcut")
        try data.write(to: url)
        return (directory, url)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
