import XCTest
@testable import Core

final class CommandManifestTests: XCTestCase {
    func testStandardManifestDescribesCLIAndCoreCommands() {
        let manifest = CommandRegistry.standard(version: "0.9.3")

        XCTAssertEqual(manifest.cli.name, "mpia")
        XCTAssertEqual(manifest.cli.version, "0.9.3")

        let topLevel = Set(manifest.commands.map(\.name))
        XCTAssertTrue(topLevel.contains("agent"))
        XCTAssertTrue(topLevel.contains("resources"))
        XCTAssertTrue(topLevel.contains("contacts"))
        XCTAssertTrue(topLevel.contains("mail"))
        XCTAssertFalse(manifest.routes.isEmpty)
    }

    func testAgentGroupDescribesEveryGlobalDiscoveryEntryPoint() throws {
        let manifest = CommandRegistry.standard(version: "0.9.3")
        let agent = try XCTUnwrap(manifest.commands.first(where: { $0.name == "agent" }))
        XCTAssertEqual(agent.subcommands?.map(\.name), ["help", "manifest", "version"])
        XCTAssertTrue(agent.subcommands?.first(where: { $0.name == "manifest" })?.description.contains("schemas") == true)
    }

    func testRoutesAreUniqueAndExposeCanonicalMethods() throws {
        let routes = CommandRegistry.standard(version: "0.9.3").routes
        let identities = routes.map { "\($0.method.rawValue) \($0.path)" }
        XCTAssertEqual(Set(identities).count, identities.count)

        let byPath = Dictionary(uniqueKeysWithValues: routes.map { ($0.path, $0) })
        XCTAssertEqual(byPath["/agent/manifest"]?.method, .get)
        XCTAssertEqual(byPath["/resources"]?.method, .options)
        XCTAssertEqual(byPath["/reminders/edit"]?.method, .patch)
        XCTAssertEqual(byPath["/notes/edit-body"]?.method, .put)
        XCTAssertEqual(byPath["/photos/export"]?.method, .post)
        XCTAssertEqual(byPath["/shortcuts/author/build"]?.method, .post)
    }

    func testPublicManifestEncodingContainsRoutesButNotLegacyCommands() throws {
        let data = try JSONEncoder().encode(CommandRegistry.standard(version: "0.9.3"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["cli"])
        XCTAssertNotNil(object["routes"])
        XCTAssertNotNil(object["schemas"])
        XCTAssertNil(object["commands"])
    }

    func testNotesAndSafariManifestCoverEveryPublicCommand() throws {
        let manifest = CommandRegistry.standard(version: "0.9.3")
        let notes = try XCTUnwrap(manifest.commands.first(where: { $0.name == "notes" })?.subcommands)
        let safari = try XCTUnwrap(manifest.commands.first(where: { $0.name == "safari" })?.subcommands)

        XCTAssertTrue(Set(notes.map(\.name)).isSuperset(of: ["folder create", "folder rename", "folder move", "folder delete"]))
        XCTAssertTrue(Set(safari.map(\.name)).isSuperset(of: [
            "bookmarks move", "folders create", "folders rename", "folders move", "folders delete", "reading-list query",
        ]))
        XCTAssertTrue(safari.first(where: { $0.name == "permission" })?.params.contains(where: { $0.name == "request" }) == true)
    }

    func testContactsGroupExposesGuardedWriteSafety() {
        let manifest = CommandRegistry.standard(version: "0.9.3")
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
        let manifest = CommandRegistry.standard(version: "0.9.3")

        let payload = try? XCTUnwrap(manifest.schemas["ContactPayload"])
        XCTAssertEqual(payload?.type, .object)
        XCTAssertNotNil(payload?.properties?["kind"])
        XCTAssertNotNil(payload?.properties?["emails"])

        // LabeledValue and PostalAddress are reachable schema targets.
        XCTAssertNotNil(manifest.schemas["LabeledValue"])
        XCTAssertNotNil(manifest.schemas["PostalAddress"])
    }

    func testPageSchemaDeclaresStableRequiredFieldsAndBounds() throws {
        let page = try XCTUnwrap(CommandRegistry.standard(version: "0.9.3").schemas["Page"])
        XCTAssertEqual(Set(page.required ?? []), ["items", "limit", "truncated", "complete"])

        let limit = try XCTUnwrap(page.properties?["limit"])
        XCTAssertEqual(limit.minimum, 1)
        XCTAssertEqual(limit.maximum, 200)

        let items = try XCTUnwrap(page.properties?["items"])
        XCTAssertEqual(items.maxItems, 200)

        let cursor = try XCTUnwrap(page.properties?["nextCursor"])
        XCTAssertEqual(cursor.minLength, 1)
        XCTAssertEqual(cursor.maxLength, 4096)
        XCTAssertFalse(page.required?.contains("nextCursor") == true)
        XCTAssertFalse(page.required?.contains("limitations") == true)
    }

    func testEverySchemaHasAuditedValidRequiredProperties() {
        for (name, schema) in CommandRegistry.standard(version: "0.9.3").schemas {
            guard let required = schema.required else {
                return XCTFail("\(name) has not been audited for required properties")
            }
            let properties = Set(schema.properties?.keys ?? Dictionary<String, JSONSchema>().keys)
            XCTAssertTrue(Set(required).isSubset(of: properties), "\(name) requires an unknown property")
        }
    }

    func testKnownInputConstraintsMatchRuntimePolicies() throws {
        let schemas = CommandRegistry.standard(version: "0.9.3").schemas
        let notesCreate = try XCTUnwrap(schemas["NotesCreateInput"])
        XCTAssertEqual(notesCreate.required, ["folderID", "title", "bodyFormat", "body"])
        XCTAssertEqual(notesCreate.properties?["title"]?.minLength, 1)
        XCTAssertEqual(notesCreate.properties?["title"]?.maxLength, 200)
        XCTAssertEqual(notesCreate.properties?["bodyFormat"]?.enumValues, ["plaintext", "html"])

        let notesMove = try XCTUnwrap(schemas["NotesFolderMoveInput"])
        XCTAssertEqual(notesMove.properties?["destinationParentFolderID"]?.nullable, true)
        XCTAssertEqual(notesMove.properties?["expectedNameSHA256"]?.pattern, "^[0-9a-f]{64}$")

        let reminder = try XCTUnwrap(schemas["ReminderInput"])
        XCTAssertEqual(reminder.properties?["title"]?.maxLength, 1_000)
        XCTAssertEqual(reminder.properties?["url"]?.format, "uri")

        let safari = try XCTUnwrap(schemas["SafariReadingListAddInput"])
        XCTAssertEqual(safari.required, ["url"])
        XCTAssertEqual(safari.properties?["url"]?.maxLength, 4_096)
    }

    func testNotesStructuredInputsMatchRuntimeParser() throws {
        let manifest = CommandRegistry.standard(version: "0.9.3")
        let notes = try XCTUnwrap(manifest.commands.first(where: { $0.name == "notes" })?.subcommands)
        let byName = Dictionary(uniqueKeysWithValues: notes.map { ($0.name, $0) })

        XCTAssertEqual(byName["move"]?.inputSchema, "NotesMoveInput")
        XCTAssertEqual(byName["delete"]?.inputSchema, "NotesDeleteInput")
        XCTAssertTrue(byName["delete"]?.params.contains(where: { $0.name == "input" }) == true)

        let bind = try XCTUnwrap(byName["write-account bind"])
        XCTAssertNil(bind.inputSchema)
        XCTAssertTrue(bind.params.contains(where: { $0.name == "account-id" && $0.required }))
        XCTAssertFalse(bind.params.contains(where: { $0.name == "input" }))

        let move = try XCTUnwrap(manifest.schemas["NotesMoveInput"])
        XCTAssertEqual(move.required, ["destinationFolderID", "expectedModificationDate"])
        let delete = try XCTUnwrap(manifest.schemas["NotesDeleteInput"])
        XCTAssertEqual(delete.required, ["expectedModificationDate"])
    }
}
