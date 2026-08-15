import XCTest
@testable import Core

final class CommandManifestTests: XCTestCase {
    func testStandardManifestDescribesCLIAndCoreCommands() {
        let manifest = CommandRegistry.standard(version: "0.9.0")

        XCTAssertEqual(manifest.cli.name, "mpia")
        XCTAssertEqual(manifest.cli.version, "0.9.0")

        let topLevel = Set(manifest.commands.map(\.name))
        XCTAssertTrue(topLevel.contains("resources"))
        XCTAssertTrue(topLevel.contains("contacts"))
        XCTAssertTrue(topLevel.contains("mail"))
    }

    func testContactsGroupExposesGuardedWriteSafety() {
        let manifest = CommandRegistry.standard(version: "0.9.0")
        guard let contacts = manifest.commands.first(where: { $0.name == "contacts" }),
              let subcommands = contacts.subcommands else {
            return XCTFail("contacts group missing")
        }

        let byName = Dictionary(uniqueKeysWithValues: subcommands.map { ($0.name, $0) })

        // Read-only commands never mutate and never require confirmation.
        XCTAssertEqual(byName["get"]?.mutates, false)
        XCTAssertEqual(byName["get"]?.outputSchema, "ContactPayload")

        // Mutating commands expose dry-run/apply and, for delete, a confirmation phrase.
        XCTAssertEqual(byName["create"]?.mutates, true)
        XCTAssertEqual(byName["create"]?.inputSchema, "ContactPayload")
        XCTAssertEqual(byName["create"]?.safety.dryRun, true)
        XCTAssertEqual(byName["create"]?.safety.apply, true)
        XCTAssertEqual(byName["delete"]?.safety.confirmation, "DELETE CONTACT")
    }

    func testSchemasIncludeContactPayloadReferences() {
        let manifest = CommandRegistry.standard(version: "0.9.0")

        let payload = try? XCTUnwrap(manifest.schemas["ContactPayload"])
        XCTAssertEqual(payload?.type, .object)
        XCTAssertNotNil(payload?.properties?["kind"])
        XCTAssertNotNil(payload?.properties?["emails"])

        // LabeledValue and PostalAddress are reachable schema targets.
        XCTAssertNotNil(manifest.schemas["LabeledValue"])
        XCTAssertNotNil(manifest.schemas["PostalAddress"])
    }
}
