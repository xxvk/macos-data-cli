import Core
import XCTest
@testable import ShortcutsAdapter

final class ShortcutsAdapterTests: XCTestCase {
    private final class ProbeStub: ShortcutsAutomationProbing, @unchecked Sendable {
        let value: ShortcutsAutomationStatus
        private(set) var requestValues: [Bool] = []
        init(_ value: ShortcutsAutomationStatus) { self.value = value }
        func status(requestConsent: Bool) -> ShortcutsAutomationStatus {
            requestValues.append(requestConsent)
            return value
        }
    }

    private struct MetadataBridgeStub: ShortcutsMetadataBridging {
        let value: ShortcutsMetadataSnapshot
        func snapshot(maximumShortcuts: Int, maximumFolders: Int) throws -> ShortcutsMetadataSnapshot { value }
    }

    private final class MutationBridgeStub: ShortcutsMutationBridging, @unchecked Sendable {
        private(set) var calls: [(String, String)] = []
        var returnedFolderID: String
        init(returnedFolderID: String) { self.returnedFolderID = returnedFolderID }
        func move(shortcutScriptingID: String, destinationFolderScriptingID: String) throws -> String {
            calls.append((shortcutScriptingID, destinationFolderScriptingID))
            return returnedFolderID
        }
    }

    private final class RunBridgeStub: ShortcutsRunBridging, @unchecked Sendable {
        private(set) var identifiers: [String] = []
        var value = ShortcutsRunDescriptor(output: Data("done".utf8), outputPath: nil, outputBytes: 4, outputSHA256: String(repeating: "a", count: 64))
        func run(identifier: String, inputPaths: [URL], outputPath: URL?, outputType: String, timeoutSeconds: Int) throws -> ShortcutsRunDescriptor {
            identifiers.append(identifier)
            return value
        }
    }

    private func snapshot() -> ShortcutsMetadataSnapshot {
        ShortcutsMetadataSnapshot(
            shortcuts: [
                .init(scriptingID: "shortcut-b", name: "Duplicate", subtitle: "Second", folderScriptingID: "folder-b", acceptsInput: true, actionCount: 3, color: [1, 2, 3], iconAvailable: true),
                .init(scriptingID: "shortcut-a", name: "Duplicate", subtitle: "First", folderScriptingID: "folder-a", acceptsInput: false, actionCount: 2, color: [4, 5, 6], iconAvailable: true)
            ],
            folders: [
                .init(scriptingID: "folder-b", name: "Work"),
                .init(scriptingID: "folder-a", name: "Personal")
            ],
            complete: true
        )
    }

    private func store(
        permission: ShortcutsAutomationStatus = .available,
        mutation: MutationBridgeStub? = nil,
        runner: RunBridgeStub? = nil
    ) -> ShortcutsStore {
        ShortcutsStore(
            permission: ShortcutsPermissionService(probe: ProbeStub(permission)),
            metadataBridge: MetadataBridgeStub(value: snapshot()),
            mutationBridge: mutation ?? MutationBridgeStub(returnedFolderID: "folder-b"),
            runBridge: runner ?? RunBridgeStub()
        )
    }

    func testColdShortcutsEventsHelperMayBeStartedByMetadataBridge() throws {
        let result = try store(permission: .targetNotRunning).list(limit: 10, cursor: nil, folderID: nil)
        XCTAssertEqual(result.items.count, 2)
    }

    func testPermissionStatusDoesNotRequestConsent() {
        let probe = ProbeStub(.requiresConsent)
        let result = ShortcutsPermissionService(probe: probe).check()
        XCTAssertEqual(result.access, .requiresConsent)
        XCTAssertFalse(result.readable)
        XCTAssertEqual(probe.requestValues, [false])
    }

    func testResourceCapabilityTracksAutomationPermission() {
        let available = ShortcutsResourceMapper.map(status: .available)
        XCTAssertEqual(available.kind, .shortcutsLibrary)
        XCTAssertTrue(available.capabilities.readable)
        XCTAssertTrue(available.capabilities.writable)
        let denied = ShortcutsResourceMapper.map(status: .denied)
        XCTAssertFalse(denied.capabilities.readable)
        XCTAssertFalse(denied.capabilities.writable)
        XCTAssertEqual(denied.capabilities.permission, .denied)
    }

    func testListUsesOpaqueIDsAndPreservesDuplicateNames() throws {
        let result = try store().list(limit: 10, cursor: nil, folderID: nil)
        XCTAssertEqual(result.items.map(\.name), ["Duplicate", "Duplicate"])
        XCTAssertEqual(Set(result.items.map(\.id)).count, 2)
        XCTAssertTrue(result.items.allSatisfy { $0.id.hasPrefix("shortcut_") })
        XCTAssertEqual(Set(result.items.map(\.actionCount)), Set([2, 3]))
        XCTAssertEqual(result.items.map(\.id), result.items.map(\.id).sorted())
        XCTAssertFalse(result.truncated)
    }

    func testFolderFilterAndPaginationAreBoundToFilter() throws {
        let all = try store().folders(limit: 1, cursor: nil)
        XCTAssertEqual(all.items.count, 1)
        XCTAssertTrue(all.truncated)
        let folderID = ShortcutsOpaqueID.folder(scriptingID: "folder-b")
        let filtered = try store().list(limit: 10, cursor: nil, folderID: folderID)
        XCTAssertEqual(filtered.items.map(\.id), [ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-b")])
        XCTAssertThrowsError(try store().list(limit: 10, cursor: all.nextCursor, folderID: folderID))
    }

    func testGetResolvesOnlyOpaqueID() throws {
        let id = ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-a")
        let value = try store().get(id: id)
        XCTAssertEqual(value.id, id)
        XCTAssertEqual(value.subtitle, "First")
        XCTAssertEqual(value.folderID, ShortcutsOpaqueID.folder(scriptingID: "folder-a"))
        XCTAssertThrowsError(try store().get(id: "shortcut-a")) { error in
            XCTAssertEqual(error as? ShortcutsError, .invalidIdentifier)
        }
    }

    func testMoveDryRunDoesNotCallMutationBridgeAndSameFolderIsNoOp() throws {
        let mutation = MutationBridgeStub(returnedFolderID: "folder-b")
        let value = try store(mutation: mutation).move(
            id: ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-a"),
            destinationFolderID: ShortcutsOpaqueID.folder(scriptingID: "folder-b"),
            apply: false
        )
        XCTAssertTrue(value.dryRun)
        XCTAssertTrue(value.changed)
        XCTAssertEqual(mutation.calls.count, 0)

        let noOp = try store(mutation: mutation).move(
            id: ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-a"),
            destinationFolderID: ShortcutsOpaqueID.folder(scriptingID: "folder-a"),
            apply: true
        )
        XCTAssertFalse(noOp.changed)
        XCTAssertEqual(mutation.calls.count, 0)
    }

    func testMoveApplyUsesRawIDsAndVerifiesReadback() throws {
        let mutation = MutationBridgeStub(returnedFolderID: "folder-b")
        let value = try store(mutation: mutation).move(
            id: ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-a"),
            destinationFolderID: ShortcutsOpaqueID.folder(scriptingID: "folder-b"),
            apply: true
        )
        XCTAssertEqual(mutation.calls.count, 1)
        XCTAssertEqual(mutation.calls.first?.0, "shortcut-a")
        XCTAssertEqual(mutation.calls.first?.1, "folder-b")
        XCTAssertEqual(value.verification, .readbackConfirmed)
    }

    func testMetadataScriptIsBoundedAndNeverRunsShortcuts() {
        let source = SystemShortcutsMetadataBridge.snapshotScript(maximumShortcuts: 200, maximumFolders: 200, timeoutSeconds: 5)
        XCTAssertTrue(source.contains("with timeout of 5 seconds"))
        XCTAssertTrue(source.contains("shortcutLimitReached"))
        XCTAssertFalse(source.contains("run shortcut"))
    }

    func testRunResolvesOpaqueIDAndReturnsBoundedText() throws {
        let runner = RunBridgeStub()
        let id = ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-a")
        let result = try store(runner: runner).run(id: id, inputPaths: [], outputPath: nil, outputType: "public.utf8-plain-text", timeoutSeconds: 30)
        XCTAssertEqual(runner.identifiers, ["shortcut-a"])
        XCTAssertEqual(result.output, "done")
        XCTAssertEqual(result.outputBytes, 4)
        XCTAssertEqual(result.verification, .completed)
    }

    func testRunRejectsUnboundedArgumentsBeforeCallingBridge() {
        let runner = RunBridgeStub()
        let urls = (0..<17).map { URL(fileURLWithPath: "/tmp/\($0)") }
        XCTAssertThrowsError(try store(runner: runner).run(id: ShortcutsOpaqueID.shortcut(scriptingID: "shortcut-a"), inputPaths: urls, outputPath: nil, outputType: "public.utf8-plain-text", timeoutSeconds: 30))
        XCTAssertTrue(runner.identifiers.isEmpty)
    }

    func testSystemRunArgumentsUseIdentifierNotName() {
        let args = SystemShortcutsRunBridge.arguments(identifier: "raw-id", inputPaths: [URL(fileURLWithPath: "/tmp/input")], outputPath: URL(fileURLWithPath: "/tmp/output"), outputType: "public.data")
        XCTAssertEqual(args.prefix(2), ["run", "raw-id"])
        XCTAssertTrue(args.contains("--input-path"))
        XCTAssertTrue(args.contains("--output-path"))
    }

    func testPlaintextRunCapturesStandardOutputInsteadOfRequestingOutputPath() {
        let args = SystemShortcutsRunBridge.arguments(identifier: "raw-id", inputPaths: [], outputPath: nil, outputType: "public.utf8-plain-text")
        XCTAssertEqual(args, ["run", "raw-id"])
    }

    func testMoveScriptEscapesIdentifiersAndReadsBackFolder() {
        let source = SystemShortcutsMutationBridge.moveScript(shortcutScriptingID: "shortcut-\"\\", destinationFolderScriptingID: "folder-\"\\")
        XCTAssertTrue(source.contains("set folder of selectedShortcut to destinationFolder"))
        XCTAssertTrue(source.contains("return (id of folder of selectedShortcut) as text"))
        XCTAssertFalse(source.contains("shortcut-\"\\\""))
    }
}
