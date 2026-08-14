import Core
import XCTest
@testable import NotesAdapter

final class NotesAdapterTests: XCTestCase {
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
    }

    func testPermissionErrorsHaveStableCodes() {
        XCTAssertEqual(NotesError.permissionRequired.machineCode, "NOTES_PERMISSION_REQUIRED")
        XCTAssertEqual(NotesError.permissionDenied.machineCode, "NOTES_PERMISSION_DENIED")
        XCTAssertEqual(NotesError.targetUnavailable.machineCode, "NOTES_TARGET_UNAVAILABLE")
        XCTAssertEqual(NotesError.automationUnknown.machineCode, "NOTES_AUTOMATION_UNKNOWN")
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
        XCTAssertTrue(script.contains("folderCounter is greater than or equal to maximumFolders"))
        XCTAssertTrue(script.contains("folderCounter, 7, 4"))
        XCTAssertTrue(script.contains("folderDepth is greater than or equal to 4"))
        XCTAssertFalse(script.contains("every note"))
        XCTAssertFalse(script.contains("body of"))
        XCTAssertFalse(script.contains("plaintext"))
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
}
