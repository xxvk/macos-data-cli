import Core
import AppKit
import XCTest
@testable import NotesAdapter

final class NotesAdapterTests: XCTestCase {
    private final class MutationBridgeStub: NotesMutationBridging, @unchecked Sendable {
        var createCalls = 0
        var renameCalls = 0
        var moveCalls = 0
        var replaceBodyCalls = 0
        var deleteCalls = 0
        var readCalls = 0
        var value: NotesMutationDescriptor
        var thrownError: Error?
        var deleteError: Error?
        var readError: Error?
        var readValues: [NotesMutationDescriptor] = []

        init(value: NotesMutationDescriptor) { self.value = value }

        func create(accountScriptingID: String, folderScriptingID: String, html: String) throws -> NotesMutationDescriptor {
            createCalls += 1
            if let thrownError { throw thrownError }
            return value
        }

        func rename(noteScriptingID: String, title: String) throws -> NotesMutationDescriptor {
            renameCalls += 1
            if let thrownError { throw thrownError }
            return value
        }

        func move(noteScriptingID: String, destinationFolderScriptingID: String) throws -> NotesMutationDescriptor {
            moveCalls += 1
            if let thrownError { throw thrownError }
            return value
        }

        func replaceBody(noteScriptingID: String, html: String) throws -> NotesMutationDescriptor {
            replaceBodyCalls += 1
            if let thrownError { throw thrownError }
            return value
        }

        func delete(noteScriptingID: String) throws -> NotesMutationDescriptor {
            deleteCalls += 1
            if let error = deleteError ?? thrownError { throw error }
            return value
        }

        func read(noteScriptingID: String) throws -> NotesMutationDescriptor {
            readCalls += 1
            if let error = readError ?? thrownError { throw error }
            if !readValues.isEmpty { return readValues.removeFirst() }
            return value
        }
    }

    private final class FolderMutationBridgeStub: NotesFolderMutationBridging, @unchecked Sendable {
        var createCalls = 0
        var renameCalls = 0
        var moveCalls = 0
        var readCalls = 0
        var value: NotesFolderMutationDescriptor
        var readValues: [NotesFolderMutationDescriptor] = []
        var thrownError: Error?
        var createError: Error?
        var renameError: Error?
        var moveError: Error?
        var readError: Error?

        init(value: NotesFolderMutationDescriptor) { self.value = value }
        func create(accountScriptingID: String, parentFolderScriptingID: String?, name: String) throws -> NotesFolderMutationDescriptor {
            createCalls += 1; if let error = createError ?? thrownError { throw error }; return value
        }
        func rename(folderScriptingID: String, name: String) throws -> NotesFolderMutationDescriptor {
            renameCalls += 1; if let error = renameError ?? thrownError { throw error }; return value
        }
        func move(folderScriptingID: String, accountScriptingID: String, destinationParentFolderScriptingID: String?) throws -> NotesFolderMutationDescriptor {
            moveCalls += 1; if let error = moveError ?? thrownError { throw error }; return value
        }
        func read(folderScriptingID: String) throws -> NotesFolderMutationDescriptor {
            readCalls += 1; if let error = readError ?? thrownError { throw error }
            if !readValues.isEmpty { return readValues.removeFirst() }
            return value
        }
    }

    private final class ProbeStub: NotesAutomationProbing, @unchecked Sendable {
        let result: NotesAutomationStatus
        private(set) var requestedConsent = false

        init(result: NotesAutomationStatus) {
            self.result = result
        }

        func status(requestConsent: Bool) -> NotesAutomationStatus {
            requestedConsent = requestConsent
            return result
        }
    }

    private struct BridgeStub: NotesMetadataBridging {
        let snapshotValue: NotesMetadataSnapshot

        func snapshot(maximumAccounts: Int, maximumFolders: Int) throws -> NotesMetadataSnapshot {
            snapshotValue
        }
    }


    private struct QueryBridgeStub: NotesQueryBridging {
        let snapshotValue: NotesQuerySnapshot

        func snapshot(maximumNotes: Int) throws -> NotesQuerySnapshot {
            snapshotValue
        }
    }

    private final class BodyBridgeStub: NotesBodyBridging, @unchecked Sendable {
        let value: String
        private(set) var calls = 0

        init(value: String) { self.value = value }

        func read(scriptingID: String, format: NotesBodyFormat) throws -> String {
            calls += 1
            return value
        }
    }

    private struct AttachmentBridgeStub: NotesAttachmentBridging {
        let snapshotValue: NotesAttachmentSnapshot

        func snapshot(scriptingID: String, maximumAttachments: Int) throws -> NotesAttachmentSnapshot {
            snapshotValue
        }
    }

    private func snapshot() -> NotesMetadataSnapshot {
        NotesMetadataSnapshot(
            accounts: [
                NotesAccountDescriptor(scriptingID: "account-icloud", name: "iCloud"),
                NotesAccountDescriptor(scriptingID: "account-local", name: "On My Mac")
            ],
            folders: [
                NotesFolderDescriptor(scriptingID: "folder-root", accountScriptingID: "account-icloud", parentScriptingID: nil, name: "Work", shared: false, depth: 0),
                NotesFolderDescriptor(scriptingID: "folder-child", accountScriptingID: "account-icloud", parentScriptingID: "folder-root", name: "Projects", shared: true, depth: 1),
                NotesFolderDescriptor(scriptingID: "folder-local", accountScriptingID: "account-local", parentScriptingID: nil, name: "Local", shared: false, depth: 0)
            ],
            defaultAccountScriptingID: "account-icloud",
            complete: true
        )
    }

    private func querySnapshot() -> NotesQuerySnapshot {
        NotesQuerySnapshot(
            notes: [
                NotesNoteDescriptor(
                    scriptingID: "note-new",
                    accountScriptingID: "account-icloud",
                    folderScriptingID: "folder-child",
                    title: "Project Alpha",
                    creationDate: Date(timeIntervalSince1970: 100),
                    modificationDate: Date(timeIntervalSince1970: 300),
                    passwordProtected: false,
                    shared: true
                ),
                NotesNoteDescriptor(
                    scriptingID: "note-old",
                    accountScriptingID: "account-icloud",
                    folderScriptingID: "folder-root",
                    title: "Project Archive",
                    creationDate: Date(timeIntervalSince1970: 50),
                    modificationDate: Date(timeIntervalSince1970: 200),
                    passwordProtected: true,
                    shared: false
                ),
                NotesNoteDescriptor(
                    scriptingID: "note-local",
                    accountScriptingID: "account-local",
                    folderScriptingID: "folder-local",
                    title: "Personal",
                    creationDate: nil,
                    modificationDate: nil,
                    passwordProtected: false,
                    shared: false
                )
            ],
            complete: true
        )
    }

    private func folderMutationSnapshot(complete: Bool = true) -> NotesMetadataSnapshot {
        NotesMetadataSnapshot(
            accounts: [
                NotesAccountDescriptor(scriptingID: "account-icloud", name: "iCloud", defaultFolderScriptingID: "folder-default"),
                NotesAccountDescriptor(scriptingID: "account-local", name: "On My Mac", defaultFolderScriptingID: "folder-local-default")
            ],
            folders: [
                NotesFolderDescriptor(scriptingID: "folder-default", accountScriptingID: "account-icloud", parentScriptingID: nil, name: "Notes", shared: false, depth: 0),
                NotesFolderDescriptor(scriptingID: "folder-root", accountScriptingID: "account-icloud", parentScriptingID: nil, name: "Root", shared: false, depth: 0),
                NotesFolderDescriptor(scriptingID: "folder-child", accountScriptingID: "account-icloud", parentScriptingID: "folder-root", name: "Child", shared: false, depth: 1),
                NotesFolderDescriptor(scriptingID: "folder-destination", accountScriptingID: "account-icloud", parentScriptingID: nil, name: "Destination", shared: false, depth: 0),
                NotesFolderDescriptor(scriptingID: "folder-shared", accountScriptingID: "account-icloud", parentScriptingID: nil, name: "Shared", shared: true, depth: 0),
                NotesFolderDescriptor(scriptingID: "folder-local-default", accountScriptingID: "account-local", parentScriptingID: nil, name: "Local Notes", shared: false, depth: 0)
            ],
            defaultAccountScriptingID: "account-icloud",
            complete: complete
        )
    }

    private func queryStore() -> NotesStore {
        NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: querySnapshot())
        )
    }

    func testPermissionServiceDoesNotPromptUnlessExplicitlyRequested() {
        let probe = ProbeStub(result: .requiresConsent)
        let service = NotesPermissionService(probe: probe)

        let result = service.check(requestConsent: false)

        XCTAssertEqual(result.access, .requiresConsent)
        XCTAssertFalse(result.requested)
        XCTAssertFalse(result.readable)
        XCTAssertFalse(probe.requestedConsent)
    }

    func testPermissionServicePassesExplicitConsentRequest() {
        let probe = ProbeStub(result: .available)
        let result = NotesPermissionService(probe: probe).check(requestConsent: true)

        XCTAssertEqual(result.access, .available)
        XCTAssertTrue(result.requested)
        XCTAssertTrue(result.readable)
        XCTAssertTrue(result.complete)
        XCTAssertTrue(probe.requestedConsent)
    }

    func testResourceMapperPreservesAutomationStates() {
        let available = NotesResourceMapper.map(status: .available)
        XCTAssertEqual(available.id, "notes_library_default")
        XCTAssertEqual(available.kind, .notesLibrary)
        XCTAssertEqual(available.provider, .notes)
        XCTAssertTrue(available.capabilities.readable)
        XCTAssertFalse(available.capabilities.writable)
        XCTAssertTrue(available.capabilities.selected)
        XCTAssertEqual(available.capabilities.permission, .available)

        XCTAssertEqual(
            NotesResourceMapper.map(status: .requiresConsent).capabilities.permission,
            .requiresConsent
        )
        XCTAssertEqual(
            NotesResourceMapper.map(status: .denied).capabilities.permission,
            .denied
        )
        XCTAssertEqual(
            NotesResourceMapper.map(status: .targetNotRunning).capabilities.permission,
            .unavailable
        )
        XCTAssertTrue(NotesResourceMapper.map(status: .available, writable: true).capabilities.writable)
        XCTAssertFalse(NotesResourceMapper.map(status: .denied, writable: true).capabilities.writable)
    }

    func testPermissionErrorsHaveStableCodes() {
        XCTAssertEqual(NotesError.permissionRequired.machineCode, "NOTES_PERMISSION_REQUIRED")
        XCTAssertEqual(NotesError.permissionDenied.machineCode, "NOTES_PERMISSION_DENIED")
        XCTAssertEqual(NotesError.targetUnavailable.machineCode, "NOTES_TARGET_UNAVAILABLE")
        XCTAssertEqual(NotesError.automationUnknown.machineCode, "NOTES_AUTOMATION_UNKNOWN")
        XCTAssertEqual(NotesError.folderMoveUnsupported.machineCode, "NOTES_FOLDER_MOVE_UNSUPPORTED")
        XCTAssertEqual(NotesError.folderNotEmpty.machineCode, "NOTES_FOLDER_NOT_EMPTY")
        XCTAssertEqual(NotesError.folderDeleteUnsupported.machineCode, "NOTES_FOLDER_DELETE_UNSUPPORTED")
    }

    func testOpaqueIDsDoNotExposeScriptingIdentifiers() {
        let account = NotesOpaqueID.account(scriptingID: "private-account-id")
        let folder = NotesOpaqueID.folder(accountScriptingID: "private-account-id", scriptingID: "private-folder-id")

        XCTAssertTrue(account.hasPrefix("notesaccount_"))
        XCTAssertTrue(folder.hasPrefix("notesfolder_"))
        XCTAssertFalse(account.contains("private-account-id"))
        XCTAssertFalse(folder.contains("private-folder-id"))
        XCTAssertNotEqual(account, folder)
        XCTAssertTrue(NotesOpaqueID.isNote(NotesOpaqueID.note(accountScriptingID: "a", scriptingID: "n")))
        XCTAssertFalse(NotesOpaqueID.isNote("note_short"))
    }

    func testAccountAndFolderMappingPreservesDefaultAndHierarchy() throws {
        let service = NotesPermissionService(probe: ProbeStub(result: .available))
        let store = NotesStore(permission: service, bridge: BridgeStub(snapshotValue: snapshot()))

        let accounts = try store.accounts()
        XCTAssertEqual(accounts.accounts.count, 2)
        XCTAssertTrue(accounts.accounts.first { $0.name == "iCloud" }?.isDefault == true)
        XCTAssertEqual(accounts.accounts.first { $0.name == "iCloud" }?.folderCount, 2)

        let folders = try store.folders(limit: 20, cursor: nil, accountID: nil, parentID: nil)
        XCTAssertEqual(folders.items.count, 3)
        let root = try XCTUnwrap(folders.items.first { $0.name == "Work" })
        let child = try XCTUnwrap(folders.items.first { $0.name == "Projects" })
        XCTAssertEqual(child.parentID, root.id)
        XCTAssertEqual(child.depth, 1)
        XCTAssertTrue(child.shared)
    }

    func testFolderFiltersAndCursorAreBoundToScope() throws {
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot())
        )
        let accounts = try store.accounts().accounts
        let iCloudID = try XCTUnwrap(accounts.first { $0.name == "iCloud" }?.id)
        let first = try store.folders(limit: 1, cursor: nil, accountID: iCloudID, parentID: nil)
        XCTAssertTrue(first.truncated)
        XCTAssertNotNil(first.nextCursor)

        XCTAssertThrowsError(
            try store.folders(limit: 1, cursor: first.nextCursor, accountID: nil, parentID: nil)
        ) { error in
            XCTAssertEqual(error as? PaginationError, .invalidCursor)
        }
    }

    func testDiscoveryFailsClosedWithoutPermission() {
        for (status, expected) in [
            (NotesAutomationStatus.requiresConsent, NotesError.permissionRequired),
            (.denied, .permissionDenied),
            (.targetNotRunning, .targetNotRunning),
            (.targetUnavailable, .targetUnavailable),
            (.unknown, .automationUnknown)
        ] {
            let store = NotesStore(
                permission: NotesPermissionService(probe: ProbeStub(result: status)),
                bridge: BridgeStub(snapshotValue: snapshot())
            )
            XCTAssertThrowsError(try store.accounts()) { error in
                XCTAssertEqual(error as? NotesError, expected)
            }
        }
    }

    func testDiscoveryScriptIsBoundedAndDoesNotReadNotesOrBodies() {
        let script = SystemNotesMetadataBridge.snapshotScript(
            maximumAccounts: 3,
            maximumFolders: 7,
            maximumDepth: 4,
            timeoutSeconds: 5
        )
        XCTAssertTrue(script.contains("accountCounter is greater than or equal to 3"))
        XCTAssertTrue(script.contains("id of default folder of accountItem"))
        XCTAssertTrue(script.contains("folderCounter is greater than or equal to maximumFolders"))
        XCTAssertTrue(script.contains("folderCounter, 7, 4"))
        XCTAssertTrue(script.contains("folderDepth is greater than or equal to 4"))
        XCTAssertTrue(script.contains("set rootFolders to {}"))
        XCTAssertTrue(script.contains("id of container of candidateFolder"))
        XCTAssertFalse(script.contains("every note"))
        XCTAssertFalse(script.contains("body of"))
        XCTAssertFalse(script.contains("plaintext"))
    }

    func testDiscoveryFailsClosedInsteadOfCrashingOnDuplicateFolderIdentifiers() {
        let original = snapshot()
        let duplicate = NotesMetadataSnapshot(
            accounts: original.accounts,
            folders: original.folders + [original.folders[0]],
            defaultAccountScriptingID: original.defaultAccountScriptingID,
            complete: original.complete
        )
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: duplicate)
        )

        XCTAssertThrowsError(try store.folders(limit: 20, cursor: nil, accountID: nil, parentID: nil)) {
            XCTAssertEqual($0 as? NotesError, .executionFailed)
        }
    }

    func testMetadataQueryFiltersAndNeverReturnsBody() throws {
        let accounts = try queryStore().accounts().accounts
        let iCloudID = try XCTUnwrap(accounts.first { $0.name == "iCloud" }?.id)
        let result = try queryStore().query(NotesQuery(
            accountID: iCloudID,
            title: "project",
            modifiedAfter: Date(timeIntervalSince1970: 250),
            limit: 20
        ))

        XCTAssertEqual(result.items.count, 1)
        let note = try XCTUnwrap(result.items.first)
        XCTAssertEqual(note.title, "Project Alpha")
        XCTAssertEqual(note.modificationDate, Date(timeIntervalSince1970: 300))
        XCTAssertTrue(note.shared)
        XCTAssertFalse(note.passwordProtected)
        let encoded = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("body"))
        XCTAssertFalse(json.contains("plaintext"))
    }

    func testNoteQueryCursorIsBoundToFilters() throws {
        let first = try queryStore().query(NotesQuery(title: "project", limit: 1))
        XCTAssertTrue(first.truncated)
        XCTAssertNotNil(first.nextCursor)
        XCTAssertThrowsError(try queryStore().query(NotesQuery(title: "personal", limit: 1, cursor: first.nextCursor))) { error in
            XCTAssertEqual(error as? PaginationError, .invalidCursor)
        }
    }

    func testNoteQueryValidatesLimitAndTitle() {
        XCTAssertThrowsError(try queryStore().query(NotesQuery(title: "", limit: 10))) { error in
            XCTAssertEqual(error as? NotesError, .invalidQuery)
        }
        XCTAssertThrowsError(try queryStore().query(NotesQuery(limit: 0))) { error in
            XCTAssertEqual(error as? NotesError, .invalidLimit)
        }
    }

    func testQueryScriptIsBoundedAndMetadataOnly() {
        let script = SystemNotesQueryBridge.snapshotScript(maximumNotes: 9, timeoutSeconds: 5)
        XCTAssertTrue(script.contains("noteCounter is greater than or equal to maximumNotes"))
        XCTAssertTrue(script.contains("noteCounter, 9, 16"))
        XCTAssertTrue(script.contains("notes of folderItem"))
        XCTAssertFalse(script.contains("notes of accountItem"))
        XCTAssertTrue(script.contains("modification date of noteItem"))
        XCTAssertTrue(script.contains("password protected of noteItem"))
        XCTAssertFalse(script.contains("body of noteItem"))
        XCTAssertFalse(script.contains("plaintext of noteItem"))
        XCTAssertFalse(script.contains("attachments of noteItem"))
    }

    func testGetDefaultsToMetadataWithoutReadingBody() throws {
        let body = BodyBridgeStub(value: "must not be read")
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: querySnapshot()),
            bodyBridge: body
        )
        let id = try XCTUnwrap(try store.query(NotesQuery(title: "Alpha")).items.first?.id)

        let result = try store.get(id: id, bodyFormat: .none)

        XCTAssertNil(result.body)
        XCTAssertNil(result.bodyBytes)
        XCTAssertEqual(body.calls, 0)
    }

    func testGetReadsExplicitPlaintextAndEnforcesByteLimit() throws {
        let body = BodyBridgeStub(value: "hello")
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: querySnapshot()),
            bodyBridge: body
        )
        let id = try XCTUnwrap(try store.query(NotesQuery(title: "Alpha")).items.first?.id)

        let result = try store.get(id: id, bodyFormat: .plaintext)

        XCTAssertEqual(result.body, "hello")
        XCTAssertEqual(result.bodyBytes, 5)
        XCTAssertEqual(body.calls, 1)
    }

    func testGetRejectsLockedOrOversizedBody() throws {
        let lockedStore = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: querySnapshot()),
            bodyBridge: BodyBridgeStub(value: "secret")
        )
        let lockedID = try XCTUnwrap(try lockedStore.query(NotesQuery(title: "Archive")).items.first?.id)
        XCTAssertThrowsError(try lockedStore.get(id: lockedID, bodyFormat: .html)) { error in
            XCTAssertEqual(error as? NotesError, .lockedNote)
        }

        let oversized = BodyBridgeStub(value: String(repeating: "x", count: NotesBodyPolicy.maximumBytes + 1))
        let oversizedStore = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: querySnapshot()),
            bodyBridge: oversized
        )
        let id = try XCTUnwrap(try oversizedStore.query(NotesQuery(title: "Alpha")).items.first?.id)
        XCTAssertThrowsError(try oversizedStore.get(id: id, bodyFormat: .plaintext)) { error in
            XCTAssertEqual(error as? NotesError, .bodyTooLarge)
        }
    }

    func testBodyScriptReadsOnlyExplicitProjection() {
        let plaintext = SystemNotesBodyBridge.readScript(scriptingID: "opaque\"id", format: .plaintext, timeoutSeconds: 5)
        XCTAssertTrue(plaintext.contains("plaintext of noteItem"))
        XCTAssertFalse(plaintext.contains("body of noteItem"))
        XCTAssertTrue(plaintext.contains("opaque\\\"id"))

        let html = SystemNotesBodyBridge.readScript(scriptingID: "note-id", format: .html, timeoutSeconds: 5)
        XCTAssertTrue(html.contains("body of noteItem"))
        XCTAssertFalse(html.contains("plaintext of noteItem"))
    }

    func testGetIncludesAttachmentMetadataOnlyWhenExplicitlyRequested() throws {
        let attachments = AttachmentBridgeStub(snapshotValue: NotesAttachmentSnapshot(
            attachments: [NotesAttachmentDescriptor(
                scriptingID: "attachment-private-id",
                name: "report.pdf",
                creationDate: Date(timeIntervalSince1970: 100),
                modificationDate: Date(timeIntervalSince1970: 200),
                contentIdentifier: "cid:one",
                url: nil,
                shared: false
            )],
            complete: true
        ))
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: querySnapshot()),
            bodyBridge: BodyBridgeStub(value: ""),
            attachmentBridge: attachments
        )
        let id = try XCTUnwrap(try store.query(NotesQuery(title: "Alpha")).items.first?.id)

        let omitted = try store.get(id: id, bodyFormat: .none, includeAttachments: false)
        XCTAssertFalse(omitted.attachmentsIncluded)
        XCTAssertNil(omitted.attachments)

        let included = try store.get(id: id, bodyFormat: .none, includeAttachments: true)
        XCTAssertTrue(included.attachmentsIncluded)
        XCTAssertEqual(included.attachments?.first?.name, "report.pdf")
        XCTAssertTrue(included.attachments?.first?.id.hasPrefix("noteattachment_") == true)
        XCTAssertFalse(included.attachments?.first?.id.contains("attachment-private-id") == true)
        XCTAssertTrue(included.attachmentsComplete == true)
    }

    func testAttachmentScriptIsBoundedAndMetadataOnly() {
        let script = SystemNotesAttachmentBridge.snapshotScript(
            scriptingID: "note-id",
            maximumAttachments: 7,
            timeoutSeconds: 5
        )
        XCTAssertTrue(script.contains("attachmentCounter is greater than or equal to 7"))
        XCTAssertTrue(script.contains("content identifier of attachmentItem"))
        XCTAssertTrue(script.contains("URL of attachmentItem"))
        XCTAssertFalse(script.contains("contents of attachmentItem"))
        XCTAssertFalse(script.contains("save attachmentItem"))
    }

    func testCreateInputIsStrictAndComposesPrivateHTML() throws {
        let decoder = JSONDecoder()
        let input = try decoder.decode(NotesCreateInput.self, from: Data(#"{"folderID":"notesfolder_abc","title":"A&B","bodyFormat":"plaintext","body":"one\ntwo"}"#.utf8))
        let prepared = try NotesWritePolicy.prepare(input)

        XCTAssertEqual(prepared.html, "<div>A&amp;B</div><div>one<br>two</div>")
        XCTAssertEqual(prepared.bodyBytes, input.body.lengthOfBytes(using: .utf8))
        XCTAssertFalse(prepared.titleSHA256.contains("A&B"))
        XCTAssertThrowsError(try decoder.decode(NotesCreateInput.self, from: Data(#"{"folderID":"x","title":"x","bodyFormat":"plaintext","body":"","unknown":true}"#.utf8)))
    }

    func testWritePolicyRejectsInvalidTitleAndOversizedBody() {
        XCTAssertThrowsError(try NotesWritePolicy.prepare(NotesCreateInput(folderID: "folder", title: "", bodyFormat: .plaintext, body: "")))
        XCTAssertThrowsError(try NotesWritePolicy.prepare(NotesCreateInput(folderID: "folder", title: "ok", bodyFormat: .plaintext, body: String(repeating: "x", count: NotesBodyPolicy.maximumBytes + 1))))
    }

    func testDeleteInputIsStrict() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let input = try decoder.decode(
            NotesDeleteInput.self,
            from: Data(#"{"expectedModificationDate":"1970-01-01T00:05:00Z"}"#.utf8)
        )
        XCTAssertEqual(input.expectedModificationDate, Date(timeIntervalSince1970: 300))
        XCTAssertThrowsError(try decoder.decode(
            NotesDeleteInput.self,
            from: Data(#"{"expectedModificationDate":"1970-01-01T00:05:00Z","unknown":true}"#.utf8)
        ))
    }

    func testEditBodyInputIsStrictAndPreparesTitlePreservingHTML() throws {
        let currentHash = NotesWritePolicy.sha256("Title\nOld body\n")
        let json = #"{"bodyFormat":"plaintext","body":"New & safe","expectedModificationDate":"1970-01-01T00:05:00Z","expectedBodySHA256":"\#(currentHash)"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let input = try decoder.decode(NotesEditBodyInput.self, from: Data(json.utf8))
        let prepared = try NotesWritePolicy.prepareBodyEdit(input, title: "Title")

        XCTAssertEqual(prepared.html, "<div>Title</div><div>New &amp; safe</div>")
        XCTAssertEqual(prepared.expectedPlaintext, "Title\nNew & safe\n")
        XCTAssertEqual(prepared.bodyBytes, 10)
        XCTAssertThrowsError(try decoder.decode(NotesEditBodyInput.self, from: Data(#"{"bodyFormat":"plaintext","body":"x","expectedModificationDate":"1970-01-01T00:05:00Z","expectedBodySHA256":"bad","unknown":true}"#.utf8)))
    }

    func testEditBodyPolicyRejectsInvalidHashAndComplexExistingHTML() throws {
        let input = NotesEditBodyInput(
            bodyFormat: .plaintext,
            body: "New",
            expectedModificationDate: Date(timeIntervalSince1970: 300),
            expectedBodySHA256: "bad"
        )

        XCTAssertThrowsError(try NotesWritePolicy.prepareBodyEdit(input, title: "Title"))
        XCTAssertTrue(NotesWritePolicy.isSafeReplaceableHTML("<div>Title</div><div><b>Body</b><br></div>"))
        XCTAssertFalse(NotesWritePolicy.isSafeReplaceableHTML("Title\nBody"))
        XCTAssertFalse(NotesWritePolicy.isSafeReplaceableHTML("<div>Title</div><table><tr><td>Data</td></tr></table>"))
        XCTAssertFalse(NotesWritePolicy.isSafeReplaceableHTML("<div>Title</div><img src=\"attachment://private\">"))
    }

    func testFolderWriteInputsAreStrictAndRequireExplicitParents() throws {
        let decoder = JSONDecoder()
        let create = try decoder.decode(
            NotesFolderCreateInput.self,
            from: Data(#"{"name":"Projects","parentFolderID":null}"#.utf8)
        )
        XCTAssertEqual(create.name, "Projects")
        XCTAssertNil(create.parentFolderID)

        let rename = try decoder.decode(
            NotesFolderRenameInput.self,
            from: Data(#"{"name":"Archive","expectedNameSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8)
        )
        XCTAssertEqual(rename.name, "Archive")

        let move = try decoder.decode(
            NotesFolderMoveInput.self,
            from: Data(#"{"destinationParentFolderID":null,"expectedParentFolderID":"notesfolder_parent","expectedNameSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}"#.utf8)
        )
        XCTAssertNil(move.destinationParentFolderID)
        XCTAssertEqual(move.expectedParentFolderID, "notesfolder_parent")

        let delete = try decoder.decode(
            NotesFolderDeleteInput.self,
            from: Data(#"{"expectedParentFolderID":null,"expectedNameSHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}"#.utf8)
        )
        XCTAssertNil(delete.expectedParentFolderID)

        XCTAssertThrowsError(try decoder.decode(NotesFolderCreateInput.self, from: Data(#"{"name":"Projects"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(NotesFolderCreateInput.self, from: Data(#"{"name":"Projects","parentFolderID":null,"unknown":true}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(NotesFolderMoveInput.self, from: Data(#"{"destinationParentFolderID":null,"expectedNameSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(NotesFolderDeleteInput.self, from: Data(#"{"expectedNameSHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(NotesFolderDeleteInput.self, from: Data(#"{"expectedParentFolderID":null,"expectedNameSHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","unknown":true}"#.utf8)))
    }

    func testFolderWritePolicyRejectsUnsafeNamesAndCycles() throws {
        XCTAssertNoThrow(try NotesWritePolicy.validateFolderName("Projects 2026"))
        for name in ["", " leading", "trailing ", "line\nbreak", String(repeating: "x", count: 201)] {
            XCTAssertThrowsError(try NotesWritePolicy.validateFolderName(name))
        }
        XCTAssertTrue(NotesWritePolicy.isFolderDescendant(
            candidateScriptingID: "child",
            of: "root",
            folders: [
                NotesFolderDescriptor(scriptingID: "root", accountScriptingID: "account", parentScriptingID: nil, name: "Root", shared: false, depth: 0),
                NotesFolderDescriptor(scriptingID: "child", accountScriptingID: "account", parentScriptingID: "root", name: "Child", shared: false, depth: 1)
            ]
        ))
        XCTAssertFalse(NotesWritePolicy.isFolderDescendant(candidateScriptingID: "root", of: "child", folders: []))
    }

    func testFolderMutationScriptsStayBoundedAndCompile() throws {
        let create = SystemNotesFolderMutationBridge.createScript(accountScriptingID: "a", parentFolderScriptingID: "p", name: "A&B", timeoutSeconds: 5)
        let createRoot = SystemNotesFolderMutationBridge.createScript(accountScriptingID: "a", parentFolderScriptingID: nil, name: "Root", timeoutSeconds: 5)
        let rename = SystemNotesFolderMutationBridge.renameScript(folderScriptingID: "f", name: "Renamed", timeoutSeconds: 5)
        let move = SystemNotesFolderMutationBridge.moveScript(folderScriptingID: "f", accountScriptingID: "a", destinationParentFolderScriptingID: nil, timeoutSeconds: 5)
        XCTAssertTrue(create.contains("make new folder at parentFolderItem"))
        XCTAssertTrue(createRoot.contains("make new folder at accountItem"))
        XCTAssertTrue(rename.contains("set name of folderItem"))
        XCTAssertTrue(move.contains("move folderItem to accountItem"))
        for source in [create, createRoot, rename, move, SystemNotesFolderMutationBridge.readScript(folderScriptingID: "f", timeoutSeconds: 5)] {
            var error: NSDictionary?
            XCTAssertNotNil(NSAppleScript(source: source)?.compileAndReturnError(&error), "\(error ?? [:])")
        }
    }

    func testFolderCreateDryRunApplyAndPrivateIdempotencyReceipt() throws {
        let created = NotesFolderMutationDescriptor(
            scriptingID: "folder-created", accountScriptingID: "account-icloud",
            parentScriptingID: "folder-root", name: "Projects", shared: false
        )
        let mutation = FolderMutationBridgeStub(value: created)
        mutation.readValues = [created]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory.appendingPathComponent("config"))
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let receiptStore = NotesFolderIdempotencyStore(directory: directory.appendingPathComponent("receipts"), now: { Date(timeIntervalSince1970: 10) })
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: folderMutationSnapshot()),
            folderMutationBridge: mutation, writeAccountStore: accountStore,
            folderIdempotencyStore: receiptStore
        )
        let parentID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")
        let input = NotesFolderCreateInput(name: "Projects", parentFolderID: parentID)

        let preview = try store.previewCreateFolder(input)
        XCTAssertTrue(preview.dryRun)
        XCTAssertEqual(preview.nameSHA256, NotesWritePolicy.sha256("Projects"))
        XCTAssertNil(preview.name)
        XCTAssertEqual(mutation.createCalls, 0)

        let result = try store.createFolder(input, idempotent: true)
        XCTAssertEqual(result.verification, .readbackConfirmed)
        XCTAssertEqual(result.parentFolderID, parentID)
        XCTAssertEqual(mutation.createCalls, 1)
        XCTAssertEqual(try receiptStore.receipt(for: input)?.state, .saved)
        let receiptFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("receipts"), includingPropertiesForKeys: nil).first)
        XCTAssertFalse(try String(contentsOf: receiptFile, encoding: .utf8).contains("Projects"))

        let duplicate = try store.createFolder(input, idempotent: true)
        XCTAssertEqual(duplicate.verification, .idempotencyReceiptPending)
        XCTAssertTrue(duplicate.deduplicated)
        XCTAssertEqual(mutation.createCalls, 1)

        let encoder = JSONEncoder()
        let previewJSON = String(decoding: try encoder.encode(preview), as: UTF8.self)
        let resultJSON = String(decoding: try encoder.encode(result), as: UTF8.self)
        XCTAssertFalse(previewJSON.contains("Projects"))
        XCTAssertFalse(resultJSON.contains("Projects"))
    }

    func testFolderRenameAndMoveUseHashParentGuardsAndAvoidNoOps() throws {
        let currentChild = NotesFolderMutationDescriptor(
            scriptingID: "folder-child", accountScriptingID: "account-icloud",
            parentScriptingID: "folder-root", name: "Child", shared: false
        )
        let movedChild = NotesFolderMutationDescriptor(
            scriptingID: "folder-child", accountScriptingID: "account-icloud",
            parentScriptingID: "folder-destination", name: "Child", shared: false
        )
        let mutation = FolderMutationBridgeStub(value: movedChild)
        mutation.readValues = [currentChild, movedChild]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory.appendingPathComponent("config"))
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: folderMutationSnapshot()),
            folderMutationBridge: mutation, writeAccountStore: accountStore,
            folderIdempotencyStore: NotesFolderIdempotencyStore(directory: directory.appendingPathComponent("receipts"))
        )
        let childID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-child")
        let rootID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")
        let destinationID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-destination")
        let childHash = NotesWritePolicy.sha256("Child")

        let noOp = try store.renameFolder(id: childID, input: NotesFolderRenameInput(name: "Child", expectedNameSHA256: childHash))
        XCTAssertFalse(noOp.changed)
        XCTAssertEqual(mutation.renameCalls, 0)

        let moveInput = NotesFolderMoveInput(destinationParentFolderID: destinationID, expectedParentFolderID: rootID, expectedNameSHA256: childHash)
        XCTAssertTrue(try store.previewMoveFolder(id: childID, input: moveInput).changed)
        XCTAssertThrowsError(try store.moveFolder(id: childID, input: moveInput)) {
            XCTAssertEqual($0 as? NotesError, .folderMoveUnsupported)
        }
        XCTAssertEqual(mutation.moveCalls, 0)

        XCTAssertThrowsError(try store.previewMoveFolder(id: childID, input: NotesFolderMoveInput(destinationParentFolderID: destinationID, expectedParentFolderID: nil, expectedNameSHA256: childHash))) { error in
            XCTAssertEqual(error as? NotesError, .folderConcurrencyConflict)
        }
    }

    func testFolderMutationRevalidatesImmediatelyAndTimeoutDoesNotInviteRetry() throws {
        let current = NotesFolderMutationDescriptor(
            scriptingID: "folder-child", accountScriptingID: "account-icloud",
            parentScriptingID: "folder-root", name: "Child", shared: false
        )
        let stale = NotesFolderMutationDescriptor(
            scriptingID: "folder-child", accountScriptingID: "account-icloud",
            parentScriptingID: "folder-root", name: "Changed Elsewhere", shared: false
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory.appendingPathComponent("config"))
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let childID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-child")
        let childHash = NotesWritePolicy.sha256("Child")

        let staleBridge = FolderMutationBridgeStub(value: current)
        staleBridge.readValues = [stale]
        let staleStore = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: folderMutationSnapshot()),
            folderMutationBridge: staleBridge, writeAccountStore: accountStore,
            folderIdempotencyStore: NotesFolderIdempotencyStore(directory: directory.appendingPathComponent("stale-receipts"))
        )
        XCTAssertThrowsError(try staleStore.renameFolder(id: childID, input: NotesFolderRenameInput(name: "Renamed", expectedNameSHA256: childHash))) {
            XCTAssertEqual($0 as? NotesError, .folderConcurrencyConflict)
        }
        XCTAssertEqual(staleBridge.renameCalls, 0)

        let timeoutBridge = FolderMutationBridgeStub(value: current)
        timeoutBridge.createError = NotesMetadataBridgeError.timedOut
        let timeoutStore = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: folderMutationSnapshot()),
            folderMutationBridge: timeoutBridge, writeAccountStore: accountStore,
            folderIdempotencyStore: NotesFolderIdempotencyStore(directory: directory.appendingPathComponent("timeout-receipts"))
        )
        let rootID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")
        let result = try timeoutStore.createFolder(NotesFolderCreateInput(name: "Private Name", parentFolderID: rootID), idempotent: false)
        XCTAssertEqual(result.verification, .outcomeUnknown)
        XCTAssertTrue(result.nextAction?.contains("Do not retry automatically") == true)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("Private Name"))
    }

    func testEmptyFolderDeletePreviewWorksAndApplyFailsClosed() throws {
        let current = NotesFolderMutationDescriptor(
            scriptingID: "folder-child", accountScriptingID: "account-icloud",
            parentScriptingID: "folder-root", name: "Child", shared: false,
            directNoteCount: 0, directChildFolderCount: 0
        )
        let mutation = FolderMutationBridgeStub(value: current)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory.appendingPathComponent("config"))
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        func makeStore(_ bridge: FolderMutationBridgeStub) -> NotesStore {
            NotesStore(
                permission: NotesPermissionService(probe: ProbeStub(result: .available)),
                bridge: BridgeStub(snapshotValue: folderMutationSnapshot()),
                folderMutationBridge: bridge, writeAccountStore: accountStore,
                folderIdempotencyStore: NotesFolderIdempotencyStore(directory: directory.appendingPathComponent(UUID().uuidString))
            )
        }
        let store = makeStore(mutation)
        let childID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-child")
        let rootID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")
        let input = NotesFolderDeleteInput(expectedParentFolderID: rootID, expectedNameSHA256: NotesWritePolicy.sha256("Child"))

        let preview = try store.previewDeleteFolder(id: childID, input: input)
        XCTAssertTrue(preview.dryRun)
        XCTAssertThrowsError(try store.deleteFolder(id: childID, input: input)) {
            XCTAssertEqual($0 as? NotesError, .folderDeleteUnsupported)
        }
    }

    func testEmptyFolderDeleteRejectsNotesChildrenAndStaleParent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory.appendingPathComponent("config"))
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let childID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-child")
        let rootID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")
        let input = NotesFolderDeleteInput(expectedParentFolderID: rootID, expectedNameSHA256: NotesWritePolicy.sha256("Child"))
        func store(_ descriptor: NotesFolderMutationDescriptor, snapshot: NotesMetadataSnapshot = folderMutationSnapshot()) -> (NotesStore, FolderMutationBridgeStub) {
            let mutation = FolderMutationBridgeStub(value: descriptor)
            return (NotesStore(
                permission: NotesPermissionService(probe: ProbeStub(result: .available)),
                bridge: BridgeStub(snapshotValue: snapshot), folderMutationBridge: mutation,
                writeAccountStore: accountStore,
                folderIdempotencyStore: NotesFolderIdempotencyStore(directory: directory.appendingPathComponent(UUID().uuidString))
            ), mutation)
        }
        let withNote = store(NotesFolderMutationDescriptor(scriptingID: "folder-child", accountScriptingID: "account-icloud", parentScriptingID: "folder-root", name: "Child", shared: false, directNoteCount: 1))
        XCTAssertThrowsError(try withNote.0.previewDeleteFolder(id: childID, input: input)) { XCTAssertEqual($0 as? NotesError, .folderNotEmpty) }

        var folders = folderMutationSnapshot().folders
        folders.append(NotesFolderDescriptor(scriptingID: "grandchild", accountScriptingID: "account-icloud", parentScriptingID: "folder-child", name: "Grandchild", shared: false, depth: 2))
        let withChild = store(NotesFolderMutationDescriptor(scriptingID: "folder-child", accountScriptingID: "account-icloud", parentScriptingID: "folder-root", name: "Child", shared: false), snapshot: NotesMetadataSnapshot(accounts: folderMutationSnapshot().accounts, folders: folders, defaultAccountScriptingID: "account-icloud", complete: true))
        XCTAssertThrowsError(try withChild.0.previewDeleteFolder(id: childID, input: input)) { XCTAssertEqual($0 as? NotesError, .folderNotEmpty) }

        let stale = NotesFolderDeleteInput(expectedParentFolderID: nil, expectedNameSHA256: NotesWritePolicy.sha256("Child"))
        XCTAssertThrowsError(try withNote.0.previewDeleteFolder(id: childID, input: stale)) { XCTAssertEqual($0 as? NotesError, .folderConcurrencyConflict) }
    }

    func testFolderMutationRejectsDefaultSharedDuplicateCycleAndIncompleteGraph() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory.appendingPathComponent("config"))
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        func makeStore(_ snapshot: NotesMetadataSnapshot) -> NotesStore {
            NotesStore(
                permission: NotesPermissionService(probe: ProbeStub(result: .available)),
                bridge: BridgeStub(snapshotValue: snapshot), writeAccountStore: accountStore,
                folderIdempotencyStore: NotesFolderIdempotencyStore(directory: directory.appendingPathComponent(UUID().uuidString))
            )
        }
        let snapshot = folderMutationSnapshot()
        let store = makeStore(snapshot)
        let defaultID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-default")
        let sharedID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-shared")
        let rootID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")
        let childID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-child")
        let localID = NotesOpaqueID.folder(accountScriptingID: "account-local", scriptingID: "folder-local-default")

        XCTAssertThrowsError(try store.previewRenameFolder(id: defaultID, input: NotesFolderRenameInput(name: "New", expectedNameSHA256: NotesWritePolicy.sha256("Notes")))) { XCTAssertEqual($0 as? NotesError, .defaultFolderTarget) }
        XCTAssertThrowsError(try store.previewCreateFolder(NotesFolderCreateInput(name: "New", parentFolderID: sharedID))) { XCTAssertEqual($0 as? NotesError, .sharedTarget) }
        XCTAssertThrowsError(try store.previewCreateFolder(NotesFolderCreateInput(name: "rÓÓt", parentFolderID: nil))) { XCTAssertEqual($0 as? NotesError, .duplicateFolderName) }
        XCTAssertThrowsError(try store.previewMoveFolder(id: rootID, input: NotesFolderMoveInput(destinationParentFolderID: childID, expectedParentFolderID: nil, expectedNameSHA256: NotesWritePolicy.sha256("Root")))) { XCTAssertEqual($0 as? NotesError, .folderCycle) }
        XCTAssertThrowsError(try store.previewMoveFolder(id: childID, input: NotesFolderMoveInput(destinationParentFolderID: localID, expectedParentFolderID: rootID, expectedNameSHA256: NotesWritePolicy.sha256("Child")))) { XCTAssertEqual($0 as? NotesError, .writeAccountMismatch) }
        XCTAssertThrowsError(try makeStore(folderMutationSnapshot(complete: false)).previewCreateFolder(NotesFolderCreateInput(name: "New", parentFolderID: nil))) { XCTAssertEqual($0 as? NotesError, .incompleteFolderGraph) }
    }

    func testOptimisticConcurrencyUsesWholeSecondPrecision() throws {
        let expected = Date(timeIntervalSince1970: 100.9)
        XCTAssertTrue(NotesWritePolicy.modificationDatesMatch(expected, Date(timeIntervalSince1970: 100.1)))
        XCTAssertFalse(NotesWritePolicy.modificationDatesMatch(expected, Date(timeIntervalSince1970: 101.0)))
    }

    func testWriteAccountConfigurationUsesPrivatePermissionsAndNoRawAccountData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotesWriteAccountStore(directory: directory)
        let binding = NotesWriteAccountBinding(accountID: "notesaccount_opaque", boundAt: Date(timeIntervalSince1970: 1))

        try store.save(binding)

        XCTAssertEqual(try store.load(), binding)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let data = try Data(contentsOf: store.fileURL)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-account"))
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testIdempotencyReceiptTracksInFlightWithoutPrivateContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotesIdempotencyStore(directory: directory, now: { Date(timeIntervalSince1970: 10) })
        let input = NotesCreateInput(folderID: "folder", title: "secret-title", bodyFormat: .plaintext, body: "secret-body")

        try store.begin(input)
        XCTAssertEqual(try store.receipt(for: input)?.state, .inFlight)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let text = try String(contentsOf: XCTUnwrap(files.first), encoding: .utf8)
        XCTAssertFalse(text.contains("secret-title"))
        XCTAssertFalse(text.contains("secret-body"))
    }

    func testMutationScriptsEscapeValuesAndStayBounded() {
        let create = SystemNotesMutationBridge.createScript(accountScriptingID: "a\"", folderScriptingID: "f\"", html: "<div>\"x\"</div>", timeoutSeconds: 5)
        XCTAssertTrue(create.contains("with timeout of 5 seconds"))
        XCTAssertTrue(create.contains("make new note"))
        XCTAssertTrue(create.contains("a\\\""))
        XCTAssertTrue(create.contains("f\\\""))
        XCTAssertTrue(create.contains("\\\"x\\\""))

        let rename = SystemNotesMutationBridge.renameScript(noteScriptingID: "n", title: "new", timeoutSeconds: 5)
        XCTAssertTrue(rename.contains("set name of noteItem to"))
        let move = SystemNotesMutationBridge.moveScript(noteScriptingID: "n", destinationFolderScriptingID: "f", timeoutSeconds: 5)
        XCTAssertTrue(move.contains("move noteItem to folderItem"))
        let replaceBody = SystemNotesMutationBridge.replaceBodyScript(noteScriptingID: "n", html: "<div>new</div>", timeoutSeconds: 5)
        XCTAssertTrue(replaceBody.contains("set body of noteItem to"))
        let delete = SystemNotesMutationBridge.deleteScript(noteScriptingID: "n", timeoutSeconds: 5)
        XCTAssertTrue(delete.contains("delete noteItem"))

        for source in [create, rename, move, replaceBody, delete, SystemNotesMutationBridge.readScript(noteScriptingID: "n", timeoutSeconds: 5)] {
            let script = NSAppleScript(source: source)
            var error: NSDictionary?
            XCTAssertTrue(script?.compileAndReturnError(&error) == true, "compile error: \(String(describing: error))")
        }
    }

    func testDryRunCreateNeverCallsMutationBridge() throws {
        let mutation = MutationBridgeStub(value: NotesMutationDescriptor(
            scriptingID: "note", accountScriptingID: "account-icloud", folderScriptingID: "folder-root",
            title: "Created", html: "<div>Created</div>", modificationDate: Date(), passwordProtected: false, shared: false
        ))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()), queryBridge: QueryBridgeStub(snapshotValue: querySnapshot()),
            mutationBridge: mutation, writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency"))
        )
        let folderID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")

        let preview = try store.previewCreate(NotesCreateInput(folderID: folderID, title: "Created", bodyFormat: .plaintext, body: "Body"))

        XCTAssertTrue(preview.dryRun)
        XCTAssertEqual(mutation.createCalls, 0)
        XCTAssertNil(preview.title)
        XCTAssertNil(preview.body)
    }

    func testRenameAndMoveRequireConcurrencyAndAvoidNoOpAppleEvents() throws {
        let date = Date(timeIntervalSince1970: 300)
        let note = NotesNoteDescriptor(scriptingID: "note-safe", accountScriptingID: "account-icloud", folderScriptingID: "folder-root", title: "Same", creationDate: nil, modificationDate: date, passwordProtected: false, shared: false)
        let mutation = MutationBridgeStub(value: NotesMutationDescriptor(scriptingID: "note-safe", accountScriptingID: "account-icloud", folderScriptingID: "folder-root", title: "Same", html: "", modificationDate: date, passwordProtected: false, shared: false))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(permission: NotesPermissionService(probe: ProbeStub(result: .available)), bridge: BridgeStub(snapshotValue: snapshot()), queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [note], complete: true)), mutationBridge: mutation, writeAccountStore: accountStore, idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency")))
        let noteID = NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe")
        let folderID = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-root")

        XCTAssertFalse(try store.rename(id: noteID, input: NotesRenameInput(title: "Same", expectedModificationDate: date)).changed)
        XCTAssertFalse(try store.move(id: noteID, input: NotesMoveInput(destinationFolderID: folderID, expectedModificationDate: date)).changed)
        XCTAssertEqual(mutation.renameCalls, 0)
        XCTAssertEqual(mutation.moveCalls, 0)
        XCTAssertThrowsError(try store.previewRename(id: noteID, input: NotesRenameInput(title: "New", expectedModificationDate: Date(timeIntervalSince1970: 301)))) { error in
            XCTAssertEqual(error as? NotesError, .concurrencyConflict)
        }
        let sharedFolder = NotesOpaqueID.folder(accountScriptingID: "account-icloud", scriptingID: "folder-child")
        XCTAssertThrowsError(try store.previewMove(id: noteID, input: NotesMoveInput(destinationFolderID: sharedFolder, expectedModificationDate: date))) { error in
            XCTAssertEqual(error as? NotesError, .sharedTarget)
        }
    }

    func testTimedOutMutationReturnsOutcomeUnknownAndForbidsRetry() throws {
        let date = Date(timeIntervalSince1970: 300)
        let note = NotesNoteDescriptor(scriptingID: "note-safe", accountScriptingID: "account-icloud", folderScriptingID: "folder-root", title: "Before", creationDate: nil, modificationDate: date, passwordProtected: false, shared: false)
        let mutation = MutationBridgeStub(value: NotesMutationDescriptor(scriptingID: "note-safe", accountScriptingID: "account-icloud", folderScriptingID: "folder-root", title: "Before", html: "", modificationDate: date, passwordProtected: false, shared: false))
        mutation.thrownError = NotesMetadataBridgeError.timedOut
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(permission: NotesPermissionService(probe: ProbeStub(result: .available)), bridge: BridgeStub(snapshotValue: snapshot()), queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [note], complete: true)), mutationBridge: mutation, writeAccountStore: accountStore, idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency")))
        let noteID = NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe")

        let result = try store.rename(id: noteID, input: NotesRenameInput(title: "After", expectedModificationDate: date))

        XCTAssertEqual(result.verification, .outcomeUnknown)
        XCTAssertTrue(result.nextAction?.contains("Do not retry automatically") == true)
    }

    func testDeleteDryRunAndApplyUseFreshReadAndConfirmFolderChange() throws {
        let date = Date(timeIntervalSince1970: 300)
        let metadata = NotesNoteDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Private title", creationDate: nil,
            modificationDate: date, passwordProtected: false, shared: false
        )
        let current = NotesMutationDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Private title", html: "",
            modificationDate: date, passwordProtected: false, shared: false
        )
        let deleted = NotesMutationDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-recently-deleted", title: "Private title", html: "",
            modificationDate: Date(timeIntervalSince1970: 301), passwordProtected: false, shared: false
        )
        let mutation = MutationBridgeStub(value: deleted)
        mutation.readValues = [current]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
            mutationBridge: mutation, writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency"))
        )
        let noteID = NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe")
        let input = NotesDeleteInput(expectedModificationDate: date)

        let preview = try store.previewDelete(id: noteID, input: input)
        XCTAssertTrue(preview.dryRun)
        XCTAssertEqual(preview.operation, "delete")
        XCTAssertNil(preview.destinationFolderID)
        XCTAssertEqual(mutation.deleteCalls, 0)

        let result = try store.delete(id: noteID, input: input)
        XCTAssertEqual(result.verification, .readbackConfirmed)
        XCTAssertEqual(mutation.readCalls, 1)
        XCTAssertEqual(mutation.deleteCalls, 1)
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Private title"))
    }

    func testDeleteRejectsStaleSharedAndLockedNotesBeforeAppleEvent() throws {
        let date = Date(timeIntervalSince1970: 300)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        func makeStore(shared: Bool = false, locked: Bool = false) -> (NotesStore, MutationBridgeStub, String) {
            let metadata = NotesNoteDescriptor(
                scriptingID: "note-safe", accountScriptingID: "account-icloud",
                folderScriptingID: "folder-root", title: "Title", creationDate: nil,
                modificationDate: date, passwordProtected: locked, shared: shared
            )
            let descriptor = NotesMutationDescriptor(
                scriptingID: "note-safe", accountScriptingID: "account-icloud",
                folderScriptingID: "folder-root", title: "Title", html: "",
                modificationDate: date, passwordProtected: locked, shared: shared
            )
            let mutation = MutationBridgeStub(value: descriptor)
            return (NotesStore(
                permission: NotesPermissionService(probe: ProbeStub(result: .available)),
                bridge: BridgeStub(snapshotValue: snapshot()),
                queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
                mutationBridge: mutation, writeAccountStore: accountStore,
                idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent(UUID().uuidString))
            ), mutation, NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe"))
        }

        let stale = makeStore()
        XCTAssertThrowsError(try stale.0.delete(id: stale.2, input: NotesDeleteInput(expectedModificationDate: Date(timeIntervalSince1970: 301)))) {
            XCTAssertEqual($0 as? NotesError, .concurrencyConflict)
        }
        XCTAssertEqual(stale.1.deleteCalls, 0)
        let shared = makeStore(shared: true)
        XCTAssertThrowsError(try shared.0.delete(id: shared.2, input: NotesDeleteInput(expectedModificationDate: date))) {
            XCTAssertEqual($0 as? NotesError, .sharedTarget)
        }
        XCTAssertEqual(shared.1.deleteCalls, 0)
        let locked = makeStore(locked: true)
        XCTAssertThrowsError(try locked.0.delete(id: locked.2, input: NotesDeleteInput(expectedModificationDate: date))) {
            XCTAssertEqual($0 as? NotesError, .lockedNote)
        }
        XCTAssertEqual(locked.1.deleteCalls, 0)
    }

    func testDeleteFailureIsOutcomeUnknownAndForbidsAutomaticRetry() throws {
        let date = Date(timeIntervalSince1970: 300)
        let metadata = NotesNoteDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title", creationDate: nil,
            modificationDate: date, passwordProtected: false, shared: false
        )
        let current = NotesMutationDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title", html: "",
            modificationDate: date, passwordProtected: false, shared: false
        )
        let mutation = MutationBridgeStub(value: current)
        mutation.readValues = [current]
        mutation.deleteError = NotesMetadataBridgeError.timedOut
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
            mutationBridge: mutation, writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency"))
        )
        let noteID = NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe")

        let result = try store.delete(id: noteID, input: NotesDeleteInput(expectedModificationDate: date))
        XCTAssertEqual(result.verification, .outcomeUnknown)
        XCTAssertFalse(result.changed)
        XCTAssertTrue(result.nextAction?.contains("Do not retry automatically") == true)
        XCTAssertEqual(mutation.deleteCalls, 1)
    }

    func testEditBodyDryRunAndApplyUseHashGuardAndReadback() throws {
        let date = Date(timeIntervalSince1970: 300)
        let oldPlaintext = "Title\nOld body\n"
        let newPlaintext = "Title\nNew body\n"
        let metadata = NotesNoteDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title", creationDate: nil,
            modificationDate: date, passwordProtected: false, shared: false
        )
        let current = NotesMutationDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title",
            html: "<div>Title</div><div>Old body</div>", plaintext: oldPlaintext,
            modificationDate: date, passwordProtected: false, shared: false
        )
        let updated = NotesMutationDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title",
            html: "<div>Title</div><div>New body</div>", plaintext: newPlaintext,
            modificationDate: Date(timeIntervalSince1970: 301), passwordProtected: false, shared: false
        )
        let mutation = MutationBridgeStub(value: updated)
        mutation.readValues = [current, current, updated]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let store = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
            attachmentBridge: AttachmentBridgeStub(snapshotValue: NotesAttachmentSnapshot(attachments: [], complete: true)),
            mutationBridge: mutation,
            writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency"))
        )
        let noteID = NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe")
        let input = NotesEditBodyInput(
            bodyFormat: .plaintext,
            body: "New body",
            expectedModificationDate: date,
            expectedBodySHA256: NotesWritePolicy.sha256(oldPlaintext)
        )

        let preview = try store.previewEditBody(id: noteID, input: input)
        XCTAssertTrue(preview.changed)
        XCTAssertEqual(preview.previousBodySHA256, NotesWritePolicy.sha256(oldPlaintext))
        XCTAssertEqual(preview.bodySHA256, NotesWritePolicy.sha256(newPlaintext))
        XCTAssertEqual(mutation.replaceBodyCalls, 0)

        let result = try store.editBody(id: noteID, input: input)
        XCTAssertEqual(result.verification, .readbackConfirmed)
        XCTAssertEqual(result.bodySHA256, NotesWritePolicy.sha256(newPlaintext))
        XCTAssertEqual(mutation.replaceBodyCalls, 1)
    }

    func testEditBodyRejectsHashConflictAttachmentsAndRichContent() throws {
        let date = Date(timeIntervalSince1970: 300)
        let metadata = NotesNoteDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title", creationDate: nil,
            modificationDate: date, passwordProtected: false, shared: false
        )
        let current = NotesMutationDescriptor(
            scriptingID: "note-safe", accountScriptingID: "account-icloud",
            folderScriptingID: "folder-root", title: "Title",
            html: "<div>Title</div><div>Body</div>", plaintext: "Title\nBody\n",
            modificationDate: date, passwordProtected: false, shared: false
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountStore = NotesWriteAccountStore(directory: directory)
        try accountStore.save(NotesWriteAccountBinding(accountID: NotesOpaqueID.account(scriptingID: "account-icloud"), boundAt: Date()))
        let mutation = MutationBridgeStub(value: current)
        let input = NotesEditBodyInput(
            bodyFormat: .plaintext, body: "New", expectedModificationDate: date,
            expectedBodySHA256: String(repeating: "0", count: 64)
        )
        let common = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
            attachmentBridge: AttachmentBridgeStub(snapshotValue: NotesAttachmentSnapshot(attachments: [], complete: true)),
            mutationBridge: mutation, writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency"))
        )
        let noteID = NotesOpaqueID.note(accountScriptingID: "account-icloud", scriptingID: "note-safe")
        XCTAssertThrowsError(try common.previewEditBody(id: noteID, input: input)) { error in
            XCTAssertEqual(error as? NotesError, .bodyHashConflict)
        }

        let attachment = NotesAttachmentDescriptor(
            scriptingID: "attachment", name: "file", creationDate: nil,
            modificationDate: nil, contentIdentifier: nil, url: nil, shared: false
        )
        let withAttachment = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
            attachmentBridge: AttachmentBridgeStub(snapshotValue: NotesAttachmentSnapshot(attachments: [attachment], complete: true)),
            mutationBridge: MutationBridgeStub(value: current), writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency-2"))
        )
        let validInput = NotesEditBodyInput(
            bodyFormat: .plaintext, body: "New", expectedModificationDate: date,
            expectedBodySHA256: NotesWritePolicy.sha256(current.plaintext)
        )
        XCTAssertThrowsError(try withAttachment.previewEditBody(id: noteID, input: validInput)) { error in
            XCTAssertEqual(error as? NotesError, .unsupportedRichContent)
        }

        let rich = NotesMutationDescriptor(
            scriptingID: current.scriptingID, accountScriptingID: current.accountScriptingID,
            folderScriptingID: current.folderScriptingID, title: current.title,
            html: "<div>Title</div><table><tr><td>Body</td></tr></table>",
            plaintext: current.plaintext, modificationDate: date,
            passwordProtected: false, shared: false
        )
        let richStore = NotesStore(
            permission: NotesPermissionService(probe: ProbeStub(result: .available)),
            bridge: BridgeStub(snapshotValue: snapshot()),
            queryBridge: QueryBridgeStub(snapshotValue: NotesQuerySnapshot(notes: [metadata], complete: true)),
            attachmentBridge: AttachmentBridgeStub(snapshotValue: NotesAttachmentSnapshot(attachments: [], complete: true)),
            mutationBridge: MutationBridgeStub(value: rich), writeAccountStore: accountStore,
            idempotencyStore: NotesIdempotencyStore(directory: directory.appendingPathComponent("idempotency-3"))
        )
        XCTAssertThrowsError(try richStore.previewEditBody(id: noteID, input: validInput)) { error in
            XCTAssertEqual(error as? NotesError, .unsupportedRichContent)
        }
    }
}
