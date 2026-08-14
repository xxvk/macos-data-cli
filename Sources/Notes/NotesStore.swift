import Core
import Foundation

public struct NotesStore: Sendable {
    private let permission: NotesPermissionService
    private let bridge: any NotesMetadataBridging
    private let queryBridge: any NotesQueryBridging
    private let bodyBridge: any NotesBodyBridging
    private let attachmentBridge: any NotesAttachmentBridging

    public init(
        permission: NotesPermissionService = NotesPermissionService(),
        bridge: any NotesMetadataBridging = SystemNotesMetadataBridge(),
        queryBridge: any NotesQueryBridging = SystemNotesQueryBridge(),
        bodyBridge: any NotesBodyBridging = SystemNotesBodyBridge(),
        attachmentBridge: any NotesAttachmentBridging = SystemNotesAttachmentBridge()
    ) {
        self.permission = permission
        self.bridge = bridge
        self.queryBridge = queryBridge
        self.bodyBridge = bodyBridge
        self.attachmentBridge = attachmentBridge
    }

    public func accounts() throws -> NotesAccountListResult {
        let snapshot = try loadSnapshot()
        let values = snapshot.accounts.map { account in
            NotesAccountPayload(
                id: NotesOpaqueID.account(scriptingID: account.scriptingID),
                name: account.name,
                isDefault: account.scriptingID == snapshot.defaultAccountScriptingID,
                folderCount: snapshot.folders.count { $0.accountScriptingID == account.scriptingID }
            )
        }.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return NotesAccountListResult(accounts: values, complete: snapshot.complete)
    }

    public func folders(
        limit: Int,
        cursor: String?,
        accountID: String?,
        parentID: String?
    ) throws -> PagedResult<NotesFolderPayload> {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw NotesError.invalidLimit }
        let snapshot = try loadSnapshot()
        let accountIDs = Dictionary(uniqueKeysWithValues: snapshot.accounts.map {
            ($0.scriptingID, NotesOpaqueID.account(scriptingID: $0.scriptingID))
        })
        if let accountID, !accountIDs.values.contains(accountID) { throw NotesError.invalidIdentifier }
        let folderIDs = Dictionary(uniqueKeysWithValues: snapshot.folders.map {
            ($0.scriptingID, NotesOpaqueID.folder(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID))
        })
        if let parentID, !folderIDs.values.contains(parentID) { throw NotesError.invalidIdentifier }
        let mapped = snapshot.folders.compactMap { folder -> NotesFolderPayload? in
            guard let opaqueAccount = accountIDs[folder.accountScriptingID],
                  let opaqueFolder = folderIDs[folder.scriptingID] else { return nil }
            return NotesFolderPayload(
                id: opaqueFolder,
                accountID: opaqueAccount,
                parentID: folder.parentScriptingID.flatMap { folderIDs[$0] },
                name: folder.name,
                shared: folder.shared,
                depth: folder.depth
            )
        }.filter {
            (accountID == nil || $0.accountID == accountID)
                && (parentID == nil || $0.parentID == parentID)
        }.sorted {
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        do {
            return try NotesFolderPagination.page(
                items: mapped,
                accountID: accountID,
                parentID: parentID,
                limit: limit,
                cursor: cursor,
                complete: snapshot.complete
            )
        } catch let error as PaginationError {
            throw error
        }
    }

    public func query(_ query: NotesQuery) throws -> PagedResult<NotesNotePayload> {
        guard (1...Pagination.maximumLimit).contains(query.limit) else { throw NotesError.invalidLimit }
        if let title = query.title, title.isEmpty || title.count > 200 { throw NotesError.invalidQuery }
        let metadata = try loadSnapshot()
        let accountIDs = Dictionary(uniqueKeysWithValues: metadata.accounts.map {
            ($0.scriptingID, NotesOpaqueID.account(scriptingID: $0.scriptingID))
        })
        let folderIDs = Dictionary(uniqueKeysWithValues: metadata.folders.map {
            ($0.scriptingID, NotesOpaqueID.folder(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID))
        })
        if let accountID = query.accountID, !accountIDs.values.contains(accountID) { throw NotesError.invalidIdentifier }
        if let folderID = query.folderID, !folderIDs.values.contains(folderID) { throw NotesError.invalidIdentifier }

        let snapshot: NotesQuerySnapshot
        do {
            snapshot = try queryBridge.snapshot(maximumNotes: SystemNotesQueryBridge.maximumNotes)
        } catch NotesMetadataBridgeError.automationDenied {
            throw NotesError.permissionDenied
        } catch NotesMetadataBridgeError.targetNotRunning {
            throw NotesError.targetNotRunning
        } catch NotesMetadataBridgeError.timedOut {
            throw NotesError.timedOut
        } catch {
            throw NotesError.executionFailed
        }
        let mapped = snapshot.notes.compactMap { note -> NotesNotePayload? in
            guard let accountID = accountIDs[note.accountScriptingID],
                  let folderID = folderIDs[note.folderScriptingID] else { return nil }
            return NotesNotePayload(
                id: NotesOpaqueID.note(accountScriptingID: note.accountScriptingID, scriptingID: note.scriptingID),
                accountID: accountID,
                folderID: folderID,
                title: note.title,
                creationDate: note.creationDate,
                modificationDate: note.modificationDate,
                passwordProtected: note.passwordProtected,
                shared: note.shared
            )
        }.filter { note in
            if let value = query.accountID, note.accountID != value { return false }
            if let value = query.folderID, note.folderID != value { return false }
            if let value = query.title, !note.title.localizedCaseInsensitiveContains(value) { return false }
            if let value = query.modifiedAfter, !(note.modificationDate.map { $0 >= value } ?? false) { return false }
            return true
        }.sorted {
            let lhs = $0.modificationDate ?? .distantPast
            let rhs = $1.modificationDate ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            return $0.id < $1.id
        }
        return try NotesQueryPagination.page(
            items: mapped,
            query: query,
            complete: metadata.complete && snapshot.complete
        )
    }

    public func get(id: String, bodyFormat: NotesBodyFormat = .none, includeAttachments: Bool = false) throws -> NotesGetResult {
        guard NotesOpaqueID.isNote(id) else { throw NotesError.invalidIdentifier }
        try requirePermission()
        let snapshot: NotesQuerySnapshot
        do {
            snapshot = try queryBridge.snapshot(maximumNotes: SystemNotesQueryBridge.maximumNotes)
        } catch NotesMetadataBridgeError.automationDenied {
            throw NotesError.permissionDenied
        } catch NotesMetadataBridgeError.targetNotRunning {
            throw NotesError.targetNotRunning
        } catch NotesMetadataBridgeError.timedOut {
            throw NotesError.timedOut
        } catch {
            throw NotesError.executionFailed
        }
        guard let descriptor = snapshot.notes.first(where: {
            NotesOpaqueID.note(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID) == id
        }) else {
            throw NotesError.invalidIdentifier
        }
        let accountID = NotesOpaqueID.account(scriptingID: descriptor.accountScriptingID)
        let folderID = NotesOpaqueID.folder(
            accountScriptingID: descriptor.accountScriptingID,
            scriptingID: descriptor.folderScriptingID
        )
        let note = NotesNotePayload(
            id: id,
            accountID: accountID,
            folderID: folderID,
            title: descriptor.title,
            creationDate: descriptor.creationDate,
            modificationDate: descriptor.modificationDate,
            passwordProtected: descriptor.passwordProtected,
            shared: descriptor.shared
        )
        if descriptor.passwordProtected && (bodyFormat != .none || includeAttachments) {
            throw NotesError.lockedNote
        }
        var body: String?
        var byteCount: Int?
        if bodyFormat != .none {
            do { body = try bodyBridge.read(scriptingID: descriptor.scriptingID, format: bodyFormat) }
            catch NotesMetadataBridgeError.automationDenied { throw NotesError.permissionDenied }
            catch NotesMetadataBridgeError.targetNotRunning { throw NotesError.targetNotRunning }
            catch NotesMetadataBridgeError.timedOut { throw NotesError.timedOut }
            catch { throw NotesError.executionFailed }
            byteCount = body?.lengthOfBytes(using: .utf8)
            guard (byteCount ?? 0) <= NotesBodyPolicy.maximumBytes else { throw NotesError.bodyTooLarge }
        }
        var attachments: [NotesAttachmentPayload]?
        var attachmentsComplete: Bool?
        if includeAttachments {
            let snapshot: NotesAttachmentSnapshot
            do { snapshot = try attachmentBridge.snapshot(scriptingID: descriptor.scriptingID, maximumAttachments: SystemNotesAttachmentBridge.maximumAttachments) }
            catch NotesMetadataBridgeError.automationDenied { throw NotesError.permissionDenied }
            catch NotesMetadataBridgeError.targetNotRunning { throw NotesError.targetNotRunning }
            catch NotesMetadataBridgeError.timedOut { throw NotesError.timedOut }
            catch { throw NotesError.executionFailed }
            attachments = snapshot.attachments.map { value in
                NotesAttachmentPayload(
                    id: NotesOpaqueID.attachment(noteScriptingID: descriptor.scriptingID, scriptingID: value.scriptingID),
                    name: value.name,
                    creationDate: value.creationDate,
                    modificationDate: value.modificationDate,
                    contentIdentifier: value.contentIdentifier,
                    url: value.url,
                    shared: value.shared
                )
            }
            attachmentsComplete = snapshot.complete
        }
        return NotesGetResult(note: note, bodyFormat: bodyFormat, body: body, bodyBytes: byteCount, attachmentsIncluded: includeAttachments, attachments: attachments, attachmentsComplete: attachmentsComplete)
    }

    private func loadSnapshot() throws -> NotesMetadataSnapshot {
        try requirePermission()
        do {
            return try bridge.snapshot(
                maximumAccounts: SystemNotesMetadataBridge.maximumAccounts,
                maximumFolders: SystemNotesMetadataBridge.maximumFolders
            )
        } catch NotesMetadataBridgeError.automationDenied {
            throw NotesError.permissionDenied
        } catch NotesMetadataBridgeError.targetNotRunning {
            throw NotesError.targetNotRunning
        } catch NotesMetadataBridgeError.timedOut {
            throw NotesError.timedOut
        } catch {
            throw NotesError.executionFailed
        }
    }

    private func requirePermission() throws {
        switch permission.check(requestConsent: false).access {
        case .available: break
        case .requiresConsent: throw NotesError.permissionRequired
        case .denied: throw NotesError.permissionDenied
        case .targetNotRunning: throw NotesError.targetNotRunning
        case .targetUnavailable: throw NotesError.targetUnavailable
        case .unknown: throw NotesError.automationUnknown
        }
    }
}
