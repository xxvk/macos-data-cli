import Foundation
import XCTest
import Core
@testable import ShortcutsAdapter

final class ShortcutsAuthoringTests: XCTestCase {
    private final class AuthorBuilderStub: ShortcutsAuthoringBuilding, @unchecked Sendable {
        var buildCalls = 0
        var declaredNames: [String] = []
        let result: ShortcutAuthorBuildResult

        init(result: ShortcutAuthorBuildResult) { self.result = result }

        func validate(sourceURL: URL) throws -> ShortcutAuthorValidationResult {
            ShortcutAuthorValidationResult(sourceSHA256: result.sourceSHA256, sourceBytes: result.sourceBytes, includeCount: 0, actionCount: result.actionCount, compiler: result.compiler, compilerVersion: result.compilerVersion, clientVersion: result.clientVersion, experimental: true)
        }

        func build(sourceURL: URL, outputURL: URL, signingMode: ShortcutSigningMode) throws -> ShortcutAuthorBuildResult {
            buildCalls += 1
            try Data("signed".utf8).write(to: outputURL)
            let source = try Data(contentsOf: sourceURL)
            declaredNames.append(try CherriSourceValidator().validate(source).declaredName)
            return ShortcutAuthorBuildResult(
                sourceSHA256: CherriSourceValidator.hash(source),
                sourceBytes: source.count,
                compiledSHA256: result.compiledSHA256,
                compiledBytes: result.compiledBytes,
                actionCount: result.actionCount,
                compiler: result.compiler,
                compilerVersion: result.compilerVersion,
                clientVersion: result.clientVersion,
                signingMode: signingMode,
                experimental: result.experimental
            )
        }
    }

    private final class VisibleImporterStub: ShortcutsVisibleImporting, @unchecked Sendable {
        var calls = 0
        var expectedNames: [String] = []
        var result: ShortcutDescriptor?
        init(result: ShortcutDescriptor?) { self.result = result }
        func importArtifact(at artifactURL: URL, expectedName: String, excludingShortcutIDs: Set<String>) throws -> ShortcutDescriptor? {
            calls += 1
            expectedNames.append(expectedName)
            return result
        }
        func replaceArtifact(at artifactURL: URL, expectedName: String, actionCount: Int, previousShortcutID: String, previousActionCount: Int) throws -> ShortcutDescriptor? {
            calls += 1
            expectedNames.append(expectedName)
            return result
        }
    }

    private let validSource = """
    #define name Managed Fixture
    #define color green
    #define glyph shortcuts
    #include 'actions/text'

    output("hello")
    """

    func testValidatorAcceptsBoundedStandardSourceWithoutReturningContent() throws {
        let result = try CherriSourceValidator().validate(Data(validSource.utf8))

        XCTAssertEqual(result.sourceBytes, Data(validSource.utf8).count)
        XCTAssertEqual(result.sourceSHA256.count, 64)
        XCTAssertEqual(result.declaredName, "Managed Fixture")
        XCTAssertEqual(result.includeCount, 1)
    }

    func testValidatorRejectsRemoteLocalAndSensitiveFeatures() {
        let rejected = [
            "#include '@owner/package'\noutput(\"x\")",
            "#include '../private'\noutput(\"x\")",
            "#ref Secret abc123\noutput(\"x\")",
            "const value = embedFile(\"secret.txt\")",
            "const value = base64File(\"secret.txt\")",
            "rawAction(\"com.example.private\", {})",
            "action 'com.example.private' custom()\ncustom()",
            "const apiToken = \"literal-value\"\noutput(apiToken)",
        ]

        for source in rejected {
            let namedSource = "#define name Rejected Fixture\n\(source)"
            XCTAssertThrowsError(try CherriSourceValidator().validate(Data(namedSource.utf8)), source) { error in
                XCTAssertEqual(error as? ShortcutsError, .authorSourceForbidden)
            }
        }
    }

    func testValidatorRequiresNameAndRejectsOversizedOrInvalidUTF8Source() {
        XCTAssertThrowsError(try CherriSourceValidator().validate(Data("output(\"x\")".utf8))) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorSourceInvalid)
        }
        XCTAssertThrowsError(try CherriSourceValidator().validate(Data(repeating: 0x61, count: CherriSourceValidator.maximumSourceBytes + 1))) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorSourceTooLarge)
        }
        XCTAssertThrowsError(try CherriSourceValidator().validate(Data([0xff, 0xfe]))) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorSourceInvalid)
        }
    }

    func testToolchainArgumentsAlwaysDisableSigningAndNetworkFallback() {
        XCTAssertEqual(
            CherriAuthoringBridge.compilerArguments(inputName: "source.cherri"),
            ["source.cherri", "--skip-sign", "--derive-uuids", "--no-ansi"]
        )
        XCTAssertEqual(
            CherriAuthoringBridge.signingArguments(input: "/private/in.shortcut", output: "/private/out.shortcut", mode: .anyone),
            ["sign", "--mode", "anyone", "--input", "/private/in.shortcut", "--output", "/private/out.shortcut"]
        )
    }

    func testAuthorCommandTimeoutForceKillsProcessThatIgnoresTerminate() throws {
        let startedAt = Date()
        let result = try SystemAuthorCommandRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; exec /usr/bin/tail -f /dev/null"],
            currentDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 0.05
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testArtifactParserReturnsOnlyBoundedMetadata() throws {
        let plist: [String: Any] = [
            "WFWorkflowActions": [
                ["WFWorkflowActionIdentifier": "is.workflow.actions.text"],
                ["WFWorkflowActionIdentifier": "is.workflow.actions.output"],
            ],
            "WFWorkflowClientVersion": "4033.0.4.3",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let metadata = try CherriAuthoringBridge.parseUnsignedArtifact(data)

        XCTAssertEqual(metadata.actionCount, 1)
        XCTAssertEqual(metadata.clientVersion, "4033.0.4.3")
    }

    func testArtifactParserRejectsMissingOrExcessiveActionGraph() throws {
        let missing = try PropertyListSerialization.data(fromPropertyList: ["x": true], format: .xml, options: 0)
        XCTAssertThrowsError(try CherriAuthoringBridge.parseUnsignedArtifact(missing))

        let outputOnly = try PropertyListSerialization.data(fromPropertyList: [
            "WFWorkflowActions": [["WFWorkflowActionIdentifier": "is.workflow.actions.output"]],
        ], format: .xml, options: 0)
        XCTAssertThrowsError(try CherriAuthoringBridge.parseUnsignedArtifact(outputOnly))

        let actions = Array(repeating: ["WFWorkflowActionIdentifier": "x"], count: CherriAuthoringBridge.maximumActionCount + 1)
        let excessive = try PropertyListSerialization.data(fromPropertyList: ["WFWorkflowActions": actions], format: .xml, options: 0)
        XCTAssertThrowsError(try CherriAuthoringBridge.parseUnsignedArtifact(excessive))
    }

    func testManagedRegistryIsPrivateAtomicAndContainsNoSourceOrName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 100)
        let store = ShortcutsManagedRegistry(directory: root, now: { now })
        let record = ManagedShortcutRecord(
            shortcutID: ShortcutsOpaqueID.shortcut(scriptingID: "fixture"),
            sourceSHA256: String(repeating: "a", count: 64),
            compiledSHA256: String(repeating: "b", count: 64),
            actionCount: 2,
            compilerVersion: "2.3.0",
            createdAt: now,
            updatedAt: now
        )

        try store.upsert(record)
        XCTAssertEqual(try store.record(shortcutID: record.shortcutID), record)
        let directoryMode = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue)
        let fileMode = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber)?.intValue)
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
        let persisted = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(persisted.contains("#define"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("fixture name"))
    }

    func testManagedRegistryRejectsInvalidRecordsAndPreservesCreationTimeOnUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var instant = Date(timeIntervalSince1970: 100)
        let store = ShortcutsManagedRegistry(directory: root, now: { instant })
        let id = ShortcutsOpaqueID.shortcut(scriptingID: "fixture")
        let first = ManagedShortcutRecord(shortcutID: id, sourceSHA256: String(repeating: "a", count: 64), compiledSHA256: String(repeating: "b", count: 64), actionCount: 1, compilerVersion: "2.3.0", createdAt: instant, updatedAt: instant)
        try store.upsert(first)
        instant = Date(timeIntervalSince1970: 200)
        try store.upsert(ManagedShortcutRecord(shortcutID: id, sourceSHA256: String(repeating: "c", count: 64), compiledSHA256: String(repeating: "d", count: 64), actionCount: 2, compilerVersion: "2.3.0", createdAt: instant, updatedAt: instant))
        let updated = try XCTUnwrap(store.record(shortcutID: id))
        XCTAssertEqual(updated.createdAt, first.createdAt)
        XCTAssertEqual(updated.updatedAt, instant)

        XCTAssertThrowsError(try store.upsert(ManagedShortcutRecord(shortcutID: "raw", sourceSHA256: "bad", compiledSHA256: "bad", actionCount: 0, compilerVersion: "", createdAt: instant, updatedAt: instant)))
    }

    func testCreateDryRunBuildsPrivatelyWithoutImportRegistryOrReceipt() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let importer = VisibleImporterStub(result: nil)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [], folders: [], complete: true))

        let result = try service.create(sourceURL: fixture.source, signingMode: .peopleWhoKnowMe, apply: false, idempotent: true)

        XCTAssertEqual(result.operation, "create_preview")
        XCTAssertEqual(result.verification, .notApplied)
        XCTAssertEqual(builder.buildCalls, 1)
        XCTAssertEqual(importer.calls, 0)
        XCTAssertTrue(try fixture.registry.list().isEmpty)
        XCTAssertNil(try fixture.receipts.receipt(sourceSHA256: fixture.buildResult.sourceSHA256))
    }

    func testCreateApplyImportsReadbackRegistersAndCompletesPrivateReceipt() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let descriptor = ShortcutDescriptor(scriptingID: "created-id", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: true, actionCount: 0, color: [], iconAvailable: false)
        let importer = VisibleImporterStub(result: descriptor)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [], folders: [], complete: true))

        let result = try service.create(sourceURL: fixture.source, signingMode: .anyone, apply: true, idempotent: true)

        XCTAssertEqual(result.verification, .readbackConfirmed)
        XCTAssertEqual(result.observedActionCount, 0)
        XCTAssertNotNil(result.nextAction)
        XCTAssertEqual(result.shortcutID, ShortcutsOpaqueID.shortcut(scriptingID: "created-id"))
        XCTAssertEqual(importer.calls, 1)
        XCTAssertEqual(try fixture.registry.list().count, 1)
        XCTAssertEqual(try fixture.receipts.receipt(sourceSHA256: fixture.buildResult.sourceSHA256)?.state, .saved)
    }

    func testCreateInFlightReceiptPreventsAutomaticRetry() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.receipts.saveInFlight(build: fixture.buildResult)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let importer = VisibleImporterStub(result: nil)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [], folders: [], complete: true))

        let result = try service.create(sourceURL: fixture.source, signingMode: .anyone, apply: true, idempotent: true)

        XCTAssertEqual(result.verification, .outcomeUnknown)
        XCTAssertNotNil(result.nextAction)
        XCTAssertEqual(builder.buildCalls, 0)
        XCTAssertEqual(importer.calls, 0)
    }

    func testCompletedReceiptWithVisibleShortcutButMissingRegistryRequiresRepair() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let shortcutID = ShortcutsOpaqueID.shortcut(scriptingID: "created-id")
        try fixture.receipts.saveCompleted(build: fixture.buildResult, shortcutID: shortcutID)
        let descriptor = ShortcutDescriptor(scriptingID: "created-id", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 2, color: [], iconAvailable: false)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let importer = VisibleImporterStub(result: nil)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [descriptor], folders: [], complete: true))

        let result = try service.create(sourceURL: fixture.source, signingMode: .anyone, apply: true, idempotent: true)

        XCTAssertEqual(result.verification, .idempotencyReceiptReadbackConfirmed)
        XCTAssertFalse(result.registrySaved)
        XCTAssertNotNil(result.nextAction)
        XCTAssertEqual(builder.buildCalls, 0)
        XCTAssertEqual(importer.calls, 0)
    }

    func testCreateRejectsExistingNameAndUnknownImportDoesNotRegister() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 1, color: [], iconAvailable: false)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let importer = VisibleImporterStub(result: nil)
        let conflicting = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [existing], folders: [], complete: true))
        XCTAssertThrowsError(try conflicting.create(sourceURL: fixture.source, signingMode: .anyone, apply: true, idempotent: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorNameConflict)
        }

        let unknown = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [], folders: [], complete: true))
        let result = try unknown.create(sourceURL: fixture.source, signingMode: .anyone, apply: true, idempotent: false)
        XCTAssertEqual(result.verification, .outcomeUnknown)
        XCTAssertTrue(try fixture.registry.list().isEmpty)
    }

    func testUpdateRequiresManagedIdentityAndExpectedSourceHash() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 1, color: [], iconAvailable: false)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: VisibleImporterStub(result: nil), snapshot: .init(shortcuts: [existing], folders: [], complete: true))

        XCTAssertThrowsError(try service.update(id: id, sourceURL: fixture.source, expectedSourceSHA256: String(repeating: "a", count: 64), strategy: .retainOld, signingMode: .anyone, apply: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorManagedOnly)
        }

        let old = ManagedShortcutRecord(shortcutID: id, sourceSHA256: String(repeating: "a", count: 64), compiledSHA256: String(repeating: "c", count: 64), actionCount: 1, compilerVersion: "2.3.0", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
        try fixture.registry.upsert(old)
        XCTAssertThrowsError(try service.update(id: id, sourceURL: fixture.source, expectedSourceSHA256: String(repeating: "f", count: 64), strategy: .retainOld, signingMode: .anyone, apply: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorSourceConflict)
        }
        XCTAssertEqual(builder.buildCalls, 0)
    }

    func testUpdateDryRunBuildsCandidateWithoutImportOrRegistryMutation() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let oldHash = String(repeating: "a", count: 64)
        try fixture.registry.upsert(ManagedShortcutRecord(shortcutID: id, sourceSHA256: oldHash, compiledSHA256: String(repeating: "c", count: 64), actionCount: 1, compilerVersion: "2.3.0", createdAt: Date(), updatedAt: Date()))
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 1, color: [], iconAvailable: false)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let importer = VisibleImporterStub(result: nil)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [existing], folders: [], complete: true))

        let result = try service.update(id: id, sourceURL: fixture.source, expectedSourceSHA256: oldHash, strategy: .retainOld, signingMode: .anyone, apply: false)

        XCTAssertEqual(result.operation, "update_preview")
        XCTAssertEqual(result.verification, .notApplied)
        XCTAssertEqual(builder.buildCalls, 1)
        XCTAssertEqual(importer.calls, 0)
        XCTAssertEqual(try fixture.registry.record(shortcutID: id)?.sourceSHA256, oldHash)
    }

    func testUpdateRetainOldImportsCandidateAndAtomicallyMovesManagedIdentity() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let oldID = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let oldHash = String(repeating: "a", count: 64)
        try fixture.registry.upsert(ManagedShortcutRecord(shortcutID: oldID, sourceSHA256: oldHash, compiledSHA256: String(repeating: "c", count: 64), actionCount: 1, compilerVersion: "2.3.0", createdAt: Date(), updatedAt: Date()))
        let oldBuild = ShortcutAuthorBuildResult(sourceSHA256: oldHash, sourceBytes: 10, compiledSHA256: String(repeating: "c", count: 64), compiledBytes: 10, actionCount: 1, compiler: "cherri", compilerVersion: "2.3.0", clientVersion: nil, signingMode: .anyone, experimental: true)
        try fixture.receipts.saveCompleted(build: oldBuild, shortcutID: oldID)
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 1, color: [], iconAvailable: false)
        let candidateName = "Managed Fixture (macos-data \(fixture.buildResult.sourceSHA256.prefix(8)))"
        let candidate = ShortcutDescriptor(scriptingID: "candidate", name: candidateName, subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 2, color: [], iconAvailable: false)
        let importer = VisibleImporterStub(result: candidate)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let service = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [existing], folders: [], complete: true))

        let result = try service.update(id: oldID, sourceURL: fixture.source, expectedSourceSHA256: oldHash, strategy: .retainOld, signingMode: .anyone, apply: true)

        let newID = ShortcutsOpaqueID.shortcut(scriptingID: "candidate")
        XCTAssertEqual(result.shortcutID, newID)
        XCTAssertEqual(result.previousShortcutID, oldID)
        XCTAssertTrue(result.oldRetained)
        XCTAssertEqual(importer.expectedNames, [candidateName])
        XCTAssertEqual(builder.declaredNames, [candidateName])
        XCTAssertNil(try fixture.registry.record(shortcutID: oldID))
        XCTAssertEqual(try fixture.registry.record(shortcutID: newID)?.sourceSHA256, fixture.buildResult.sourceSHA256)
        XCTAssertNil(try fixture.receipts.receipt(sourceSHA256: oldHash))
        XCTAssertEqual(try fixture.receipts.receipt(sourceSHA256: fixture.buildResult.sourceSHA256)?.state, .saved)
    }

    func testRetainOldRewritesOnlyCompiledNameAndPreservesManagedSourceHash() throws {
        let rewritten = try ShortcutsAuthoringService.source(Data(validSource.utf8), replacingDeclaredNameWith: "Managed Fixture (macos-data abcdef12)")
        let text = try XCTUnwrap(String(data: rewritten, encoding: .utf8))

        XCTAssertTrue(text.contains("#define name Managed Fixture (macos-data abcdef12)"))
        XCTAssertTrue(text.contains("output(\"hello\")"))
        XCTAssertFalse(text.contains("#define name Managed Fixture\n"))
    }

    func testUpdateReplaceRejectsSameActionCountAsUnverifiable() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let oldID = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let oldHash = String(repeating: "a", count: 64)
        try fixture.registry.upsert(ManagedShortcutRecord(shortcutID: oldID, sourceSHA256: oldHash, compiledSHA256: String(repeating: "c", count: 64), actionCount: 2, compilerVersion: "2.3.0", createdAt: Date(), updatedAt: Date()))
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 2, color: [], iconAvailable: false)
        let service = makeAuthoringService(fixture: fixture, builder: AuthorBuilderStub(result: fixture.buildResult), importer: VisibleImporterStub(result: nil), snapshot: .init(shortcuts: [existing], folders: [], complete: true))

        XCTAssertThrowsError(try service.update(id: oldID, sourceURL: fixture.source, expectedSourceSHA256: oldHash, strategy: .replace, signingMode: .anyone, apply: true)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorUpdateUnverifiable)
        }
    }

    func testUpdateReplaceRejectsUnreliableObservedActionCount() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let oldID = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let oldHash = String(repeating: "a", count: 64)
        try fixture.registry.upsert(ManagedShortcutRecord(shortcutID: oldID, sourceSHA256: oldHash, compiledSHA256: String(repeating: "c", count: 64), actionCount: 1, compilerVersion: "2.3.0", createdAt: Date(), updatedAt: Date()))
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: true, actionCount: 0, color: [], iconAvailable: false)
        let importer = VisibleImporterStub(result: nil)
        let service = makeAuthoringService(fixture: fixture, builder: AuthorBuilderStub(result: fixture.buildResult), importer: importer, snapshot: .init(shortcuts: [existing], folders: [], complete: true))

        XCTAssertThrowsError(try service.update(id: oldID, sourceURL: fixture.source, expectedSourceSHA256: oldHash, strategy: .replace, signingMode: .anyone, apply: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorUpdateUnverifiable)
        }
        XCTAssertEqual(importer.calls, 0)
    }

    func testUpdateRejectsAmbiguousManagedNameAndExistingRetainOldCandidate() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let oldID = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let oldHash = String(repeating: "a", count: 64)
        try fixture.registry.upsert(ManagedShortcutRecord(shortcutID: oldID, sourceSHA256: oldHash, compiledSHA256: String(repeating: "c", count: 64), actionCount: 1, compilerVersion: "2.3.0", createdAt: Date(), updatedAt: Date()))
        let existing = ShortcutDescriptor(scriptingID: "existing", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 1, color: [], iconAvailable: false)
        let duplicate = ShortcutDescriptor(scriptingID: "duplicate", name: "Managed Fixture", subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 1, color: [], iconAvailable: false)
        let builder = AuthorBuilderStub(result: fixture.buildResult)
        let importer = VisibleImporterStub(result: nil)
        let ambiguous = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [existing, duplicate], folders: [], complete: true))

        XCTAssertThrowsError(try ambiguous.update(id: oldID, sourceURL: fixture.source, expectedSourceSHA256: oldHash, strategy: .replace, signingMode: .anyone, apply: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorNameConflict)
        }

        let candidateName = "Managed Fixture (macos-data \(fixture.buildResult.sourceSHA256.prefix(8)))"
        let candidate = ShortcutDescriptor(scriptingID: "candidate", name: candidateName, subtitle: "", folderScriptingID: nil, acceptsInput: false, actionCount: 2, color: [], iconAvailable: false)
        let candidateConflict = makeAuthoringService(fixture: fixture, builder: builder, importer: importer, snapshot: .init(shortcuts: [existing, candidate], folders: [], complete: true))
        XCTAssertThrowsError(try candidateConflict.update(id: oldID, sourceURL: fixture.source, expectedSourceSHA256: oldHash, strategy: .retainOld, signingMode: .anyone, apply: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .authorNameConflict)
        }
        XCTAssertEqual(importer.calls, 0)
    }

    func testManagedForgetPreviewsThenAtomicallyRemovesRegistryAndReceipt() throws {
        let fixture = try makeAuthoringFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = ShortcutsOpaqueID.shortcut(scriptingID: "existing")
        let record = ManagedShortcutRecord(shortcutID: id, sourceSHA256: fixture.buildResult.sourceSHA256, compiledSHA256: fixture.buildResult.compiledSHA256, actionCount: fixture.buildResult.actionCount, compilerVersion: "2.3.0", createdAt: Date(), updatedAt: Date())
        try fixture.registry.upsert(record)
        try fixture.receipts.saveCompleted(build: fixture.buildResult, shortcutID: id)
        let service = makeAuthoringService(fixture: fixture, builder: AuthorBuilderStub(result: fixture.buildResult), importer: VisibleImporterStub(result: nil), snapshot: .init(shortcuts: [], folders: [], complete: true))

        XCTAssertFalse(try service.forgetManaged(id: id, apply: false).changed)
        XCTAssertNotNil(try fixture.registry.record(shortcutID: id))
        XCTAssertTrue(try service.forgetManaged(id: id, apply: true).changed)
        XCTAssertNil(try fixture.registry.record(shortcutID: id))
        XCTAssertNil(try fixture.receipts.receipt(sourceSHA256: fixture.buildResult.sourceSHA256))
    }

    private struct AuthoringFixture {
        let root: URL
        let source: URL
        let buildResult: ShortcutAuthorBuildResult
        let registry: ShortcutsManagedRegistry
        let receipts: ShortcutsAuthoringReceiptStore
    }

    private func makeAuthoringFixture() throws -> AuthoringFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("fixture.cherri")
        try Data("#define name Managed Fixture\noutput(\"ok\")".utf8).write(to: source)
        let result = ShortcutAuthorBuildResult(sourceSHA256: CherriSourceValidator.hash(try Data(contentsOf: source)), sourceBytes: Int((try Data(contentsOf: source)).count), compiledSHA256: String(repeating: "b", count: 64), compiledBytes: 6, actionCount: 2, compiler: "cherri", compilerVersion: "2.3.0", clientVersion: "4033", signingMode: .anyone, experimental: true)
        return AuthoringFixture(root: root, source: source, buildResult: result, registry: ShortcutsManagedRegistry(directory: root.appendingPathComponent("registry"), now: { Date(timeIntervalSince1970: 100) }), receipts: ShortcutsAuthoringReceiptStore(directory: root.appendingPathComponent("receipts"), now: { Date(timeIntervalSince1970: 100) }))
    }

    private func makeAuthoringService(fixture: AuthoringFixture, builder: AuthorBuilderStub, importer: VisibleImporterStub, snapshot: ShortcutsMetadataSnapshot) -> ShortcutsAuthoringService {
        ShortcutsAuthoringService(builder: builder, validator: CherriSourceValidator(), metadataBridge: MetadataBridgeFixed(snapshot), importer: importer, registry: fixture.registry, receipts: fixture.receipts)
    }

    private struct MetadataBridgeFixed: ShortcutsMetadataBridging {
        let value: ShortcutsMetadataSnapshot
        init(_ value: ShortcutsMetadataSnapshot) { self.value = value }
        func snapshot(maximumShortcuts: Int, maximumFolders: Int) throws -> ShortcutsMetadataSnapshot { value }
    }
}
