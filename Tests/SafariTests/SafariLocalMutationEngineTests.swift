import Foundation
import Testing
@testable import SafariAdapter

@Suite("Safari local-only mutation engine")
struct SafariLocalMutationEngineTests {
    @Test("Bookmark create update move and delete preserve unrelated nodes")
    func bookmarkCRUD() throws {
        let engine = SafariLocalMutationEngine()
        let source = try data(root())
        let folderA = SafariOpaqueID.folder(uuid: "FOLDER-A")
        let folderB = SafariOpaqueID.folder(uuid: "FOLDER-B")

        let created = try engine.prepare(
            data: source,
            operation: .createBookmark(parentID: folderA, index: 0, uuid: "NEW-BOOKMARK", title: "Created", url: "https://example.com/new")
        )
        let createdSnapshot = try SafariBookmarksParser.parse(data: created.outputData)
        let createdID = SafariOpaqueID.bookmark(uuid: "NEW-BOOKMARK")
        #expect(createdSnapshot.bookmarks.first(where: { $0.id == createdID })?.parentID == folderA)

        let updated = try engine.prepare(
            data: created.outputData,
            operation: .updateBookmark(id: createdID, title: "Updated", url: "https://example.com/updated")
        )
        #expect(try SafariBookmarksParser.parse(data: updated.outputData).bookmarks.first(where: { $0.id == createdID })?.title == "Updated")

        let moved = try engine.prepare(data: updated.outputData, operation: .moveBookmark(id: createdID, parentID: folderB, index: 0))
        #expect(try SafariBookmarksParser.parse(data: moved.outputData).bookmarks.first(where: { $0.id == createdID })?.parentID == folderB)

        let deleted = try engine.prepare(data: moved.outputData, operation: .deleteBookmark(id: createdID))
        #expect(try SafariBookmarksParser.parse(data: deleted.outputData).bookmarks.contains(where: { $0.id == createdID }) == false)
        #expect(deleted.untouchedSubtreeHashesPreserved)
    }

    @Test("Folder CRUD rejects cycles and non-empty deletion")
    func folderCRUDGuards() throws {
        let engine = SafariLocalMutationEngine()
        let folderA = SafariOpaqueID.folder(uuid: "FOLDER-A")
        let folderB = SafariOpaqueID.folder(uuid: "FOLDER-B")
        let created = try engine.prepare(
            data: try data(root()),
            operation: .createFolder(parentID: folderA, index: 0, uuid: "NEW-FOLDER", title: "New Folder")
        )
        let newID = SafariOpaqueID.folder(uuid: "NEW-FOLDER")
        let renamed = try engine.prepare(data: created.outputData, operation: .renameFolder(id: newID, title: "Renamed"))
        #expect(try SafariBookmarksParser.parse(data: renamed.outputData).bookmarks.first(where: { $0.id == newID })?.title == "Renamed")

        #expect(throws: SafariLocalMutationError.cycle) {
            try engine.prepare(data: renamed.outputData, operation: .moveFolder(id: folderA, parentID: newID, index: 0))
        }
        #expect(throws: SafariLocalMutationError.folderNotEmpty) {
            try engine.prepare(data: renamed.outputData, operation: .deleteFolder(id: folderA))
        }

        let moved = try engine.prepare(data: renamed.outputData, operation: .moveFolder(id: newID, parentID: folderB, index: 0))
        let deleted = try engine.prepare(data: moved.outputData, operation: .deleteFolder(id: newID))
        #expect(try SafariBookmarksParser.parse(data: deleted.outputData).bookmarks.contains(where: { $0.id == newID }) == false)
    }

    @Test("Invalid indexes roots duplicate UUIDs and unsafe URLs fail closed")
    func invalidMutations() throws {
        let engine = SafariLocalMutationEngine()
        let source = try data(root())
        let folderA = SafariOpaqueID.folder(uuid: "FOLDER-A")
        #expect(throws: SafariLocalMutationError.invalidIndex) {
            try engine.prepare(data: source, operation: .createFolder(parentID: folderA, index: 99, uuid: "NEW", title: "New"))
        }
        #expect(throws: SafariLocalMutationError.duplicateIdentifier) {
            try engine.prepare(data: source, operation: .createFolder(parentID: folderA, index: 0, uuid: "FOLDER-B", title: "Duplicate"))
        }
        #expect(throws: SafariLocalMutationError.invalidInput) {
            try engine.prepare(data: source, operation: .createBookmark(parentID: folderA, index: 0, uuid: "NEW", title: "New", url: "file:///tmp/private"))
        }
        #expect(throws: SafariLocalMutationError.rootMutation) {
            try engine.prepare(data: source, operation: .deleteFolder(id: SafariOpaqueID.folder(uuid: "ROOT")))
        }
        #expect(throws: SafariLocalMutationError.invalidIdentifier) {
            try engine.prepare(data: source, operation: .moveBookmark(id: folderA, parentID: SafariOpaqueID.folder(uuid: "FOLDER-B"), index: 0))
        }
    }

    @Test("Strict JSON rejects unknown fields and dry-run never creates recovery")
    func strictJSONAndDryRun() throws {
        #expect(throws: SafariError.invalidInput) {
            try SafariLocalMutationInput.decode(
                Data(#"{"parentID":"x","index":0,"title":"T","url":"https://example.com","unknown":true}"#.utf8),
                command: .bookmarkCreate
            )
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        try data(root()).write(to: source)
        let parent = SafariOpaqueID.folder(uuid: "FOLDER-B")
        let input = try SafariLocalMutationInput.decode(
            Data("{\"parentID\":\"\(parent)\",\"index\":0,\"title\":\"Preview\",\"url\":\"https://example.com/preview\"}".utf8),
            command: .bookmarkCreate
        )
        let before = try Data(contentsOf: source)
        let result = try SafariLocalMutationService(source: source).execute(input, apply: false, confirmation: nil)
        #expect(result.dryRun)
        #expect(result.syncStatus == "local_only")
        #expect(result.targetID == nil)
        #expect(result.sourceSHA256Before.count == 64)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("Atomic apply requires the dry-run hash and confirms read-back")
    func atomicApply() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        try data(root()).write(to: source)
        let parent = SafariOpaqueID.folder(uuid: "FOLDER-B")
        let service = SafariLocalMutationService(
            source: source,
            recoveryRoot: directory.appendingPathComponent("recovery/safari-local", isDirectory: true),
            safetyGate: .init(safariRunning: { false }, plistHasOpenHandles: { _ in false }, pause: { _ in }),
            writer: .init(safariRunning: { false }, plistHasOpenHandles: { _ in false })
        )
        let previewInput = try SafariLocalMutationInput.decode(
            Data("{\"parentID\":\"\(parent)\",\"index\":0,\"title\":\"Applied\",\"url\":\"https://example.com/applied\"}".utf8),
            command: .bookmarkCreate
        )
        let preview = try service.execute(previewInput, apply: false, confirmation: nil)
        let applyInput = try SafariLocalMutationInput.decode(
            Data("{\"parentID\":\"\(parent)\",\"index\":0,\"title\":\"Applied\",\"url\":\"https://example.com/applied\",\"expectedSourceSHA256\":\"\(preview.sourceSHA256Before)\"}".utf8),
            command: .bookmarkCreate
        )
        let applied = try service.execute(applyInput, apply: true, confirmation: nil)
        #expect(applied.verification == "readback_confirmed")
        #expect(applied.targetID != nil)
        #expect(applied.recoverySessionID != nil)
        #expect(try SafariBookmarksParser.parse(data: Data(contentsOf: source)).bookmarks.contains(where: { $0.url == "https://example.com/applied" }))
    }

    @Test("Semantic no-op preserves exact bytes and creates no recovery")
    func semanticNoop() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let original = try data(root())
        try original.write(to: source)
        let id = SafariOpaqueID.bookmark(uuid: "EXISTING")
        let previewInput = try SafariLocalMutationInput.decode(
            Data("{\"id\":\"\(id)\",\"title\":\"Existing\",\"url\":\"https://example.com/existing\"}".utf8),
            command: .bookmarkEdit
        )
        let service = SafariLocalMutationService(
            source: source,
            recoveryRoot: directory.appendingPathComponent("recovery/safari-local", isDirectory: true)
        )
        let preview = try service.execute(previewInput, apply: false, confirmation: nil)
        #expect(preview.changed == false)
        let applyInput = try SafariLocalMutationInput.decode(
            Data("{\"id\":\"\(id)\",\"title\":\"Existing\",\"url\":\"https://example.com/existing\",\"expectedSourceSHA256\":\"\(preview.sourceSHA256Before)\"}".utf8),
            command: .bookmarkEdit
        )
        let applied = try service.execute(applyInput, apply: true, confirmation: nil)
        #expect(applied.changed == false)
        #expect(applied.recoverySessionID == nil)
        #expect(try Data(contentsOf: source) == original)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recovery").path) == false)
    }

    @Test("Opt-in live-schema private copy completes full local CRUD with zero residue")
    func liveSchemaPrivateCopyCRUD() throws {
        guard ProcessInfo.processInfo.environment["MACOS_DATA_SAFARI_LOCAL_CRUD_COPY_GATE"] == "1" else { return }
        let live = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        try FileManager.default.copyItem(at: live, to: source)
        let before = try SafariBookmarksParser.parse(data: Data(contentsOf: source))
        let folders = before.bookmarks.filter { $0.kind == .folder && $0.title != "com.apple.ReadingList" }
        guard folders.count >= 2 else { throw SafariLocalMutationError.invalidParent }
        let parentA = folders[0]
        let parentB = folders.first(where: { $0.id != parentA.id && $0.parentID != parentA.id }) ?? folders[1]
        let marker = "macos-data-private-copy-\(UUID().uuidString.lowercased())"
        let service = SafariLocalMutationService(
            source: source,
            recoveryRoot: directory.appendingPathComponent("recovery/safari-local", isDirectory: true),
            safetyGate: .init(safariRunning: { false }, plistHasOpenHandles: { _ in false }, pause: { _ in }),
            writer: .init(safariRunning: { false }, plistHasOpenHandles: { _ in false })
        )

        let createdFolder = try apply(service, command: .folderCreate, object: [
            "parentID": parentA.id, "index": parentA.childCount, "title": marker
        ])
        let folderID = try #require(createdFolder.targetID)
        _ = try apply(service, command: .folderRename, object: ["id": folderID, "title": marker + "-renamed"])
        _ = try apply(service, command: .folderMove, object: ["id": folderID, "parentID": parentB.id, "index": 0])

        let createdBookmark = try apply(service, command: .bookmarkCreate, object: [
            "parentID": folderID, "index": 0, "title": marker, "url": "https://example.com/\(marker)"
        ])
        let bookmarkID = try #require(createdBookmark.targetID)
        _ = try apply(service, command: .bookmarkEdit, object: [
            "id": bookmarkID, "title": marker + "-edited", "url": "https://example.com/\(marker)/edited"
        ])
        _ = try apply(service, command: .bookmarkMove, object: [
            "id": bookmarkID, "parentID": parentA.id, "index": 0
        ])
        _ = try apply(service, command: .bookmarkDelete, object: ["id": bookmarkID], confirmation: "DELETE SAFARI BOOKMARK")
        _ = try apply(service, command: .folderDelete, object: ["id": folderID], confirmation: "DELETE SAFARI FOLDER")

        let after = try SafariBookmarksParser.parse(data: Data(contentsOf: source))
        #expect(after.bookmarks == before.bookmarks)
        #expect(after.readingList == before.readingList)
        #expect(after.bookmarks.contains(where: { $0.title.contains(marker) }) == false)
        print("Safari local CRUD private-copy gate passed: originalNodes=\(before.bookmarks.count) zeroResidue=true liveSourceUnchanged=true")
    }

    private func apply(
        _ service: SafariLocalMutationService,
        command: SafariLocalMutationCommand,
        object: [String: Any],
        confirmation: String? = nil
    ) throws -> SafariLocalMutationResult {
        do {
            let previewData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let preview = try service.execute(try .decode(previewData, command: command), apply: false, confirmation: nil)
            var appliedObject = object
            appliedObject["expectedSourceSHA256"] = preview.sourceSHA256Before
            let appliedData = try JSONSerialization.data(withJSONObject: appliedObject, options: [.sortedKeys])
            return try service.execute(try .decode(appliedData, command: command), apply: true, confirmation: confirmation)
        } catch {
            print("Safari local CRUD private-copy gate failed safely: operation=\(command.rawValue)")
            throw error
        }
    }

    private func data(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func root() -> [String: Any] {
        [
            "WebBookmarkFileVersion": 1,
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": "ROOT",
            "Title": "Root",
            "Children": [
                folder(uuid: "FOLDER-A", title: "A", children: [leaf(uuid: "EXISTING", title: "Existing")]),
                folder(uuid: "FOLDER-B", title: "B", children: [])
            ]
        ]
    }

    private func folder(uuid: String, title: String, children: [[String: Any]]) -> [String: Any] {
        ["WebBookmarkType": "WebBookmarkTypeList", "WebBookmarkUUID": uuid, "Title": title, "Children": children]
    }

    private func leaf(uuid: String, title: String) -> [String: Any] {
        [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": uuid,
            "URLString": "https://example.com/existing",
            "URIDictionary": ["title": title]
        ]
    }
}
