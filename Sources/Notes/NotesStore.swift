import Core
import Foundation

public struct NotesStore: Sendable {
    private let permission: NotesPermissionService
    private let bridge: any NotesMetadataBridging
    private let queryBridge: any NotesQueryBridging
    private let bodyBridge: any NotesBodyBridging
    private let attachmentBridge: any NotesAttachmentBridging
    private let mutationBridge: any NotesMutationBridging
    private let folderMutationBridge: any NotesFolderMutationBridging
    private let writeAccountStore: NotesWriteAccountStore
    private let idempotencyStore: NotesIdempotencyStore
    private let folderIdempotencyStore: NotesFolderIdempotencyStore

    public init(
        permission: NotesPermissionService = NotesPermissionService(),
        bridge: any NotesMetadataBridging = SystemNotesMetadataBridge(),
        queryBridge: any NotesQueryBridging = SystemNotesQueryBridge(),
        bodyBridge: any NotesBodyBridging = SystemNotesBodyBridge(),
        attachmentBridge: any NotesAttachmentBridging = SystemNotesAttachmentBridge(),
        mutationBridge: any NotesMutationBridging = SystemNotesMutationBridge(),
        folderMutationBridge: any NotesFolderMutationBridging = SystemNotesFolderMutationBridge(),
        writeAccountStore: NotesWriteAccountStore = NotesWriteAccountStore(),
        idempotencyStore: NotesIdempotencyStore = NotesIdempotencyStore(),
        folderIdempotencyStore: NotesFolderIdempotencyStore = NotesFolderIdempotencyStore()
    ) {
        self.permission = permission
        self.bridge = bridge
        self.queryBridge = queryBridge
        self.bodyBridge = bodyBridge
        self.attachmentBridge = attachmentBridge
        self.mutationBridge = mutationBridge
        self.folderMutationBridge = folderMutationBridge
        self.writeAccountStore = writeAccountStore
        self.idempotencyStore = idempotencyStore
        self.folderIdempotencyStore = folderIdempotencyStore
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

    public func writeAccountStatus() -> NotesWriteAccountStatus {
        guard let binding = try? writeAccountStore.load() else {
            return NotesWriteAccountStatus(bound: false, valid: false, accountID: nil, boundAt: nil)
        }
        let valid = (try? loadSnapshot().accounts.contains {
            NotesOpaqueID.account(scriptingID: $0.scriptingID) == binding.accountID
        }) ?? false
        return NotesWriteAccountStatus(bound: true, valid: valid, accountID: binding.accountID, boundAt: binding.boundAt)
    }

    public func changeWriteAccount(accountID: String?, clear: Bool, apply: Bool) throws -> NotesWriteAccountChangeResult {
        if clear {
            let changed = (try writeAccountStore.load()) != nil
            if apply { try writeAccountStore.clear() }
            return NotesWriteAccountChangeResult(operation: "clear_write_account", dryRun: !apply, changed: changed, accountID: nil)
        }
        guard let accountID, !accountID.isEmpty else { throw NotesError.invalidWriteInput }
        let snapshot = try loadSnapshot()
        guard snapshot.accounts.contains(where: { NotesOpaqueID.account(scriptingID: $0.scriptingID) == accountID }) else { throw NotesError.invalidIdentifier }
        let current = try writeAccountStore.load()
        let changed = current?.accountID != accountID
        if apply { try writeAccountStore.save(NotesWriteAccountBinding(accountID: accountID, boundAt: Date())) }
        return NotesWriteAccountChangeResult(operation: "bind_write_account", dryRun: !apply, changed: changed, accountID: accountID)
    }

    public func previewCreateFolder(_ input: NotesFolderCreateInput) throws -> NotesFolderWritePreview {
        let context = try folderCreateContext(input)
        return NotesFolderWritePreview(
            operation: "create_folder", changed: true, folderID: nil,
            accountID: context.accountID, sourceParentFolderID: nil,
            destinationParentFolderID: input.parentFolderID,
            previousNameSHA256: nil, nameSHA256: context.nameHash
        )
    }

    public func createFolder(_ input: NotesFolderCreateInput, idempotent: Bool) throws -> NotesFolderWriteResult {
        let context = try folderCreateContext(input)
        if idempotent, let receipt = try folderIdempotencyStore.receipt(for: input) {
            guard receipt.state == .saved, let folderID = receipt.folderID else {
                return NotesFolderWriteResult(
                    operation: "create_folder", changed: false, verification: .outcomeUnknown,
                    folderID: nil, accountID: context.accountID, parentFolderID: input.parentFolderID,
                    nameSHA256: context.nameHash, deduplicated: true,
                    nextAction: "An in-flight folder receipt exists. Do not retry automatically; list the target parent and verify first."
                )
            }
            if let existing = folderByOpaqueID(folderID, in: context.snapshot),
               NotesWritePolicy.sha256(existing.name) == context.nameHash,
               existing.parentScriptingID == context.parent?.scriptingID {
                return folderResult(
                    operation: "create_folder", descriptor: existing.mutationDescriptor,
                    previousFolderID: nil, changed: false,
                    verification: .idempotencyReceiptReadbackConfirmed,
                    deduplicated: true, nameHash: context.nameHash
                )
            }
            return NotesFolderWriteResult(
                operation: "create_folder", changed: false, verification: .idempotencyReceiptPending,
                folderID: folderID, accountID: context.accountID, parentFolderID: input.parentFolderID,
                nameSHA256: context.nameHash, deduplicated: true,
                nextAction: "A recent folder receipt prevented a duplicate. Do not retry automatically; list folders and verify the returned ID."
            )
        }
        if idempotent { try folderIdempotencyStore.begin(input) }
        let saved: NotesFolderMutationDescriptor
        do {
            saved = try folderMutationBridge.create(
                accountScriptingID: context.accountScriptingID,
                parentFolderScriptingID: context.parent?.scriptingID,
                name: input.name
            )
        } catch NotesMetadataBridgeError.timedOut {
            return NotesFolderWriteResult(
                operation: "create_folder", changed: false, verification: .outcomeUnknown,
                folderID: nil, accountID: context.accountID, parentFolderID: input.parentFolderID,
                nameSHA256: context.nameHash,
                nextAction: "The folder create Apple Event timed out. Do not retry automatically; list the target parent and verify first."
            )
        } catch { throw mapMutationError(error) }
        let folderID = NotesOpaqueID.folder(accountScriptingID: saved.accountScriptingID, scriptingID: saved.scriptingID)
        if idempotent { try? folderIdempotencyStore.complete(input, folderID: folderID) }
        let readback = try? folderMutationBridge.read(folderScriptingID: saved.scriptingID)
        let confirmed = readback.map {
            $0.accountScriptingID == context.accountScriptingID
                && $0.parentScriptingID == context.parent?.scriptingID
                && NotesWritePolicy.sha256($0.name) == context.nameHash
                && !$0.shared
        } ?? false
        return folderResult(
            operation: "create_folder", descriptor: readback ?? saved,
            previousFolderID: nil, changed: true,
            verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending,
            deduplicated: false, nameHash: context.nameHash,
            nextAction: confirmed ? nil : "Notes accepted the folder create but read-back is pending. Do not retry automatically; list folders and verify first."
        )
    }

    public func previewRenameFolder(id: String, input: NotesFolderRenameInput) throws -> NotesFolderWritePreview {
        let context = try folderMutationContext(id: id, expectedNameHash: input.expectedNameSHA256)
        try NotesWritePolicy.validateFolderName(input.name)
        try rejectDuplicateFolderName(input.name, parentScriptingID: context.folder.parentScriptingID, excluding: context.folder.scriptingID, snapshot: context.snapshot, accountScriptingID: context.folder.accountScriptingID)
        return NotesFolderWritePreview(
            operation: "rename_folder", changed: context.folder.name != input.name,
            folderID: id, accountID: context.accountID,
            sourceParentFolderID: opaqueParentID(context.folder, snapshot: context.snapshot),
            destinationParentFolderID: opaqueParentID(context.folder, snapshot: context.snapshot),
            previousNameSHA256: input.expectedNameSHA256,
            nameSHA256: NotesWritePolicy.sha256(input.name)
        )
    }

    public func renameFolder(id: String, input: NotesFolderRenameInput) throws -> NotesFolderWriteResult {
        let context = try folderMutationContext(id: id, expectedNameHash: input.expectedNameSHA256)
        try NotesWritePolicy.validateFolderName(input.name)
        try rejectDuplicateFolderName(input.name, parentScriptingID: context.folder.parentScriptingID, excluding: context.folder.scriptingID, snapshot: context.snapshot, accountScriptingID: context.folder.accountScriptingID)
        let nameHash = NotesWritePolicy.sha256(input.name)
        if context.folder.name == input.name {
            return folderResult(operation: "rename_folder", descriptor: context.folder.mutationDescriptor, previousFolderID: id, changed: false, verification: .readbackConfirmed, deduplicated: false, nameHash: nameHash)
        }
        try revalidateFolder(context)
        let saved: NotesFolderMutationDescriptor
        do { saved = try folderMutationBridge.rename(folderScriptingID: context.folder.scriptingID, name: input.name) }
        catch NotesMetadataBridgeError.timedOut { return unknownFolderResult(operation: "rename_folder", context: context, nameHash: nameHash) }
        catch { throw mapMutationError(error) }
        let readback = try? folderMutationBridge.read(folderScriptingID: saved.scriptingID)
        let confirmed = readback.map {
            $0.accountScriptingID == context.folder.accountScriptingID
                && $0.parentScriptingID == context.folder.parentScriptingID
                && NotesWritePolicy.sha256($0.name) == nameHash
        } ?? false
        return folderResult(
            operation: "rename_folder", descriptor: readback ?? saved, previousFolderID: id,
            changed: true, verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending,
            deduplicated: false, nameHash: nameHash,
            nextAction: confirmed ? nil : "Notes accepted the folder rename but read-back is pending. Do not retry automatically; list folders and verify first."
        )
    }

    public func previewMoveFolder(id: String, input: NotesFolderMoveInput) throws -> NotesFolderWritePreview {
        let context = try folderMoveContext(id: id, input: input)
        return NotesFolderWritePreview(
            operation: "move_folder", changed: context.folder.parentScriptingID != context.destination?.scriptingID,
            folderID: id, accountID: context.accountID,
            sourceParentFolderID: input.expectedParentFolderID,
            destinationParentFolderID: input.destinationParentFolderID,
            previousNameSHA256: input.expectedNameSHA256,
            nameSHA256: input.expectedNameSHA256
        )
    }

    public func moveFolder(id: String, input: NotesFolderMoveInput) throws -> NotesFolderWriteResult {
        _ = id
        _ = input
        throw NotesError.folderMoveUnsupported
    }

    public func previewDeleteFolder(id: String, input: NotesFolderDeleteInput) throws -> NotesFolderWritePreview {
        let context = try folderDeleteContext(id: id, input: input)
        return NotesFolderWritePreview(
            operation: "delete_folder", changed: true,
            folderID: id, accountID: context.accountID,
            sourceParentFolderID: input.expectedParentFolderID,
            destinationParentFolderID: nil,
            previousNameSHA256: input.expectedNameSHA256,
            nameSHA256: input.expectedNameSHA256
        )
    }

    public func deleteFolder(id: String, input: NotesFolderDeleteInput) throws -> NotesFolderWriteResult {
        _ = id
        _ = input
        throw NotesError.folderDeleteUnsupported
    }

    public func previewCreate(_ input: NotesCreateInput) throws -> NotesWritePreview {
        let context = try createContext(input)
        return NotesWritePreview(operation: "create", changed: true, noteID: nil, accountID: context.accountID, sourceFolderID: nil, destinationFolderID: input.folderID, expectedModificationDate: nil, titleSHA256: context.prepared.titleSHA256, bodySHA256: context.prepared.bodySHA256, bodyBytes: context.prepared.bodyBytes)
    }

    public func create(_ input: NotesCreateInput, idempotent: Bool) throws -> NotesWriteResult {
        let context = try createContext(input)
        if idempotent, let receipt = try idempotencyStore.receipt(for: input) {
            guard receipt.state == .saved, let noteID = receipt.noteID else {
                return NotesWriteResult(operation: "create", changed: false, verification: .outcomeUnknown, noteID: nil, accountID: context.accountID, folderID: input.folderID, modificationDate: nil, titleSHA256: context.prepared.titleSHA256, bodySHA256: context.prepared.bodySHA256, bodyBytes: context.prepared.bodyBytes, deduplicated: true, nextAction: "An in-flight idempotency receipt exists. Do not retry automatically; query and verify the note first.")
            }
            if let descriptor = try? resolveNote(noteID), descriptor.accountScriptingID == context.accountScriptingID {
                return result(operation: "create", descriptor: descriptor, previousNoteID: nil, changed: false, verification: .idempotencyReceiptReadbackConfirmed, deduplicated: true, titleHash: context.prepared.titleSHA256, bodyHash: context.prepared.bodySHA256, bodyBytes: context.prepared.bodyBytes)
            }
            return NotesWriteResult(operation: "create", changed: false, verification: .idempotencyReceiptPending, noteID: noteID, accountID: context.accountID, folderID: input.folderID, modificationDate: nil, titleSHA256: context.prepared.titleSHA256, bodySHA256: context.prepared.bodySHA256, bodyBytes: context.prepared.bodyBytes, deduplicated: true, nextAction: "A recent receipt prevented a duplicate. Do not retry automatically; use notes get with the returned ID.")
        }
        if idempotent { try idempotencyStore.begin(input) }
        let saved: NotesMutationDescriptor
        do { saved = try mutationBridge.create(accountScriptingID: context.accountScriptingID, folderScriptingID: context.folder.scriptingID, html: context.prepared.html) }
        catch NotesMetadataBridgeError.timedOut {
            return NotesWriteResult(operation: "create", changed: false, verification: .outcomeUnknown, noteID: nil, accountID: context.accountID, folderID: input.folderID, modificationDate: nil, titleSHA256: context.prepared.titleSHA256, bodySHA256: context.prepared.bodySHA256, bodyBytes: context.prepared.bodyBytes, nextAction: "The Apple Event timed out. Do not retry automatically; query the target folder first.")
        } catch { throw mapMutationError(error) }
        let noteID = NotesOpaqueID.note(accountScriptingID: saved.accountScriptingID, scriptingID: saved.scriptingID)
        if idempotent { try? idempotencyStore.complete(input, noteID: noteID) }
        let readback = try? mutationBridge.read(noteScriptingID: saved.scriptingID)
        let confirmed = readback.map { $0.folderScriptingID == context.folder.scriptingID && NotesWritePolicy.sha256($0.title) == context.prepared.titleSHA256 && NotesWritePolicy.sha256($0.plaintext) == context.prepared.bodySHA256 } ?? false
        return result(operation: "create", descriptor: readback ?? saved, previousNoteID: nil, changed: true, verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending, deduplicated: false, titleHash: context.prepared.titleSHA256, bodyHash: context.prepared.bodySHA256, bodyBytes: context.prepared.bodyBytes, nextAction: confirmed ? nil : "Notes accepted the create but exact read-back is pending. Do not retry automatically; use notes get.")
    }

    public func previewRename(id: String, input: NotesRenameInput) throws -> NotesWritePreview {
        let context = try mutationContext(id: id, expected: input.expectedModificationDate)
        try NotesWritePolicy.validateTitle(input.title)
        return NotesWritePreview(operation: "rename", changed: context.note.title != input.title, noteID: id, accountID: context.accountID, sourceFolderID: context.folderID, destinationFolderID: context.folderID, expectedModificationDate: input.expectedModificationDate, titleSHA256: NotesWritePolicy.sha256(input.title), bodySHA256: nil, bodyBytes: nil)
    }

    public func rename(id: String, input: NotesRenameInput) throws -> NotesWriteResult {
        let context = try mutationContext(id: id, expected: input.expectedModificationDate)
        try NotesWritePolicy.validateTitle(input.title)
        let titleHash = NotesWritePolicy.sha256(input.title)
        if context.note.title == input.title { return result(operation: "rename", descriptor: context.note, previousNoteID: id, changed: false, verification: .readbackConfirmed, deduplicated: false, titleHash: titleHash) }
        let saved: NotesMutationDescriptor
        do { saved = try mutationBridge.rename(noteScriptingID: context.note.scriptingID, title: input.title) }
        catch NotesMetadataBridgeError.timedOut { return unknownResult(operation: "rename", context: context, titleHash: titleHash) }
        catch { throw mapMutationError(error) }
        let readback = try? mutationBridge.read(noteScriptingID: saved.scriptingID)
        let confirmed = readback.map { NotesWritePolicy.sha256($0.title) == titleHash } ?? false
        return result(operation: "rename", descriptor: readback ?? saved, previousNoteID: id, changed: true, verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending, deduplicated: false, titleHash: titleHash, nextAction: confirmed ? nil : "Notes accepted the rename but read-back is pending. Do not retry automatically; use notes get.")
    }

    public func previewMove(id: String, input: NotesMoveInput) throws -> NotesWritePreview {
        let context = try mutationContext(id: id, expected: input.expectedModificationDate)
        let destination = try resolveWritableFolder(input.destinationFolderID, boundAccountID: context.accountID)
        return NotesWritePreview(operation: "move", changed: context.note.folderScriptingID != destination.scriptingID, noteID: id, accountID: context.accountID, sourceFolderID: context.folderID, destinationFolderID: input.destinationFolderID, expectedModificationDate: input.expectedModificationDate, titleSHA256: NotesWritePolicy.sha256(context.note.title), bodySHA256: nil, bodyBytes: nil)
    }

    public func move(id: String, input: NotesMoveInput) throws -> NotesWriteResult {
        let context = try mutationContext(id: id, expected: input.expectedModificationDate)
        let destination = try resolveWritableFolder(input.destinationFolderID, boundAccountID: context.accountID)
        let titleHash = NotesWritePolicy.sha256(context.note.title)
        if context.note.folderScriptingID == destination.scriptingID { return result(operation: "move", descriptor: context.note, previousNoteID: id, changed: false, verification: .readbackConfirmed, deduplicated: false, titleHash: titleHash) }
        let saved: NotesMutationDescriptor
        do { saved = try mutationBridge.move(noteScriptingID: context.note.scriptingID, destinationFolderScriptingID: destination.scriptingID) }
        catch NotesMetadataBridgeError.timedOut { return unknownResult(operation: "move", context: context, titleHash: titleHash) }
        catch { throw mapMutationError(error) }
        let readback = try? mutationBridge.read(noteScriptingID: saved.scriptingID)
        let confirmed = readback?.folderScriptingID == destination.scriptingID
        return result(operation: "move", descriptor: readback ?? saved, previousNoteID: id, changed: true, verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending, deduplicated: false, titleHash: titleHash, nextAction: confirmed ? nil : "Notes accepted the move but read-back is pending. Do not retry automatically; use notes get.")
    }

    public func previewDelete(id: String, input: NotesDeleteInput) throws -> NotesWritePreview {
        let context = try mutationContext(id: id, expected: input.expectedModificationDate)
        return NotesWritePreview(
            operation: "delete", changed: true, noteID: id,
            accountID: context.accountID, sourceFolderID: context.folderID,
            destinationFolderID: nil,
            expectedModificationDate: input.expectedModificationDate,
            titleSHA256: NotesWritePolicy.sha256(context.note.title),
            bodySHA256: nil, bodyBytes: nil
        )
    }

    public func delete(id: String, input: NotesDeleteInput) throws -> NotesWriteResult {
        let context = try mutationContext(id: id, expected: input.expectedModificationDate)
        let current = try revalidateNoteForDelete(context, expected: input.expectedModificationDate)
        let titleHash = NotesWritePolicy.sha256(current.title)
        let saved: NotesMutationDescriptor
        do {
            saved = try mutationBridge.delete(noteScriptingID: current.scriptingID)
        } catch NotesMetadataBridgeError.automationDenied {
            throw NotesError.permissionDenied
        } catch {
            return NotesWriteResult(
                operation: "delete", changed: false, verification: .outcomeUnknown,
                noteID: id, accountID: context.accountID, folderID: context.folderID,
                modificationDate: current.modificationDate, titleSHA256: titleHash,
                nextAction: "The recoverable delete outcome is unknown. Do not retry automatically; query the original folder and inspect Notes Recently Deleted first."
            )
        }
        let confirmed = saved.accountScriptingID == current.accountScriptingID
            && saved.folderScriptingID != current.folderScriptingID
            && NotesWritePolicy.sha256(saved.title) == titleHash
        return result(
            operation: "delete", descriptor: saved, previousNoteID: id,
            changed: true,
            verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending,
            deduplicated: false, titleHash: titleHash,
            nextAction: confirmed ? nil : "Notes accepted the recoverable delete but Recently Deleted read-back is pending. Do not retry automatically; inspect Notes UI first."
        )
    }

    public func previewEditBody(id: String, input: NotesEditBodyInput) throws -> NotesWritePreview {
        let context = try bodyEditContext(id: id, input: input)
        return NotesWritePreview(
            operation: "edit_body",
            changed: context.currentBodySHA256 != context.prepared.bodySHA256,
            noteID: id,
            accountID: context.mutation.accountID,
            sourceFolderID: context.mutation.folderID,
            destinationFolderID: context.mutation.folderID,
            expectedModificationDate: input.expectedModificationDate,
            titleSHA256: NotesWritePolicy.sha256(context.current.title),
            previousBodySHA256: context.currentBodySHA256,
            bodySHA256: context.prepared.bodySHA256,
            bodyBytes: context.prepared.bodyBytes
        )
    }

    public func editBody(id: String, input: NotesEditBodyInput) throws -> NotesWriteResult {
        let context = try bodyEditContext(id: id, input: input)
        let titleHash = NotesWritePolicy.sha256(context.current.title)
        if context.currentBodySHA256 == context.prepared.bodySHA256 {
            return result(
                operation: "edit_body",
                descriptor: context.current,
                previousNoteID: id,
                changed: false,
                verification: .readbackConfirmed,
                deduplicated: false,
                titleHash: titleHash,
                bodyHash: context.prepared.bodySHA256,
                bodyBytes: context.prepared.bodyBytes
            )
        }

        let saved: NotesMutationDescriptor
        do {
            saved = try mutationBridge.replaceBody(
                noteScriptingID: context.current.scriptingID,
                html: context.prepared.html
            )
        } catch NotesMetadataBridgeError.timedOut {
            return NotesWriteResult(
                operation: "edit_body",
                changed: false,
                verification: .outcomeUnknown,
                noteID: id,
                previousNoteID: nil,
                accountID: context.mutation.accountID,
                folderID: context.mutation.folderID,
                modificationDate: context.current.modificationDate,
                titleSHA256: titleHash,
                bodySHA256: context.prepared.bodySHA256,
                bodyBytes: context.prepared.bodyBytes,
                nextAction: "The Apple Event timed out. Do not retry automatically; fetch the note body and verify its SHA-256 first."
            )
        } catch {
            throw mapMutationError(error)
        }

        let readback = try? mutationBridge.read(noteScriptingID: saved.scriptingID)
        let confirmed = readback.map {
            NotesWritePolicy.sha256($0.title) == titleHash
                && NotesWritePolicy.sha256($0.plaintext) == context.prepared.bodySHA256
                && $0.accountScriptingID == context.current.accountScriptingID
                && $0.folderScriptingID == context.current.folderScriptingID
        } ?? false
        return result(
            operation: "edit_body",
            descriptor: readback ?? saved,
            previousNoteID: id,
            changed: true,
            verification: confirmed ? .readbackConfirmed : .saveAcceptedReadbackPending,
            deduplicated: false,
            titleHash: titleHash,
            bodyHash: context.prepared.bodySHA256,
            bodyBytes: context.prepared.bodyBytes,
            nextAction: confirmed ? nil : "Notes accepted the body replacement but read-back is pending. Do not retry automatically; fetch the body and verify its SHA-256."
        )
    }

    private struct CreateContext { let prepared: PreparedNotesCreate; let accountID: String; let accountScriptingID: String; let folder: NotesFolderDescriptor }
    private struct MutationContext { let note: NotesMutationDescriptor; let accountID: String; let folderID: String }
    private struct FolderCreateContext {
        let snapshot: NotesMetadataSnapshot
        let accountID: String
        let accountScriptingID: String
        let parent: NotesFolderDescriptor?
        let nameHash: String
    }
    private struct FolderMutationContext {
        let snapshot: NotesMetadataSnapshot
        let folder: NotesFolderDescriptor
        let accountID: String
        let expectedNameHash: String
    }
    private struct FolderMoveContext {
        let base: FolderMutationContext
        let destination: NotesFolderDescriptor?
        var snapshot: NotesMetadataSnapshot { base.snapshot }
        var folder: NotesFolderDescriptor { base.folder }
        var accountID: String { base.accountID }
    }
    private struct BodyEditContext {
        let mutation: MutationContext
        let current: NotesMutationDescriptor
        let currentBodySHA256: String
        let prepared: PreparedNotesBodyEdit
    }

    private func createContext(_ input: NotesCreateInput) throws -> CreateContext {
        let prepared = try NotesWritePolicy.prepare(input)
        let binding = try requiredBinding()
        let folder = try resolveWritableFolder(input.folderID, boundAccountID: binding.accountID)
        return CreateContext(prepared: prepared, accountID: binding.accountID, accountScriptingID: folder.accountScriptingID, folder: folder)
    }

    private func folderCreateContext(_ input: NotesFolderCreateInput) throws -> FolderCreateContext {
        try NotesWritePolicy.validateFolderName(input.name)
        let snapshot = try loadCompleteFolderSnapshot()
        let binding = try requiredBinding(in: snapshot)
        let account = try boundAccount(binding.accountID, in: snapshot)
        let parent = try resolveFolderParent(input.parentFolderID, boundAccountID: binding.accountID, snapshot: snapshot)
        if let parent, parent.depth >= SystemNotesMetadataBridge.maximumDepth { throw NotesError.invalidWriteInput }
        try rejectDuplicateFolderName(input.name, parentScriptingID: parent?.scriptingID, excluding: nil, snapshot: snapshot, accountScriptingID: account.scriptingID)
        return FolderCreateContext(
            snapshot: snapshot, accountID: binding.accountID,
            accountScriptingID: account.scriptingID, parent: parent,
            nameHash: NotesWritePolicy.sha256(input.name)
        )
    }

    private func folderMutationContext(id: String, expectedNameHash: String) throws -> FolderMutationContext {
        guard NotesOpaqueID.isFolder(id) else { throw NotesError.invalidIdentifier }
        try NotesWritePolicy.validateFolderNameHash(expectedNameHash)
        let snapshot = try loadCompleteFolderSnapshot()
        let binding = try requiredBinding(in: snapshot)
        guard let folder = folderByOpaqueID(id, in: snapshot) else { throw NotesError.invalidIdentifier }
        guard NotesOpaqueID.account(scriptingID: folder.accountScriptingID) == binding.accountID else { throw NotesError.writeAccountMismatch }
        guard !folder.shared else { throw NotesError.sharedTarget }
        try rejectDefaultFolder(folder, snapshot: snapshot)
        guard NotesWritePolicy.sha256(folder.name) == expectedNameHash else { throw NotesError.folderConcurrencyConflict }
        return FolderMutationContext(snapshot: snapshot, folder: folder, accountID: binding.accountID, expectedNameHash: expectedNameHash)
    }

    private func folderMoveContext(id: String, input: NotesFolderMoveInput) throws -> FolderMoveContext {
        let base = try folderMutationContext(id: id, expectedNameHash: input.expectedNameSHA256)
        guard opaqueParentID(base.folder, snapshot: base.snapshot) == input.expectedParentFolderID else {
            throw NotesError.folderConcurrencyConflict
        }
        let destination = try resolveFolderParent(input.destinationParentFolderID, boundAccountID: base.accountID, snapshot: base.snapshot)
        if destination?.scriptingID == base.folder.scriptingID
            || destination.map({ NotesWritePolicy.isFolderDescendant(candidateScriptingID: $0.scriptingID, of: base.folder.scriptingID, folders: base.snapshot.folders) }) == true {
            throw NotesError.folderCycle
        }
        let subtreeDepth = base.snapshot.folders
            .filter { $0.scriptingID == base.folder.scriptingID || NotesWritePolicy.isFolderDescendant(candidateScriptingID: $0.scriptingID, of: base.folder.scriptingID, folders: base.snapshot.folders) }
            .map(\.depth).max().map { $0 - base.folder.depth } ?? 0
        let destinationDepth = destination.map { $0.depth + 1 } ?? 0
        guard destinationDepth + subtreeDepth <= SystemNotesMetadataBridge.maximumDepth else { throw NotesError.invalidWriteInput }
        try rejectDuplicateFolderName(
            base.folder.name, parentScriptingID: destination?.scriptingID,
            excluding: base.folder.scriptingID, snapshot: base.snapshot,
            accountScriptingID: base.folder.accountScriptingID
        )
        return FolderMoveContext(base: base, destination: destination)
    }

    private func folderDeleteContext(id: String, input: NotesFolderDeleteInput) throws -> FolderMutationContext {
        let context = try folderMutationContext(id: id, expectedNameHash: input.expectedNameSHA256)
        guard opaqueParentID(context.folder, snapshot: context.snapshot) == input.expectedParentFolderID else {
            throw NotesError.folderConcurrencyConflict
        }
        guard !context.snapshot.folders.contains(where: { $0.parentScriptingID == context.folder.scriptingID }) else {
            throw NotesError.folderNotEmpty
        }
        let current: NotesFolderMutationDescriptor
        do {
            current = try folderMutationBridge.read(folderScriptingID: context.folder.scriptingID)
        } catch {
            throw mapMutationError(error)
        }
        guard current.accountScriptingID == context.folder.accountScriptingID,
              current.parentScriptingID == context.folder.parentScriptingID,
              NotesWritePolicy.sha256(current.name) == input.expectedNameSHA256 else {
            throw NotesError.folderConcurrencyConflict
        }
        guard !current.shared else { throw NotesError.sharedTarget }
        guard current.directNoteCount == 0, current.directChildFolderCount == 0 else {
            throw NotesError.folderNotEmpty
        }
        return context
    }

    private func loadCompleteFolderSnapshot() throws -> NotesMetadataSnapshot {
        let snapshot = try loadSnapshot()
        guard snapshot.complete else { throw NotesError.incompleteFolderGraph }
        return snapshot
    }

    private func requiredBinding(in snapshot: NotesMetadataSnapshot) throws -> NotesWriteAccountBinding {
        guard let binding = try writeAccountStore.load() else { throw NotesError.writeAccountNotBound }
        guard snapshot.accounts.contains(where: { NotesOpaqueID.account(scriptingID: $0.scriptingID) == binding.accountID }) else {
            throw NotesError.writeAccountStale
        }
        return binding
    }

    private func boundAccount(_ accountID: String, in snapshot: NotesMetadataSnapshot) throws -> NotesAccountDescriptor {
        guard let account = snapshot.accounts.first(where: { NotesOpaqueID.account(scriptingID: $0.scriptingID) == accountID }) else {
            throw NotesError.writeAccountStale
        }
        return account
    }

    private func folderByOpaqueID(_ id: String, in snapshot: NotesMetadataSnapshot) -> NotesFolderDescriptor? {
        snapshot.folders.first {
            NotesOpaqueID.folder(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID) == id
        }
    }

    private func resolveFolderParent(_ id: String?, boundAccountID: String, snapshot: NotesMetadataSnapshot) throws -> NotesFolderDescriptor? {
        guard let id else { return nil }
        guard NotesOpaqueID.isFolder(id), let folder = folderByOpaqueID(id, in: snapshot) else { throw NotesError.invalidIdentifier }
        guard NotesOpaqueID.account(scriptingID: folder.accountScriptingID) == boundAccountID else { throw NotesError.writeAccountMismatch }
        guard !folder.shared else { throw NotesError.sharedTarget }
        try rejectDefaultFolder(folder, snapshot: snapshot)
        return folder
    }

    private func rejectDefaultFolder(_ folder: NotesFolderDescriptor, snapshot: NotesMetadataSnapshot) throws {
        if snapshot.accounts.contains(where: { $0.scriptingID == folder.accountScriptingID && $0.defaultFolderScriptingID == folder.scriptingID }) {
            throw NotesError.defaultFolderTarget
        }
    }

    private func rejectDuplicateFolderName(
        _ name: String,
        parentScriptingID: String?,
        excluding excludedScriptingID: String?,
        snapshot: NotesMetadataSnapshot,
        accountScriptingID: String? = nil
    ) throws {
        let inferredAccount = accountScriptingID ?? parentScriptingID.flatMap { parent in
            snapshot.folders.first(where: { $0.scriptingID == parent })?.accountScriptingID
        }
        guard let inferredAccount else { throw NotesError.writeAccountMismatch }
        if snapshot.folders.contains(where: {
            $0.accountScriptingID == inferredAccount
                && $0.parentScriptingID == parentScriptingID
                && $0.scriptingID != excludedScriptingID
                && NotesWritePolicy.folderNamesEqual($0.name, name)
        }) { throw NotesError.duplicateFolderName }
    }

    private func opaqueParentID(_ folder: NotesFolderDescriptor, snapshot: NotesMetadataSnapshot) -> String? {
        folder.parentScriptingID.flatMap { parent in
            snapshot.folders.first(where: { $0.scriptingID == parent }).map {
                NotesOpaqueID.folder(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID)
            }
        }
    }

    private func revalidateFolder(_ context: FolderMutationContext) throws {
        let current: NotesFolderMutationDescriptor
        do { current = try folderMutationBridge.read(folderScriptingID: context.folder.scriptingID) }
        catch NotesMetadataBridgeError.automationDenied { throw NotesError.permissionDenied }
        catch NotesMetadataBridgeError.targetNotRunning { throw NotesError.targetNotRunning }
        catch NotesMetadataBridgeError.timedOut { throw NotesError.timedOut }
        catch { throw NotesError.executionFailed }
        guard !current.shared else { throw NotesError.sharedTarget }
        guard current.accountScriptingID == context.folder.accountScriptingID,
              current.parentScriptingID == context.folder.parentScriptingID,
              NotesWritePolicy.sha256(current.name) == context.expectedNameHash else {
            throw NotesError.folderConcurrencyConflict
        }
    }

    private func mutationContext(id: String, expected: Date) throws -> MutationContext {
        guard NotesOpaqueID.isNote(id) else { throw NotesError.invalidIdentifier }
        let binding = try requiredBinding()
        let note = try resolveNote(id)
        guard NotesOpaqueID.account(scriptingID: note.accountScriptingID) == binding.accountID else { throw NotesError.writeAccountMismatch }
        guard !note.shared else { throw NotesError.sharedTarget }
        guard !note.passwordProtected else { throw NotesError.lockedNote }
        guard let actual = note.modificationDate, NotesWritePolicy.modificationDatesMatch(expected, actual) else { throw NotesError.concurrencyConflict }
        return MutationContext(note: note, accountID: binding.accountID, folderID: NotesOpaqueID.folder(accountScriptingID: note.accountScriptingID, scriptingID: note.folderScriptingID))
    }

    private func revalidateNoteForDelete(_ context: MutationContext, expected: Date) throws -> NotesMutationDescriptor {
        let current: NotesMutationDescriptor
        do { current = try mutationBridge.read(noteScriptingID: context.note.scriptingID) }
        catch NotesMetadataBridgeError.automationDenied { throw NotesError.permissionDenied }
        catch NotesMetadataBridgeError.targetNotRunning { throw NotesError.targetNotRunning }
        catch NotesMetadataBridgeError.timedOut { throw NotesError.timedOut }
        catch { throw NotesError.executionFailed }
        guard current.accountScriptingID == context.note.accountScriptingID,
              current.folderScriptingID == context.note.folderScriptingID,
              NotesWritePolicy.sha256(current.title) == NotesWritePolicy.sha256(context.note.title),
              let actual = current.modificationDate,
              NotesWritePolicy.modificationDatesMatch(expected, actual) else {
            throw NotesError.concurrencyConflict
        }
        guard !current.shared else { throw NotesError.sharedTarget }
        guard !current.passwordProtected else { throw NotesError.lockedNote }
        return current
    }

    private func bodyEditContext(id: String, input: NotesEditBodyInput) throws -> BodyEditContext {
        try NotesWritePolicy.validateBodyEditInput(input)
        let mutation = try mutationContext(id: id, expected: input.expectedModificationDate)
        let current: NotesMutationDescriptor
        do {
            current = try mutationBridge.read(noteScriptingID: mutation.note.scriptingID)
        } catch NotesMetadataBridgeError.automationDenied {
            throw NotesError.permissionDenied
        } catch NotesMetadataBridgeError.targetNotRunning {
            throw NotesError.targetNotRunning
        } catch NotesMetadataBridgeError.timedOut {
            throw NotesError.timedOut
        } catch {
            throw NotesError.executionFailed
        }
        guard let actual = current.modificationDate,
              NotesWritePolicy.modificationDatesMatch(input.expectedModificationDate, actual) else {
            throw NotesError.concurrencyConflict
        }
        guard current.accountScriptingID == mutation.note.accountScriptingID,
              current.folderScriptingID == mutation.note.folderScriptingID else {
            throw NotesError.concurrencyConflict
        }

        let attachments: NotesAttachmentSnapshot
        do {
            attachments = try attachmentBridge.snapshot(scriptingID: current.scriptingID, maximumAttachments: 1)
        } catch NotesMetadataBridgeError.automationDenied {
            throw NotesError.permissionDenied
        } catch NotesMetadataBridgeError.targetNotRunning {
            throw NotesError.targetNotRunning
        } catch NotesMetadataBridgeError.timedOut {
            throw NotesError.timedOut
        } catch {
            throw NotesError.executionFailed
        }
        guard attachments.complete, attachments.attachments.isEmpty,
              NotesWritePolicy.isSafeReplaceableHTML(current.html) else {
            throw NotesError.unsupportedRichContent
        }

        let currentHash = NotesWritePolicy.sha256(current.plaintext)
        guard currentHash == input.expectedBodySHA256 else { throw NotesError.bodyHashConflict }
        let prepared = try NotesWritePolicy.prepareBodyEdit(input, title: current.title)
        return BodyEditContext(mutation: mutation, current: current, currentBodySHA256: currentHash, prepared: prepared)
    }

    private func requiredBinding() throws -> NotesWriteAccountBinding {
        guard let binding = try writeAccountStore.load() else { throw NotesError.writeAccountNotBound }
        let snapshot = try loadSnapshot()
        guard snapshot.accounts.contains(where: { NotesOpaqueID.account(scriptingID: $0.scriptingID) == binding.accountID }) else { throw NotesError.writeAccountStale }
        return binding
    }

    private func resolveWritableFolder(_ id: String, boundAccountID: String) throws -> NotesFolderDescriptor {
        let snapshot = try loadSnapshot()
        guard let folder = snapshot.folders.first(where: { NotesOpaqueID.folder(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID) == id }) else { throw NotesError.invalidIdentifier }
        guard NotesOpaqueID.account(scriptingID: folder.accountScriptingID) == boundAccountID else { throw NotesError.writeAccountMismatch }
        guard !folder.shared else { throw NotesError.sharedTarget }
        return folder
    }

    private func resolveNote(_ id: String) throws -> NotesMutationDescriptor {
        let snapshot: NotesQuerySnapshot
        do { snapshot = try queryBridge.snapshot(maximumNotes: SystemNotesQueryBridge.maximumNotes) }
        catch { throw mapMutationError(error) }
        guard let note = snapshot.notes.first(where: { NotesOpaqueID.note(accountScriptingID: $0.accountScriptingID, scriptingID: $0.scriptingID) == id }) else { throw NotesError.invalidIdentifier }
        return NotesMutationDescriptor(scriptingID: note.scriptingID, accountScriptingID: note.accountScriptingID, folderScriptingID: note.folderScriptingID, title: note.title, html: "", modificationDate: note.modificationDate, passwordProtected: note.passwordProtected, shared: note.shared)
    }

    private func result(operation: String, descriptor: NotesMutationDescriptor, previousNoteID: String?, changed: Bool, verification: NotesWriteVerification, deduplicated: Bool, titleHash: String?, bodyHash: String? = nil, bodyBytes: Int? = nil, nextAction: String? = nil) -> NotesWriteResult {
        let id = NotesOpaqueID.note(accountScriptingID: descriptor.accountScriptingID, scriptingID: descriptor.scriptingID)
        let accountID = NotesOpaqueID.account(scriptingID: descriptor.accountScriptingID)
        let folderID = NotesOpaqueID.folder(accountScriptingID: descriptor.accountScriptingID, scriptingID: descriptor.folderScriptingID)
        return NotesWriteResult(operation: operation, changed: changed, verification: verification, noteID: id, previousNoteID: previousNoteID, accountID: accountID, folderID: folderID, modificationDate: descriptor.modificationDate, titleSHA256: titleHash, bodySHA256: bodyHash, bodyBytes: bodyBytes, identityChanged: previousNoteID.map { $0 != id }, deduplicated: deduplicated, nextAction: nextAction)
    }

    private func folderResult(operation: String, descriptor: NotesFolderMutationDescriptor, previousFolderID: String?, changed: Bool, verification: NotesWriteVerification, deduplicated: Bool, nameHash: String, nextAction: String? = nil) -> NotesFolderWriteResult {
        let folderID = NotesOpaqueID.folder(accountScriptingID: descriptor.accountScriptingID, scriptingID: descriptor.scriptingID)
        let accountID = NotesOpaqueID.account(scriptingID: descriptor.accountScriptingID)
        let parentID = descriptor.parentScriptingID.map {
            NotesOpaqueID.folder(accountScriptingID: descriptor.accountScriptingID, scriptingID: $0)
        }
        return NotesFolderWriteResult(
            operation: operation, changed: changed, verification: verification,
            folderID: folderID, previousFolderID: previousFolderID,
            accountID: accountID, parentFolderID: parentID, nameSHA256: nameHash,
            identityChanged: previousFolderID.map { $0 != folderID },
            deduplicated: deduplicated, nextAction: nextAction
        )
    }

    private func unknownFolderResult(operation: String, context: FolderMutationContext, nameHash: String) -> NotesFolderWriteResult {
        let folderID = NotesOpaqueID.folder(accountScriptingID: context.folder.accountScriptingID, scriptingID: context.folder.scriptingID)
        return NotesFolderWriteResult(
            operation: operation, changed: false, verification: .outcomeUnknown,
            folderID: folderID, accountID: context.accountID,
            parentFolderID: opaqueParentID(context.folder, snapshot: context.snapshot),
            nameSHA256: nameHash,
            nextAction: "The folder Apple Event timed out. Do not retry automatically; list folders and verify first."
        )
    }

    private func unknownResult(operation: String, context: MutationContext, titleHash: String) -> NotesWriteResult {
        NotesWriteResult(operation: operation, changed: false, verification: .outcomeUnknown, noteID: NotesOpaqueID.note(accountScriptingID: context.note.accountScriptingID, scriptingID: context.note.scriptingID), previousNoteID: nil, accountID: context.accountID, folderID: context.folderID, modificationDate: context.note.modificationDate, titleSHA256: titleHash, nextAction: "The Apple Event timed out. Do not retry automatically; query and verify first.")
    }

    private func mapMutationError(_ error: Error) -> NotesError {
        switch error {
        case let notesError as NotesError: notesError
        case NotesMetadataBridgeError.automationDenied: .permissionDenied
        case NotesMetadataBridgeError.targetNotRunning: .targetNotRunning
        case NotesMetadataBridgeError.timedOut: .writeOutcomeUnknown
        default: .executionFailed
        }
    }

    private func loadSnapshot() throws -> NotesMetadataSnapshot {
        try requirePermission()
        do {
            let snapshot = try bridge.snapshot(
                maximumAccounts: SystemNotesMetadataBridge.maximumAccounts,
                maximumFolders: SystemNotesMetadataBridge.maximumFolders
            )
            return try SystemNotesMetadataBridge.validateSnapshot(snapshot)
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

private extension NotesFolderDescriptor {
    var mutationDescriptor: NotesFolderMutationDescriptor {
        NotesFolderMutationDescriptor(
            scriptingID: scriptingID,
            accountScriptingID: accountScriptingID,
            parentScriptingID: parentScriptingID,
            name: name,
            shared: shared
        )
    }
}
