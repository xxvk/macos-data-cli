import Foundation
import Core
import Contacts
import ContactsAdapter
import MailAdapter
import CalendarAdapter
import RemindersAdapter
import PhotosAdapter
import NotesAdapter
@_spi(ShortcutsFixtureGate) import ShortcutsAdapter
import SafariAdapter

@main
struct MpiaCLI {
    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let jsonRequested = rawArguments.contains("--format") && rawArguments.contains("json")
        var arguments = rawArguments.filter { $0 != "--format" && $0 != "json" }
        var containerSelector: String?
        if let index = arguments.firstIndex(of: "--container") {
            guard index + 1 < arguments.count else {
                report(error: "--container requires iCloud or a container identifier", code: CLIErrorCode.invalidQuery.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            containerSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        var calendarSourceSelector: String?
        if arguments.first == "calendar", let index = arguments.firstIndex(of: "--source") {
            guard index + 1 < arguments.count else {
                report(error: "--source requires iCloud or a source identifier", code: CLIErrorCode.calendar.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            calendarSourceSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        var remindersSourceSelector: String?
        if arguments.first == "reminders", let index = arguments.firstIndex(of: "--source") {
            guard index + 1 < arguments.count else {
                report(error: "--source requires iCloud or a source identifier", code: CLIErrorCode.reminders.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
            remindersSourceSelector = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        if arguments.isEmpty || arguments == ["--help"] || arguments == ["contacts", "--help"] || arguments == ["mail", "--help"] || arguments == ["calendar", "--help"] || arguments == ["reminders", "--help"] || arguments == ["photos", "--help"] || arguments == ["notes", "--help"] || arguments == ["shortcuts", "--help"] || arguments == ["safari", "--help"] {
            printHelp()
            return
        }

        if arguments == ["--version"] || arguments == ["-v"] {
            print(CLIVersion.current)
            return
        }

        do {
            let permission = ContactsPermission()
            let store = ContactsStore(permission: permission, containerSelector: containerSelector)
            let calendarPermission = CalendarPermission()
            let calendarStore = CalendarStore(permission: calendarPermission, sourceSelector: calendarSourceSelector)
            let remindersPermission = RemindersPermission()
            let remindersStore = RemindersStore(permission: remindersPermission, sourceSelector: remindersSourceSelector)
            let photosPermission = PhotosPermission()
            let photosStore = PhotosStore(permission: photosPermission)
            let notesPermission = NotesPermissionService()
            let notesStore = NotesStore(permission: notesPermission)
            let shortcutsPermission = ShortcutsPermissionService()
            let shortcutsStore = ShortcutsStore(permission: shortcutsPermission)
            let shortcutsAuthoring = CherriAuthoringBridge()
            let shortcutsAuthoringService = ShortcutsAuthoringService(builder: shortcutsAuthoring)
            let shortcutsAcquisition = ShortcutAcquisitionClassifier()
            let shortcutsEditPlan = ShortcutEditPlanService()
            let shortcutsSemanticEdit = ShortcutSemanticEditService()
            let shortcutsAccessibilityDiscovery = ShortcutAccessibilityDiscoveryService()
            let safariPermission = SafariPermissionService()
            let safariStore = SafariStore()
            switch arguments {
            case ["manifest"]:
                emitJSONSuccess(CommandRegistry.standard(version: CLIVersion.current))
            case ["resources"]:
                emitJSONSuccess(makeResourcesResult(
                    permission: permission,
                    store: store,
                    calendarPermission: calendarPermission,
                    calendarStore: calendarStore,
                    remindersPermission: remindersPermission,
                    remindersStore: remindersStore,
                    photosPermission: photosPermission,
                    notesPermission: notesPermission,
                    notesStore: notesStore,
                    shortcutsPermission: shortcutsPermission,
                    safariPermission: safariPermission
                ))
            case ["safari", "permission"]:
                emitSafariJSONSuccess(safariPermission.check(requestConsent: false))
            case ["safari", "permission", "--request"]:
                let result = safariPermission.check(requestConsent: true)
                emitSafariJSONSuccess(result)
                if result.automation != .available { Foundation.exit(CLIExitCode.safariFailure.rawValue) }
            case let args where args.count >= 3 && args[0] == "safari" && args[1] == "bookmarks" && ["list", "query"].contains(args[2]):
                let request = try parseSafariBookmarkPageArguments(Array(args.dropFirst(3)))
                emitSafariJSONSuccess(try safariStore.bookmarks(query: request.query, limit: request.limit, cursor: request.cursor))
            case let args where args.count == 5 && args[0] == "safari" && args[1] == "bookmarks" && args[2] == "get" && args[3] == "--id":
                emitSafariJSONSuccess(try safariStore.bookmark(id: args[4]))
            case let args where args.count >= 3 && args[0] == "safari" && ["bookmarks", "folders"].contains(args[1]) && ["create", "edit", "rename", "move", "delete"].contains(args[2]):
                let command = try safariLocalMutationCommand(collection: args[1], action: args[2])
                let request = try parseSafariLocalMutationArguments(Array(args.dropFirst(3)))
                let input = try SafariLocalMutationInput.decode(request.data, command: command)
                emitSafariJSONSuccess(try safariStore.mutateLocally(input, apply: request.apply, confirmation: request.confirmation))
            case let args where args.count >= 3 && args[0] == "safari" && args[1] == "reading-list" && ["list", "query"].contains(args[2]):
                let request = try parseSafariReadingListPageArguments(Array(args.dropFirst(3)))
                emitSafariJSONSuccess(try safariStore.readingList(query: request.query, limit: request.limit, cursor: request.cursor))
            case let args where args.count == 5 && args[0] == "safari" && args[1] == "reading-list" && args[2] == "get" && args[3] == "--id":
                emitSafariJSONSuccess(try safariStore.readingListItem(id: args[4]))
            case let args where args.count >= 3 && args[0] == "safari" && args[1] == "reading-list" && args[2] == "add":
                let request = try parseSafariReadingListAddArguments(Array(args.dropFirst(3)))
                emitSafariJSONSuccess(try safariStore.addReadingList(SafariReadingListAddInput.decode(request.data), apply: request.apply))
            case ["shortcuts", "permission"]:
                emitJSONSuccess(shortcutsPermission.check(requestConsent: false))
            case ["shortcuts", "permission", "--request"]:
                let result = shortcutsPermission.check(requestConsent: true)
                emitJSONSuccess(result)
                if !result.readable { Foundation.exit(CLIExitCode.shortcutsFailure.rawValue) }
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "edit" && args[2] == "inspect":
                let inputURL = try parseShortcutAcquisitionArguments(Array(args.dropFirst(3)))
                emitJSONSuccess(try shortcutsAcquisition.inspect(inputURL: inputURL))
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "edit" && args[2] == "plan":
                let request = try parseShortcutEditPlanArguments(Array(args.dropFirst(3)))
                let result = request.patchURL != nil
                    ? try shortcutsEditPlan.plan(inputURL: request.inputURL, patchURL: request.patchURL!)
                    : try shortcutsEditPlan.plan(inputURL: request.inputURL, patchData: FileHandle.standardInput.readDataToEndOfFile())
                emitJSONSuccess(result)
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "edit" && args[2] == "copy":
                let request = try parseShortcutSemanticEditArguments(Array(args.dropFirst(3)))
                let result = request.patchURL != nil
                    ? try shortcutsSemanticEdit.execute(
                        inputURL: request.inputURL,
                        patchURL: request.patchURL!,
                        expectedEditorNameSHA256: request.expectedEditorNameSHA256,
                        apply: request.apply,
                        confirmation: request.confirmation
                    )
                    : try shortcutsSemanticEdit.execute(
                        inputURL: request.inputURL,
                        patchData: FileHandle.standardInput.readDataToEndOfFile(),
                        expectedEditorNameSHA256: request.expectedEditorNameSHA256,
                        apply: request.apply,
                        confirmation: request.confirmation
                    )
                emitJSONSuccess(result)
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "edit" && args[2] == "ui-inspect":
                guard args.count == 3 else { throw ShortcutsError.editPlanInvalid }
                emitJSONSuccess(shortcutsAccessibilityDiscovery.inspect())
#if DEBUG
            case ["shortcuts", "edit", "_ax-fixture-gate"]:
                let environment = ProcessInfo.processInfo.environment
                guard let mode = environment["MPIA_SHORTCUTS_AX_FIXTURE_GATE"],
                      let nameHash = environment["MPIA_SHORTCUTS_AX_NAME_SHA256"],
                      let textHash = environment["MPIA_SHORTCUTS_AX_TEXT_SHA256"],
                      let commentHash = environment["MPIA_SHORTCUTS_AX_COMMENT_SHA256"],
                      let confirmation = environment["MPIA_SHORTCUTS_AX_CONFIRM"] else {
                    throw ShortcutsError.editConfirmationRequired
                }
                if mode == "copy-delete" {
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().deleteCommentFromCopy(
                        expectedNameSHA256: nameHash,
                        expectedTextSHA256: textHash,
                        expectedCommentSHA256: commentHash,
                        confirmation: confirmation
                    ))
                } else if mode == "copy-move" {
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().moveCommentBeforeTextFromCopy(
                        expectedNameSHA256: nameHash,
                        expectedTextSHA256: textHash,
                        expectedCommentSHA256: commentHash,
                        confirmation: confirmation
                    ))
                } else if mode == "copy-delete-readback" {
                    guard let copyNameHash = environment["MPIA_SHORTCUTS_AX_COPY_NAME_SHA256"] else {
                        throw ShortcutsError.editConfirmationRequired
                    }
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().verifyExistingDeletedCopy(
                        expectedOriginalNameSHA256: nameHash,
                        expectedCopyNameSHA256: copyNameHash,
                        expectedTextSHA256: textHash,
                        confirmation: confirmation
                    ))
                } else if mode == "copy-move-readback" {
                    guard let copyNameHash = environment["MPIA_SHORTCUTS_AX_COPY_NAME_SHA256"] else {
                        throw ShortcutsError.editConfirmationRequired
                    }
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().verifyExistingMovedCopy(
                        expectedOriginalNameSHA256: nameHash,
                        expectedCopyNameSHA256: copyNameHash,
                        expectedTextSHA256: textHash,
                        expectedCommentSHA256: commentHash,
                        confirmation: confirmation
                    ))
                } else {
                    guard mode == "copy-replace",
                          let replacement = environment["MPIA_SHORTCUTS_AX_REPLACEMENT"] else {
                        throw ShortcutsError.editConfirmationRequired
                    }
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().mutateCopy(
                        expectedNameSHA256: nameHash,
                        expectedTextSHA256: textHash,
                        expectedCommentSHA256: commentHash,
                        replacement: replacement,
                        confirmation: confirmation
                    ))
                }
            case ["shortcuts", "edit", "_ax-fixture-verify-original"]:
                let environment = ProcessInfo.processInfo.environment
                guard environment["MPIA_SHORTCUTS_AX_FIXTURE_GATE"] == "verify-original",
                      let nameHash = environment["MPIA_SHORTCUTS_AX_NAME_SHA256"],
                      let textHash = environment["MPIA_SHORTCUTS_AX_TEXT_SHA256"],
                      let commentHash = environment["MPIA_SHORTCUTS_AX_COMMENT_SHA256"] else {
                    throw ShortcutsError.editConfirmationRequired
                }
                emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().verifyOriginal(
                    expectedNameSHA256: nameHash,
                    expectedTextSHA256: textHash,
                    expectedCommentSHA256: commentHash
                ))
            case ["shortcuts", "edit", "_ax-fixture-resume-copy"]:
                let environment = ProcessInfo.processInfo.environment
                guard let mode = environment["MPIA_SHORTCUTS_AX_FIXTURE_GATE"],
                      let originalNameHash = environment["MPIA_SHORTCUTS_AX_NAME_SHA256"],
                      let copyNameHash = environment["MPIA_SHORTCUTS_AX_COPY_NAME_SHA256"],
                      let textHash = environment["MPIA_SHORTCUTS_AX_TEXT_SHA256"],
                      let commentHash = environment["MPIA_SHORTCUTS_AX_COMMENT_SHA256"],
                      let confirmation = environment["MPIA_SHORTCUTS_AX_CONFIRM"] else {
                    throw ShortcutsError.editConfirmationRequired
                }
                if mode == "resume-copy-move" {
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().resumeExistingCopyMove(
                        expectedOriginalNameSHA256: originalNameHash,
                        expectedCopyNameSHA256: copyNameHash,
                        expectedTextSHA256: textHash,
                        expectedCommentSHA256: commentHash,
                        confirmation: confirmation
                    ))
                } else {
                    guard mode == "resume-copy-replace",
                          let replacement = environment["MPIA_SHORTCUTS_AX_REPLACEMENT"] else {
                        throw ShortcutsError.editConfirmationRequired
                    }
                    emitJSONSuccess(try ShortcutAXReplaceTextFixtureGate().resumeExistingCopy(
                        expectedOriginalNameSHA256: originalNameHash,
                        expectedCopyNameSHA256: copyNameHash,
                        expectedTextSHA256: textHash,
                        expectedCommentSHA256: commentHash,
                        replacement: replacement,
                        confirmation: confirmation
                    ))
                }
#endif
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "author" && args[2] == "validate":
                let request = try parseShortcutAuthorArguments(Array(args.dropFirst(3)), build: false)
                emitJSONSuccess(try shortcutsAuthoring.validate(sourceURL: request.sourceURL))
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "author" && args[2] == "build":
                let request = try parseShortcutAuthorArguments(Array(args.dropFirst(3)), build: true)
                emitJSONSuccess(try shortcutsAuthoring.build(sourceURL: request.sourceURL, outputURL: request.outputURL!, signingMode: request.signingMode))
            case let args where args.count >= 2 && args[0] == "shortcuts" && args[1] == "create":
                let request = try parseShortcutCreateArguments(Array(args.dropFirst(2)))
                emitJSONSuccess(try shortcutsAuthoringService.create(sourceURL: request.sourceURL, signingMode: request.signingMode, apply: request.apply, idempotent: request.idempotent))
            case let args where args.count >= 2 && args[0] == "shortcuts" && args[1] == "update":
                let request = try parseShortcutUpdateArguments(Array(args.dropFirst(2)))
                emitJSONSuccess(try shortcutsAuthoringService.update(id: request.id, sourceURL: request.sourceURL, expectedSourceSHA256: request.expectedSourceSHA256, strategy: request.strategy, signingMode: request.signingMode, apply: request.apply))
            case ["shortcuts", "managed", "list"]:
                emitJSONSuccess(try shortcutsAuthoringService.managedRecords())
            case let args where args.count >= 3 && args[0] == "shortcuts" && args[1] == "managed" && args[2] == "forget":
                let request = try parseShortcutManagedForgetArguments(Array(args.dropFirst(3)))
                emitJSONSuccess(try shortcutsAuthoringService.forgetManaged(id: request.id, apply: request.apply))
            case let args where args.count >= 2 && args[0] == "shortcuts" && args[1] == "list":
                let request = try parseShortcutsPageArguments(Array(args.dropFirst(2)), allowsFolder: true)
                emitJSONSuccess(try shortcutsStore.list(limit: request.limit, cursor: request.cursor, folderID: request.folderID))
            case let args where args.count >= 2 && args[0] == "shortcuts" && args[1] == "folders":
                let request = try parseShortcutsPageArguments(Array(args.dropFirst(2)), allowsFolder: false)
                emitJSONSuccess(try shortcutsStore.folders(limit: request.limit, cursor: request.cursor))
            case let args where args.count == 4 && args[0] == "shortcuts" && args[1] == "get" && args[2] == "--id":
                emitJSONSuccess(try shortcutsStore.get(id: args[3]))
            case let args where args.count >= 2 && args[0] == "shortcuts" && args[1] == "run":
                let request = try parseShortcutRunArguments(Array(args.dropFirst(2)))
                emitJSONSuccess(try shortcutsStore.run(
                    id: request.id,
                    inputPaths: request.inputPaths,
                    outputPath: request.outputPath,
                    outputType: request.outputType,
                    timeoutSeconds: request.timeoutSeconds
                ))
            case let args where args.count >= 2 && args[0] == "shortcuts" && args[1] == "move":
                let request = try parseShortcutMoveArguments(Array(args.dropFirst(2)))
                emitJSONSuccess(try shortcutsStore.move(id: request.id, destinationFolderID: request.destinationFolderID, apply: request.apply))
            case ["notes", "permission"]:
                emitJSONSuccess(notesPermission.check(requestConsent: false))
            case ["notes", "permission", "--request"]:
                let result = notesPermission.check(requestConsent: true)
                emitJSONSuccess(result)
                if !result.readable { Foundation.exit(CLIExitCode.notesFailure.rawValue) }
            case ["notes", "accounts"]:
                emitJSONSuccess(try notesStore.accounts())
            case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "create":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "create", requiresID: false)
                let input: NotesFolderCreateInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.createFolder(input, idempotent: request.idempotent)) }
                else { emitNotesJSONSuccess(try notesStore.previewCreateFolder(input)) }
            case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "rename":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "rename", requiresID: true)
                let input: NotesFolderRenameInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.renameFolder(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewRenameFolder(id: request.id!, input: input)) }
            case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "move":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "move", requiresID: true)
                let input: NotesFolderMoveInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.moveFolder(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewMoveFolder(id: request.id!, input: input)) }
            case let args where args.count >= 3 && args[0] == "notes" && args[1] == "folder" && args[2] == "delete":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(3)), command: "folder-delete", requiresID: true)
                let input: NotesFolderDeleteInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.deleteFolder(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewDeleteFolder(id: request.id!, input: input)) }
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "folders":
                let request = try parseNotesFolderArguments(Array(args.dropFirst(2)))
                emitJSONSuccess(try notesStore.folders(
                    limit: request.limit,
                    cursor: request.cursor,
                    accountID: request.accountID,
                    parentID: request.parentID
                ))
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "query":
                emitNotesJSONSuccess(try notesStore.query(parseNotesQueryArguments(Array(args.dropFirst(2)))))
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "get":
                let request = try parseNotesGetArguments(Array(args.dropFirst(2)))
                emitNotesJSONSuccess(try notesStore.get(id: request.id, bodyFormat: request.bodyFormat, includeAttachments: request.includeAttachments))
            case ["notes", "write-account", "status"]:
                emitNotesJSONSuccess(notesStore.writeAccountStatus())
            case let args where args.count >= 3 && args[0] == "notes" && args[1] == "write-account" && args[2] == "bind":
                let request = try parseNotesWriteAccountArguments(Array(args.dropFirst(3)), clear: false)
                emitNotesJSONSuccess(try notesStore.changeWriteAccount(accountID: request.accountID, clear: false, apply: request.apply))
            case let args where args.count >= 3 && args[0] == "notes" && args[1] == "write-account" && args[2] == "clear":
                let request = try parseNotesWriteAccountArguments(Array(args.dropFirst(3)), clear: true)
                emitNotesJSONSuccess(try notesStore.changeWriteAccount(accountID: nil, clear: true, apply: request.apply))
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "create":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "create", requiresID: false)
                let input: NotesCreateInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.create(input, idempotent: request.idempotent)) }
                else { emitNotesJSONSuccess(try notesStore.previewCreate(input)) }
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "rename":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "rename", requiresID: true)
                let input: NotesRenameInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.rename(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewRename(id: request.id!, input: input)) }
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "move":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "move", requiresID: true)
                let input: NotesMoveInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.move(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewMove(id: request.id!, input: input)) }
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "delete":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "delete", requiresID: true)
                let input: NotesDeleteInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.delete(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewDelete(id: request.id!, input: input)) }
            case let args where args.count >= 2 && args[0] == "notes" && args[1] == "edit-body":
                let request = try parseNotesMutationArguments(Array(args.dropFirst(2)), command: "edit-body", requiresID: true)
                let input: NotesEditBodyInput = try decodeNotesWrite(request.data)
                if request.apply { emitNotesJSONSuccess(try notesStore.editBody(id: request.id!, input: input)) }
                else { emitNotesJSONSuccess(try notesStore.previewEditBody(id: request.id!, input: input)) }
            case ["photos", "permission"]:
                emitJSONSuccess(PhotosPermissionResult(
                    access: photosPermission.status.rawValue,
                    readable: photosPermission.status.canRead,
                    complete: photosPermission.status.complete,
                    requested: false
                ))
            case ["photos", "permission", "--request"]:
                let status = await photosPermission.requestReadWriteAccess()
                emitJSONSuccess(PhotosPermissionResult(
                    access: status.rawValue,
                    readable: status.canRead,
                    complete: status.complete,
                    requested: true
                ))
                if !status.canRead { Foundation.exit(CLIExitCode.photosFailure.rawValue) }
            case let args where args.count >= 2 && args[0] == "photos" && args[1] == "albums":
                let request = try parsePhotoAlbumArguments(Array(args.dropFirst(2)))
                emitJSONSuccess(try photosStore.albums(kind: request.kind, limit: request.limit, cursor: request.cursor))
            case let args where args.count >= 2 && args[0] == "photos" && args[1] == "query":
                emitPhotosJSONSuccess(try photosStore.query(parsePhotoQueryArguments(Array(args.dropFirst(2)))))
            case let args where args.count >= 2 && args[0] == "photos" && args[1] == "get":
                let request = try parsePhotoGetArguments(Array(args.dropFirst(2)))
                emitPhotosJSONSuccess(try photosStore.get(id: request.id, includeLocation: request.includeLocation))
            case let args where args.count >= 2 && args[0] == "photos" && args[1] == "export":
                let request = try parsePhotoExportArguments(Array(args.dropFirst(2)))
                emitPhotosJSONSuccess(try await photosStore.export(
                    id: request.id,
                    outputURL: request.outputURL,
                    variant: request.variant,
                    allowNetwork: request.allowNetwork
                ))
            case ["calendar", "permission"]:
                let granted = try await calendarPermission.requestFullAccess()
                if jsonRequested { emitJSONSuccess(CalendarPermissionResult(granted: granted, access: calendarPermission.status.rawValue)) }
                else { print(granted ? "Calendar full access granted." : "Calendar full access not granted.") }
                if !granted { Foundation.exit(CLIExitCode.calendarFailure.rawValue) }
            case ["calendar", "sources"]:
                emitJSONSuccess(try calendarStore.sourceDescriptions())
            case ["calendar", "calendars"]:
                emitJSONSuccess(try calendarStore.calendarDescriptions())
            case let args where args.count >= 2 && args[0] == "calendar" && args[1] == "query":
                emitCalendarJSONSuccess(try calendarStore.query(parseCalendarQuery(Array(args.dropFirst(2)))))
            case let args where args.count >= 2 && args[0] == "calendar" && args[1] == "conflicts":
                emitCalendarJSONSuccess(try calendarStore.conflicts(parseCalendarConflicts(Array(args.dropFirst(2)))))
            case let args where args.count == 4 && args[0] == "calendar" && args[1] == "get" && args[2] == "--id":
                emitCalendarJSONSuccess(try calendarStore.get(id: args[3]))
            case let args where args.count >= 3 && args[0] == "calendar" && args[1] == "create":
                let request = try parseCalendarWriteArguments(Array(args.dropFirst(2)), command: "create", allowsSpan: false)
                let input: CalendarEventInput = try decodeCalendar(request.data)
                if request.idempotent {
                    let result = try calendarStore.createIdempotent(input, dryRun: request.mode == "--dry-run")
                    emitCalendarJSONSuccess(CalendarWriteResult(
                        operation: result.created ? (request.mode == "--dry-run" ? "create_preview" : "created") : "existing",
                        dryRun: request.mode == "--dry-run",
                        event: result.event
                    ))
                } else if request.mode == "--dry-run" {
                    emitCalendarJSONSuccess(CalendarWriteResult(operation: "create_preview", dryRun: true, event: try calendarStore.previewCreate(input)))
                } else {
                    emitCalendarJSONSuccess(CalendarWriteResult(operation: "created", dryRun: false, event: try calendarStore.create(input)))
                }
            case let args where args.count >= 5 && args[0] == "calendar" && args[1] == "edit" && args[2] == "--id":
                let id = args[3]
                let request = try parseCalendarWriteArguments(Array(args.dropFirst(4)), command: "edit", allowsSpan: true)
                let patch: CalendarEventPatch = try decodeCalendar(request.data)
                if request.mode == "--dry-run" {
                    let before = try calendarStore.get(id: id)
                    let after = try calendarStore.previewUpdate(id: id, patch: patch, span: request.span)
                    emitCalendarJSONSuccess(CalendarUpdatePreview(operation: "update_preview", dryRun: true, before: before, after: after))
                } else {
                    emitCalendarJSONSuccess(CalendarWriteResult(operation: "updated", dryRun: false, event: try calendarStore.update(id: id, patch: patch, span: request.span)))
                }
            case let args where args.count >= 5 && args[0] == "calendar" && args[1] == "delete" && args[2] == "--id":
                let request = try parseCalendarDeleteArguments(Array(args.dropFirst(4)))
                if request.apply {
                    emitCalendarJSONSuccess(CalendarWriteResult(operation: "deleted", dryRun: false, event: try calendarStore.delete(id: args[3], span: request.span)))
                } else {
                    emitCalendarJSONSuccess(CalendarWriteResult(operation: "delete_preview", dryRun: true, event: try calendarStore.previewDelete(id: args[3], span: request.span)))
                }
            case ["reminders", "permission"]:
                let granted = try await remindersPermission.requestFullAccess()
                if jsonRequested {
                    emitJSONSuccess(RemindersPermissionResult(granted: granted, access: remindersPermission.status.rawValue))
                } else {
                    print(granted ? "Reminders full access granted." : "Reminders full access not granted.")
                }
                if !granted { Foundation.exit(CLIExitCode.remindersFailure.rawValue) }
            case ["reminders", "sources"]:
                emitJSONSuccess(try remindersStore.sourceDescriptions())
            case ["reminders", "lists"]:
                emitJSONSuccess(try remindersStore.listDescriptions())
            case let args where args.count >= 2 && args[0] == "reminders" && args[1] == "query":
                emitRemindersJSONSuccess(try await remindersStore.query(parseReminderQuery(Array(args.dropFirst(2)))))
            case let args where args.count == 4 && args[0] == "reminders" && args[1] == "get" && args[2] == "--id":
                emitRemindersJSONSuccess(try remindersStore.get(id: args[3]))
            case let args where args.count >= 3 && args[0] == "reminders" && args[1] == "create":
                let request = try parseReminderCreateArguments(Array(args.dropFirst(2)))
                let input: ReminderInput = try decodeReminder(request.data)
                if request.mode == "--dry-run" {
                    emitRemindersJSONSuccess(try remindersStore.previewCreate(input))
                } else {
                    emitRemindersJSONSuccess(try remindersStore.create(input, idempotent: request.idempotent))
                }
            case let args where args.count >= 5 && args[0] == "reminders" && args[1] == "edit" && args[2] == "--id":
                let request = try parseReminderEditArguments(Array(args.dropFirst(4)))
                let patch: ReminderPatch = try decodeReminder(request.data)
                if request.mode == "--dry-run" {
                    emitRemindersJSONSuccess(try remindersStore.previewUpdate(id: args[3], patch: patch))
                } else {
                    emitRemindersJSONSuccess(try remindersStore.update(id: args[3], patch: patch))
                }
            case let args where args.count >= 4 && args[0] == "reminders" && ["complete", "reopen"].contains(args[1]) && args[2] == "--id":
                let action: ReminderStateAction = args[1] == "complete" ? .complete : .reopen
                let apply = try parseReminderStateArguments(Array(args.dropFirst(4)), command: args[1])
                if apply {
                    emitRemindersJSONSuccess(try remindersStore.changeState(id: args[3], action: action))
                } else {
                    emitRemindersJSONSuccess(try remindersStore.previewStateChange(id: args[3], action: action))
                }
            case let args where args.count >= 4 && args[0] == "reminders" && args[1] == "delete" && args[2] == "--id":
                let apply = try parseReminderDeleteArguments(Array(args.dropFirst(4)))
                if apply {
                    emitRemindersJSONSuccess(try remindersStore.delete(id: args[3]))
                } else {
                    emitRemindersJSONSuccess(try remindersStore.previewDelete(id: args[3]))
                }
            case ["mail", "doctor"]:
                emitJSONSuccess(MailDoctor().run())
            case ["mail", "accounts"]:
                emitJSONSuccess(try makeValidatedMailStore().accounts())
            case ["mail", "mailboxes"]:
                emitJSONSuccess(try makeValidatedMailStore().mailboxes())
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "threads":
                emitJSONSuccess(try makeValidatedMailStore().threads(limit: parseSimpleLimit(Array(args.dropFirst(2)))))
            case let args where args.count == 4 && args[0] == "mail" && args[1] == "mailboxes" && args[2] == "--account-id":
                emitJSONSuccess(try makeValidatedMailStore().mailboxes(accountID: args[3]))
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "query":
                emitJSONSuccess(try makeValidatedMailStore().query(parseMailQuery(Array(args.dropFirst(2)))))
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "search":
                let request = try parseMailTextSearch(Array(args.dropFirst(2)))
                emitJSONSuccess(try makeValidatedMailStore().searchText(request.text, query: request.query, resultLimit: request.limit))
            case let args where args.count >= 2 && args[0] == "mail" && args[1] == "get":
                let request = try parseMailGet(Array(args.dropFirst(2)), jsonRequested: jsonRequested)
                let mailStore = try makeValidatedMailStore()
                if request.projection == .raw {
                    let raw = try mailStore.rawMessage(id: request.id)
                    if request.output == "-" {
                        do { try FileHandle.standardOutput.write(contentsOf: raw.data) }
                        catch { throw MailStoreError.outputFailed }
                    } else {
                        guard let output = request.output else {
                            throw MailStoreError.invalidArgument("Raw content requires --output <file|->.")
                        }
                        do {
                            try raw.data.write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
                        } catch let error as CocoaError where error.code == .fileWriteFileExists {
                            throw MailStoreError.outputAlreadyExists
                        } catch {
                            throw MailStoreError.outputFailed
                        }
                        emitJSONSuccess(MailRawWriteResult(
                            backend: "sqlite_emlx",
                            cacheState: raw.cacheState,
                            id: raw.message.id,
                            output: "file",
                            bytesWritten: raw.data.count,
                            fallbackReason: raw.incomplete ? "partial_emlx" : nil,
                            incomplete: raw.incomplete,
                            limitations: raw.limitations
                        ))
                    }
                } else {
                    emitJSONSuccess(try mailStore.get(id: request.id, projection: request.projection))
                }
            case let args where args.count == 4 && args[0] == "mail" && args[1] == "reveal" && args[2] == "--id":
                emitJSONSuccess(try makeValidatedMailStore().reveal(id: args[3]))
            case let args where args.count == 5 && args[0] == "mail" && args[1] == "attachments" &&
                args[2] == "verify" && args[3] == "--id":
                emitJSONSuccess(try makeValidatedMailStore().verifyAttachments(id: args[4]))
            case let args where args.count == 7 && args[0] == "mail" && args[1] == "attachments" &&
                args[2] == "export" && args[3] == "--id" && args[5] == "--output":
                emitJSONSuccess(try makeValidatedMailStore().exportAttachments(id: args[4], directory: URL(fileURLWithPath: args[6])))
            case ["contacts", "permission"]:
                let granted = try await permission.requestAccess()
                print(granted ? "Contacts permission granted." : "Contacts permission not granted.")
                if !granted { Foundation.exit(2) }
            case ["contacts", "count"]:
                if jsonRequested { emitJSONSuccess(["count": try store.count()]) }
                else { print("{\"count\": \(try store.count())}") }
            case ["contacts", "containers"], ["contacts", "containers", "--format", "json"]:
                emitJSONSuccess(try store.containerDescriptions())
            case ["contacts", "container"]:
                let container = try store.selectedContainerDescription()
                if jsonRequested {
                    emitJSONSuccess(container)
                } else {
                    print("{\"name\":\"\(container.name)\",\"identifier\":\"\(container.identifier)\",\"type\":\"\(container.type)\",\"isICloud\":\(container.isICloud) }")
                }
            case ["contacts", "export"]:
                emitJSONSuccess(try store.list())
            case let args where args.count == 4 && args[0] == "contacts" && args[1] == "export" && args[2] == "--output":
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(store.list()).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
                if jsonRequested { emitJSONSuccess(["message": "Contacts exported.", "output": args[3]]) }
                else { print("Contacts exported.") }
            case let args where args.count >= 2 && args[0] == "contacts" && args[1] == "list":
                let pagination = try parseContactPagination(Array(args.dropFirst(2)))
                emitJSONSuccess(try store.listPage(limit: pagination.limit, cursor: pagination.cursor))
            case let args where (args.count == 4 || args.count == 6) &&
                args[0] == "contacts" && args[1] == "get" && args[2] == "--external-id" &&
                (args.count == 4 || (args[4] == "--format" && args[5] == "json")):
                let externalID = args[3]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if args.count == 6 { emitJSONSuccess(try store.get(externalID: externalID)) } else { print(String(data: try encoder.encode(store.get(externalID: externalID)), encoding: .utf8)!) }
            case let args where args.count == 5 && args[0] == "contacts" && args[1] == "avatar" && args[2] == "verify" && args[3] == "--external-id":
                let verification = try store.verifyImage(externalID: args[4])
                if jsonRequested { emitJSONSuccess(verification) }
                else {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    print(String(data: try encoder.encode(verification), encoding: .utf8)!)
                }
            case let args where (args.count == 8 || args.count == 10) &&
                args[0] == "contacts" && args[1] == "avatar" && args[2] == "replace" &&
                args[3] == "--external-id" && args[5] == "--image":
                let externalID = args[4]
                let imagePath = args[6]
                let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                guard !imageData.isEmpty else { throw ContactsError.invalidInput("image file is empty") }
                let processed = try ContactImageProcessor().process(imageData)
                let isApply = args.count == 10 && args[7] == "--apply" && args[8] == "--confirm" && args[9] == "RECREATE CONTACT"
                let isDryRun = args.count == 8 && args[7] == "--dry-run"
                guard isApply || isDryRun else { throw ContactsError.avatarReplacementConfirmationRequired }
                if isDryRun {
                    let preview: [String: Any] = ["externalID": externalID, "originalBytes": imageData.count, "finalBytes": processed.data.count, "width": processed.width, "height": processed.height, "dryRun": true, "operation": "avatar_replace"]
                    if let data = try? JSONSerialization.data(withJSONObject: preview, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
                } else {
                    let verification = try store.replaceImage(externalID: externalID, data: imageData)
                    if jsonRequested { emitJSONSuccess(ContactImageWriteResult(operation: "avatar_replaced", contact: try store.get(externalID: externalID), avatar: verification)) } else { print("Contact avatar replaced (\(verification.status.rawValue)).") }
                }
            case let args where args.count >= 4 && args[0] == "contacts" && args[1] == "query":
                let pagination = try parseContactPagination(Array(args.dropFirst(2)))
                let query = try parseQuerySet(pagination.conditions)
                emitJSONSuccess(try store.queryPage(query, limit: pagination.limit, cursor: pagination.cursor))
            case let args where args.count >= 4 && args[0] == "contacts" && args[1] == "create":
                let (inputData, mode, idempotent) = try parseJSONWriteArguments(Array(args.dropFirst(2)), command: "create")
                let payload = try JSONDecoder().decode(ContactPayload.self, from: inputData)
                guard payload.externalID != nil else { throw ContactsError.invalidInput("external_id is required") }
                if mode == "--dry-run" {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let preview = ContactsMapper().map(ContactsMapper().makeMutableContact(from: payload))
                    if jsonRequested { emitJSONSuccess(preview) } else { print(String(data: try encoder.encode(preview), encoding: .utf8)!) }
                } else {
                    let existing: ContactPayload?
                    do { existing = try store.get(externalID: payload.externalID!) }
                    catch ContactsQueryError.notFound { existing = nil }
                    if let existing {
                        guard idempotent else { throw ContactsError.duplicateExternalID(payload.externalID!) }
                        guard payload.isEquivalentForIdempotentCreate(to: existing) else { throw ContactsError.idempotencyConflict(payload.externalID!) }
                        if jsonRequested { emitJSONSuccess(ContactWriteResult(operation: "already_exists", contact: existing)) } else { print("Contact already exists.") }
                    } else {
                        try store.create(payload)
                        if jsonRequested { emitJSONSuccess(ContactWriteResult(operation: "created", contact: try store.get(externalID: payload.externalID!))) } else { print("Contact created.") }
                    }
                }
            case let args where args.count >= 6 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && (args.contains("--input") || args.contains("--stdin")):
                let externalID = args[3]
                let (inputData, mode, idempotent) = try parseJSONWriteArguments(Array(args.dropFirst(4)), command: "edit")
                guard !idempotent else { throw ContactsError.invalidInput("--idempotent is supported only by create") }
                let patch = try JSONDecoder().decode(ContactPatch.self, from: inputData)
                if mode == "--apply" { try store.update(externalID: externalID, with: patch); if jsonRequested { emitJSONSuccess(ContactWriteResult(operation: "updated", contact: try store.get(externalID: externalID))) } else { print("Contact updated.") } }
                else { let before = try store.get(externalID: externalID); let mutable = ContactsMapper().makeMutableContact(from: before); try ContactsMapper().update(mutable, from: patch, preservingExternalID: externalID); var after = ContactsMapper().map(mutable); after.imageAvailable = before.imageAvailable; let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(data: try encoder.encode(["before": before, "after": after]), encoding: .utf8)!) }
            case let args where args.count == 7 && args[0] == "contacts" && args[1] == "edit" && args[2] == "--external-id" && args[4] == "--image":
                let externalID = args[3]
                let imagePath = args[5]
                guard args[6] == "--dry-run" || args[6] == "--apply" else { throw ContactsError.invalidInput("image edit requires --dry-run or --apply") }
                let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                guard !imageData.isEmpty else { throw ContactsError.invalidInput("image file is empty") }
                let processed = try ContactImageProcessor().process(imageData)
                if args[6] == "--apply" { let verification = try store.updateImage(externalID: externalID, data: imageData); if jsonRequested { emitJSONSuccess(ContactImageWriteResult(operation: "image_updated", contact: try store.get(externalID: externalID), avatar: verification)) } else { print("Contact image updated (\(verification.status.rawValue)).") } }
                else { print("{\"externalID\":\"\(externalID)\",\"imagePath\":\"\(imagePath)\",\"originalBytes\":\(imageData.count),\"finalBytes\":\(processed.data.count),\"width\":\(processed.width),\"height\":\(processed.height),\"compressed\":\(processed.wasCompressed),\"dryRun\":true}") }
            case let args where args.count >= 4 &&
                args[0] == "contacts" && args[1] == "delete" && args[2] == "--external-id":
                let externalID = args[3]
                let ignoreNotFound = args.contains("--ignore-not-found")
                let normalizedArgs = args.filter { $0 != "--ignore-not-found" }
                let isApply = normalizedArgs.count == 7 && normalizedArgs[4] == "--apply" && normalizedArgs[5] == "--confirm" && normalizedArgs[6] == "DELETE CONTACT"
                guard (normalizedArgs.count == 5 && normalizedArgs[4] == "--dry-run") || isApply else { throw ContactsError.invalidInput("delete requires --dry-run or --apply --confirm \"DELETE CONTACT\"") }
                if isApply {
                    do {
                        let deleted = try store.get(externalID: externalID)
                        try store.delete(externalID: externalID)
                        if jsonRequested { emitJSONSuccess(ContactDeleteResult(contact: deleted)) } else { print("Contact deleted.") }
                    } catch ContactsQueryError.notFound where ignoreNotFound {
                        if jsonRequested { emitJSONSuccess(ContactAlreadyDeletedResult(externalID: externalID)) } else { print("Contact already deleted.") }
                    }
                }
                else { let preview = try store.get(externalID: externalID); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; if jsonRequested { emitJSONSuccess(preview) } else { print(String(data: try encoder.encode(preview), encoding: .utf8)!) } }
            case let args where args.count >= 7 &&
                args[0] == "contacts" && args[1] == "external-id" && args[2] == "migrate" &&
                args[3] == "--from" && args[5] == "--to":
                let oldID = args[4], newID = args[6]
                let isApply = args.count == 10 && args[7] == "--apply" && args[8] == "--confirm" && args[9] == "CHANGE EXTERNAL ID"
                guard (args.count == 8 && args[7] == "--dry-run") || isApply else { throw ContactsError.externalIDMigrationConfirmationRequired }
                if isApply { try store.migrateExternalID(from: oldID, to: newID); if jsonRequested { emitJSONSuccess(MigrationResult(from: oldID, to: newID, contact: try store.get(externalID: newID))) } else { print("External ID migrated.") } }
                else { if jsonRequested { emitJSONSuccess(MigrationPreview(from: oldID, to: newID, dryRun: true, message: nil)) } else { print("{\"from\":\"\(oldID)\",\"to\":\"\(newID)\",\"dryRun\":true}") } }
            default:
                report(error: "unknown command or invalid arguments", code: CLIErrorCode.invalidQuery.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
                Foundation.exit(CLIExitCode.usage.rawValue)
            }
        } catch let error as ContactsError {
            report(error: error.description, code: CLIErrorCode.contacts.rawValue, arguments: rawArguments, exitCode: CLIExitCode.contactsFailure.rawValue)
            Foundation.exit(CLIExitCode.contactsFailure.rawValue)
        } catch let error as ContactsQueryError {
            report(error: error.description, code: CLIErrorCode.query.rawValue, arguments: rawArguments, exitCode: CLIExitCode.queryFailure.rawValue)
            Foundation.exit(CLIExitCode.queryFailure.rawValue)
        } catch let error as ContactQuerySetError {
            report(error: error.description, code: CLIErrorCode.invalidQuery.rawValue, arguments: rawArguments, exitCode: CLIExitCode.usage.rawValue)
            Foundation.exit(CLIExitCode.usage.rawValue)
        } catch let error as MailStoreError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.mailFailure.rawValue)
            Foundation.exit(CLIExitCode.mailFailure.rawValue)
        } catch let error as CalendarError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.calendarFailure.rawValue)
            Foundation.exit(CLIExitCode.calendarFailure.rawValue)
        } catch let error as ReminderError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.remindersFailure.rawValue)
            Foundation.exit(CLIExitCode.remindersFailure.rawValue)
        } catch let error as PhotoError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.photosFailure.rawValue)
            Foundation.exit(CLIExitCode.photosFailure.rawValue)
        } catch let error as NotesError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.notesFailure.rawValue)
            Foundation.exit(CLIExitCode.notesFailure.rawValue)
        } catch let error as ShortcutsError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.shortcutsFailure.rawValue)
            Foundation.exit(CLIExitCode.shortcutsFailure.rawValue)
        } catch let error as SafariError {
            report(error: error.description, code: error.machineCode, arguments: rawArguments, exitCode: CLIExitCode.safariFailure.rawValue)
            Foundation.exit(CLIExitCode.safariFailure.rawValue)
        } catch let error as PaginationError {
            if rawArguments.first == "reminders" {
                report(error: error == .invalidLimit ? "Reminder limit must be between 1 and 200." : "Reminder cursor is invalid or stale.", code: CLIErrorCode.reminders.rawValue, arguments: rawArguments, exitCode: CLIExitCode.remindersFailure.rawValue)
                Foundation.exit(CLIExitCode.remindersFailure.rawValue)
            } else if rawArguments.first == "photos" {
                report(error: error == .invalidLimit ? "Photos limit must be between 1 and 200." : "Photos cursor is invalid or stale.", code: CLIErrorCode.photos.rawValue, arguments: rawArguments, exitCode: CLIExitCode.photosFailure.rawValue)
                Foundation.exit(CLIExitCode.photosFailure.rawValue)
            } else if rawArguments.first == "notes" {
                report(error: error == .invalidLimit ? "Notes limit must be between 1 and 200." : "Notes cursor is invalid or stale.", code: CLIErrorCode.notes.rawValue, arguments: rawArguments, exitCode: CLIExitCode.notesFailure.rawValue)
                Foundation.exit(CLIExitCode.notesFailure.rawValue)
            } else if rawArguments.first == "shortcuts" {
                report(error: error == .invalidLimit ? "Shortcuts limit must be between 1 and 200." : "Shortcuts cursor is invalid or stale.", code: CLIErrorCode.shortcuts.rawValue, arguments: rawArguments, exitCode: CLIExitCode.shortcutsFailure.rawValue)
                Foundation.exit(CLIExitCode.shortcutsFailure.rawValue)
            } else if rawArguments.first == "safari" {
                report(error: error == .invalidLimit ? "Safari limit must be between 1 and 200." : "Safari cursor is invalid or stale.", code: CLIErrorCode.safari.rawValue, arguments: rawArguments, exitCode: CLIExitCode.safariFailure.rawValue)
                Foundation.exit(CLIExitCode.safariFailure.rawValue)
            } else {
                report(error: error == .invalidLimit ? "Calendar limit must be between 1 and 200." : "Calendar cursor is invalid or stale.", code: CLIErrorCode.calendar.rawValue, arguments: rawArguments, exitCode: CLIExitCode.calendarFailure.rawValue)
                Foundation.exit(CLIExitCode.calendarFailure.rawValue)
            }
        } catch {
            report(error: error.localizedDescription, code: CLIErrorCode.cli.rawValue, arguments: rawArguments, exitCode: CLIExitCode.genericFailure.rawValue)
            Foundation.exit(CLIExitCode.genericFailure.rawValue)
        }
    }

    private static func report(error: String, code: String, arguments: [String], exitCode: Int32) {
        DiagnosticLogger.record(code: code, message: error)
        if arguments.contains("--format") && arguments.contains("json") {
            let response: [String: Any] = ["ok": false, "contractVersion": JSONContract.version, "error": ["code": code, "message": error]]
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { fputs(text + "\n", stderr) }
        } else {
            fputs("error: \(error)\n", stderr)
        }
    }

    private struct JSONSuccess<T: Encodable>: Encodable { let ok = true; let contractVersion = JSONContract.version; let data: T }
    private struct ContactWriteResult: Encodable { let operation: String; let contact: ContactPayload }
    private struct ContactImageWriteResult: Encodable { let operation: String; let contact: ContactPayload; let avatar: AvatarWriteVerification }
    private struct ContactDeleteResult: Encodable { let operation = "deleted"; let contact: ContactPayload }
    private struct ContactAlreadyDeletedResult: Encodable { let operation = "already_deleted"; let externalID: String }
    private struct MigrationPreview: Encodable { let from: String; let to: String; let dryRun: Bool; let message: String? }
    private struct MigrationResult: Encodable { let from: String; let to: String; let contact: ContactPayload }
    private struct CalendarWriteResult: Encodable { let operation: String; let dryRun: Bool; let event: CalendarEventPayload }
    private struct CalendarUpdatePreview: Encodable { let operation: String; let dryRun: Bool; let before: CalendarEventPayload; let after: CalendarEventPayload }
    private struct CalendarPermissionResult: Encodable { let granted: Bool; let access: String }
    private struct RemindersPermissionResult: Encodable { let granted: Bool; let access: String }
    private struct PhotosPermissionResult: Encodable {
        let access: String
        let readable: Bool
        let complete: Bool
        let requested: Bool
    }
    private struct PhotoAlbumArguments {
        var kind: PhotoAlbumQueryKind = .all
        var limit = Pagination.defaultLimit
        var cursor: String?
    }
    private struct PhotoGetArguments {
        let id: String
        let includeLocation: Bool
    }
    private struct PhotoExportArguments {
        let id: String
        let outputURL: URL
        let variant: PhotoExportVariant
        let allowNetwork: Bool
    }
    private struct NotesFolderArguments {
        var accountID: String?
        var parentID: String?
        var limit = Pagination.defaultLimit
        var cursor: String?
    }

    private struct NotesGetArguments {
        let id: String
        let bodyFormat: NotesBodyFormat
        let includeAttachments: Bool
    }

    private struct NotesWriteAccountArguments { let accountID: String?; let apply: Bool }
    private struct NotesMutationArguments { let id: String?; let data: Data; let apply: Bool; let idempotent: Bool }
    private struct SafariBookmarkPageArguments { let query: SafariBookmarkQuery; let limit: Int; let cursor: String? }
    private struct SafariReadingListPageArguments { let query: SafariReadingListQuery; let limit: Int; let cursor: String? }
    private struct SafariReadingListAddArguments { let data: Data; let apply: Bool }
    private struct SafariLocalMutationArguments { let data: Data; let apply: Bool; let confirmation: String? }

    private static func emitJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) { print(text) }
    }

    private static func emitPhotosJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func emitNotesJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func emitSafariJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func parseNotesWriteAccountArguments(_ arguments: [String], clear: Bool) throws -> NotesWriteAccountArguments {
        var accountID: String?
        var apply = false
        var modeSeen = false
        var confirmation: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--account-id":
                guard !clear, accountID == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                accountID = arguments[index + 1]; index += 2
            case "--dry-run":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; index += 1
            case "--apply":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; apply = true; index += 1
            case "--confirm":
                guard confirmation == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                confirmation = arguments[index + 1]; index += 2
            default: throw NotesError.invalidWriteInput
            }
        }
        if clear { guard accountID == nil else { throw NotesError.invalidWriteInput } }
        else { guard let accountID, !accountID.isEmpty else { throw NotesError.invalidWriteInput } }
        if apply {
            let expected = clear ? "CLEAR ICLOUD NOTES" : "BIND ICLOUD NOTES"
            guard confirmation == expected else { throw NotesError.invalidWriteInput }
        }
        return NotesWriteAccountArguments(accountID: accountID, apply: apply)
    }

    private static func parseNotesMutationArguments(_ arguments: [String], command: String, requiresID: Bool) throws -> NotesMutationArguments {
        var id: String?
        var source: String?
        var apply = false
        var modeSeen = false
        var idempotent = false
        var confirmation: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--id":
                guard requiresID, id == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                id = arguments[index + 1]; index += 2
            case "--input":
                guard source == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                source = arguments[index + 1]; index += 2
            case "--stdin":
                guard source == nil else { throw NotesError.invalidWriteInput }
                source = "-"; index += 1
            case "--dry-run":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; index += 1
            case "--apply":
                guard !modeSeen else { throw NotesError.invalidWriteInput }
                modeSeen = true; apply = true; index += 1
            case "--idempotent":
                guard command == "create", !idempotent else { throw NotesError.invalidWriteInput }
                idempotent = true; index += 1
            case "--confirm":
                guard ["delete", "folder-delete"].contains(command), confirmation == nil, index + 1 < arguments.count else { throw NotesError.invalidWriteInput }
                confirmation = arguments[index + 1]; index += 2
            default: throw NotesError.invalidWriteInput
            }
        }
        guard let source, !source.isEmpty, !requiresID || !(id ?? "").isEmpty else { throw NotesError.invalidWriteInput }
        if command == "delete", apply {
            guard confirmation == "DELETE NOTE" else { throw NotesError.invalidWriteInput }
        } else if command == "folder-delete", apply {
            guard confirmation == "DELETE EMPTY NOTES FOLDER" else { throw NotesError.invalidWriteInput }
        } else if confirmation != nil {
            throw NotesError.invalidWriteInput
        }
        do {
            let data = source == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: URL(fileURLWithPath: source))
            guard !data.isEmpty else { throw NotesError.invalidWriteInput }
            return NotesMutationArguments(id: id, data: data, apply: apply, idempotent: idempotent)
        } catch let error as NotesError { throw error }
        catch { throw NotesError.invalidWriteInput }
    }

    private static func decodeNotesWrite<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(T.self, from: data) }
        catch { throw NotesError.invalidWriteInput }
    }

    private static func parseNotesFolderArguments(_ arguments: [String]) throws -> NotesFolderArguments {
        var result = NotesFolderArguments()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw NotesError.invalidIdentifier }
            guard index + 1 < arguments.count else { throw NotesError.invalidIdentifier }
            let value = arguments[index + 1]
            guard !value.isEmpty else { throw NotesError.invalidIdentifier }
            switch option {
            case "--account-id": result.accountID = value
            case "--parent-id": result.parentID = value
            case "--limit":
                guard let limit = Int(value), (1...Pagination.maximumLimit).contains(limit) else {
                    throw NotesError.invalidLimit
                }
                result.limit = limit
            case "--cursor": result.cursor = value
            default: throw NotesError.invalidIdentifier
            }
            index += 2
        }
        return result
    }

    private static func parseNotesQueryArguments(_ arguments: [String]) throws -> NotesQuery {
        var accountID: String?
        var folderID: String?
        var title: String?
        var modifiedAfter: Date?
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted, index + 1 < arguments.count else { throw NotesError.invalidQuery }
            let value = arguments[index + 1]
            guard !value.isEmpty else { throw NotesError.invalidQuery }
            switch option {
            case "--account-id": accountID = value
            case "--folder-id": folderID = value
            case "--title":
                guard value.count <= 200 else { throw NotesError.invalidQuery }
                title = value
            case "--modified-after":
                guard let parsed = ISO8601DateFormatter().date(from: value) else { throw NotesError.invalidQuery }
                modifiedAfter = parsed
            case "--limit":
                guard let parsed = Int(value), (1...Pagination.maximumLimit).contains(parsed) else {
                    throw NotesError.invalidLimit
                }
                limit = parsed
            case "--cursor": cursor = value
            default: throw NotesError.invalidQuery
            }
            index += 2
        }
        return NotesQuery(
            accountID: accountID,
            folderID: folderID,
            title: title,
            modifiedAfter: modifiedAfter,
            limit: limit,
            cursor: cursor
        )
    }

    private static func parseNotesGetArguments(_ arguments: [String]) throws -> NotesGetArguments {
        var id: String?
        var bodyFormat = NotesBodyFormat.none
        var includeAttachments = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--body", "--include-attachments"].contains(option), seen.insert(option).inserted else { throw NotesError.invalidQuery }
            if option == "--include-attachments" {
                includeAttachments = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw NotesError.invalidQuery }
            let value = arguments[index + 1]
            if option == "--id" {
                id = value
            } else {
                guard let parsed = NotesBodyFormat(rawValue: value) else { throw NotesError.invalidQuery }
                bodyFormat = parsed
            }
            index += 2
        }
        guard let id, !id.isEmpty else { throw NotesError.invalidIdentifier }
        return NotesGetArguments(id: id, bodyFormat: bodyFormat, includeAttachments: includeAttachments)
    }

    private static func parsePhotoAlbumArguments(_ arguments: [String]) throws -> PhotoAlbumArguments {
        var result = PhotoAlbumArguments()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else {
                throw PhotoError.invalidArgument("duplicate albums option")
            }
            guard index + 1 < arguments.count else {
                throw PhotoError.invalidArgument("\(option) requires a value")
            }
            let value = arguments[index + 1]
            switch option {
            case "--kind":
                guard let kind = PhotoAlbumQueryKind(rawValue: value) else {
                    throw PhotoError.invalidArgument("--kind must be user, smart, or all")
                }
                result.kind = kind
            case "--limit":
                guard let limit = Int(value), (1...Pagination.maximumLimit).contains(limit) else {
                    throw PhotoError.invalidLimit
                }
                result.limit = limit
            case "--cursor":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                result.cursor = value
            default:
                throw PhotoError.invalidArgument("unsupported albums option")
            }
            index += 2
        }
        return result
    }

    private static func parsePhotoQueryArguments(_ arguments: [String]) throws -> PhotoAssetQuery {
        var start: Date?
        var end: Date?
        var albumID: String?
        var mediaType: PhotoMediaType?
        var favorite: Bool?
        var includeHidden = false
        var includeLocation = false
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0

        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw PhotoError.invalidArgument("duplicate query option") }
            if option == "--include-hidden" || option == "--include-location" {
                if option == "--include-hidden" { includeHidden = true } else { includeLocation = true }
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw PhotoError.invalidArgument("\(option) requires a value") }
            let value = arguments[index + 1]
            switch option {
            case "--start":
                guard let date = ISO8601DateFormatter().date(from: value) else { throw PhotoError.invalidArgument("--start must be ISO 8601") }
                start = date
            case "--end":
                guard let date = ISO8601DateFormatter().date(from: value) else { throw PhotoError.invalidArgument("--end must be ISO 8601") }
                end = date
            case "--album-id":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                albumID = value
            case "--media":
                guard let parsed = PhotoMediaType(rawValue: value) else { throw PhotoError.invalidArgument("--media must be image, video, audio, or unknown") }
                mediaType = parsed
            case "--favorite":
                guard value == "true" || value == "false" else { throw PhotoError.invalidArgument("--favorite must be true or false") }
                favorite = value == "true"
            case "--limit":
                guard let parsed = Int(value), (1...Pagination.maximumLimit).contains(parsed) else { throw PhotoError.invalidLimit }
                limit = parsed
            case "--cursor":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                cursor = value
            default:
                throw PhotoError.invalidArgument("unsupported query option")
            }
            index += 2
        }
        guard let start, let end else { throw PhotoError.invalidArgument("query requires --start and --end") }
        return PhotoAssetQuery(
            start: start,
            end: end,
            albumID: albumID,
            mediaType: mediaType,
            favorite: favorite,
            includeHidden: includeHidden,
            includeLocation: includeLocation,
            limit: limit,
            cursor: cursor
        )
    }

    private static func parsePhotoGetArguments(_ arguments: [String]) throws -> PhotoGetArguments {
        var id: String?
        var includeLocation = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw PhotoError.invalidArgument("duplicate get option") }
            if option == "--include-location" {
                includeLocation = true
                index += 1
                continue
            }
            guard option == "--id", index + 1 < arguments.count else { throw PhotoError.invalidArgument("get accepts --id and --include-location") }
            guard !arguments[index + 1].isEmpty else { throw PhotoError.invalidIdentifier }
            id = arguments[index + 1]
            index += 2
        }
        guard let id else { throw PhotoError.invalidArgument("get requires --id") }
        return PhotoGetArguments(id: id, includeLocation: includeLocation)
    }

    private static func parsePhotoExportArguments(_ arguments: [String]) throws -> PhotoExportArguments {
        var id: String?
        var output: String?
        var variant = PhotoExportVariant.original
        var allowNetwork = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw PhotoError.invalidArgument("duplicate export option") }
            if option == "--allow-network" {
                allowNetwork = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw PhotoError.invalidArgument("\(option) requires a value") }
            let value = arguments[index + 1]
            switch option {
            case "--id":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                id = value
            case "--output":
                guard !value.isEmpty, value != "-" else { throw PhotoError.invalidOutput }
                output = value
            case "--variant":
                guard let parsed = PhotoExportVariant(rawValue: value) else {
                    throw PhotoError.invalidArgument("--variant must be original, current, paired-video, or adjustment-data")
                }
                variant = parsed
            default:
                throw PhotoError.invalidArgument("unsupported export option")
            }
            index += 2
        }
        guard let id, let output else { throw PhotoError.invalidArgument("export requires --id and --output") }
        return PhotoExportArguments(
            id: id,
            outputURL: URL(fileURLWithPath: output).standardizedFileURL,
            variant: variant,
            allowNetwork: allowNetwork
        )
    }

    private static func emitCalendarJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) { print(text) }
    }

    private static func emitRemindersJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func parseJSONWriteArguments(_ arguments: [String], command: String) throws -> (Data, String, Bool) {
        var inputSource: String?
        var mode: String?
        var idempotent = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--input":
                guard inputSource == nil, index + 1 < arguments.count else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one JSON source")
                }
                inputSource = arguments[index + 1]
                index += 2
            case "--stdin":
                guard inputSource == nil else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one JSON source")
                }
                inputSource = "-"
                index += 1
            case "--dry-run", "--apply":
                guard mode == nil else {
                    throw ContactsError.invalidInput("\(command) accepts exactly one of --dry-run or --apply")
                }
                mode = arguments[index]
                index += 1
            case "--idempotent":
                guard command == "create", !idempotent else {
                    throw ContactsError.invalidInput("--idempotent is supported only by create")
                }
                idempotent = true
                index += 1
            default:
                throw ContactsError.invalidInput("unsupported \(command) option: \(arguments[index])")
            }
        }

        guard let inputSource, let mode else {
            throw ContactsError.invalidInput("\(command) requires JSON input (--input <file> or --stdin) and --dry-run or --apply")
        }

        let data: Data
        if inputSource == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            data = try Data(contentsOf: URL(fileURLWithPath: inputSource))
        }
        guard !data.isEmpty else {
            throw ContactsError.invalidInput("\(command) JSON input is empty")
        }
        return (data, mode, idempotent)
    }

    private struct CalendarWriteArguments {
        let data: Data
        let mode: String
        let span: CalendarMutationSpan?
        let idempotent: Bool
    }

    private static func parseCalendarWriteArguments(
        _ arguments: [String],
        command: String,
        allowsSpan: Bool
    ) throws -> CalendarWriteArguments {
        var inputSource: String?
        var mode: String?
        var span: CalendarMutationSpan?
        var idempotent = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--input":
                guard inputSource == nil, index + 1 < arguments.count else { throw CalendarError.invalidInput("\(command) accepts exactly one JSON source") }
                inputSource = arguments[index + 1]
                index += 2
            case "--stdin":
                guard inputSource == nil else { throw CalendarError.invalidInput("\(command) accepts exactly one JSON source") }
                inputSource = "-"
                index += 1
            case "--dry-run", "--apply":
                guard mode == nil else { throw CalendarError.invalidInput("\(command) accepts exactly one of --dry-run or --apply") }
                mode = arguments[index]
                index += 1
            case "--span":
                guard allowsSpan, span == nil, index + 1 < arguments.count,
                      let value = CalendarMutationSpan(rawValue: arguments[index + 1]) else {
                    throw CalendarError.invalidInput("--span requires this or future")
                }
                span = value
                index += 2
            case "--idempotent":
                guard command == "create", !idempotent else { throw CalendarError.invalidInput("--idempotent is supported only by create") }
                idempotent = true
                index += 1
            default:
                throw CalendarError.invalidInput("unsupported \(command) option: \(arguments[index])")
            }
        }
        guard let inputSource, let mode else {
            throw CalendarError.invalidInput("\(command) requires JSON input (--input <file> or --stdin) and --dry-run or --apply")
        }
        let data = inputSource == "-"
            ? FileHandle.standardInput.readDataToEndOfFile()
            : try Data(contentsOf: URL(fileURLWithPath: inputSource))
        guard !data.isEmpty else { throw CalendarError.invalidInput("\(command) JSON input is empty") }
        return CalendarWriteArguments(data: data, mode: mode, span: span, idempotent: idempotent)
    }

    private static func parseCalendarDeleteArguments(_ arguments: [String]) throws -> (apply: Bool, span: CalendarMutationSpan?) {
        var apply: Bool?
        var confirmed = false
        var span: CalendarMutationSpan?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--dry-run":
                guard apply == nil else { throw CalendarError.invalidInput("delete accepts exactly one of --dry-run or --apply") }
                apply = false
                index += 1
            case "--apply":
                guard apply == nil else { throw CalendarError.invalidInput("delete accepts exactly one of --dry-run or --apply") }
                apply = true
                index += 1
            case "--confirm":
                guard index + 1 < arguments.count, arguments[index + 1] == "DELETE EVENT" else {
                    throw CalendarError.invalidInput("delete apply requires --confirm \"DELETE EVENT\"")
                }
                confirmed = true
                index += 2
            case "--span":
                guard span == nil, index + 1 < arguments.count, let value = CalendarMutationSpan(rawValue: arguments[index + 1]) else {
                    throw CalendarError.invalidInput("--span requires this or future")
                }
                span = value
                index += 2
            default:
                throw CalendarError.invalidInput("unsupported delete option: \(arguments[index])")
            }
        }
        guard let apply else { throw CalendarError.invalidInput("delete requires --dry-run or --apply") }
        guard !apply || confirmed else { throw CalendarError.invalidInput("delete apply requires --confirm \"DELETE EVENT\"") }
        guard apply || !confirmed else { throw CalendarError.invalidInput("--confirm is valid only with --apply") }
        return (apply, span)
    }

    private static func calendarDecoder() -> JSONDecoder {
        CalendarJSON.decoder()
    }

    private static func decodeCalendar<T: Decodable>(_ data: Data) throws -> T {
        do { return try calendarDecoder().decode(T.self, from: data) }
        catch { throw CalendarError.invalidInput("JSON does not match the Calendar contract") }
    }

    private static func parseCalendarQuery(_ arguments: [String]) throws -> CalendarEventQuery {
        var startDate: Date?
        var endDate: Date?
        var calendarID: String?
        var title: String?
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--start", "--end", "--calendar", "--title", "--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else {
                throw CalendarError.invalidInput("calendar query accepts --start, --end, --calendar, --title, --limit, and --cursor")
            }
            let value = arguments[index + 1]
            switch option {
            case "--start": startDate = try parseCalendarDate(value, option: option)
            case "--end": endDate = try parseCalendarDate(value, option: option)
            case "--calendar": calendarID = value
            case "--title": title = value
            case "--limit": guard let parsed = Int(value) else { throw CalendarError.invalidInput("--limit requires an integer") }; limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }
        guard let startDate, let endDate else { throw CalendarError.invalidInput("calendar query requires --start and --end") }
        do { return try CalendarEventQuery(startDate: startDate, endDate: endDate, calendarID: calendarID, title: title, limit: limit, cursor: cursor) }
        catch let error as PaginationError { throw error }
    }

    private static func parseCalendarConflicts(_ arguments: [String]) throws -> CalendarEventQuery {
        var forwarded: [String] = []
        var index = 0
        while index < arguments.count {
            guard ["--start", "--end", "--calendar"].contains(arguments[index]), index + 1 < arguments.count else {
                throw CalendarError.invalidInput("calendar conflicts accepts --start, --end, and --calendar")
            }
            forwarded.append(contentsOf: [arguments[index], arguments[index + 1]])
            index += 2
        }
        return try parseCalendarQuery(forwarded)
    }

    private static func parseCalendarDate(_ value: String, option: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = formatter.date(from: value) { return date }
        throw CalendarError.invalidInput("\(option) requires ISO 8601, for example 2026-08-14T09:00:00+09:00")
    }

    private static func parseReminderQuery(_ arguments: [String]) throws -> ReminderQuery {
        var status = ReminderQueryStatus.incomplete
        var dueStart: Date?
        var dueEnd: Date?
        var listID: String?
        var title: String?
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        let supported = ["--status", "--due-start", "--due-end", "--list", "--title", "--limit", "--cursor"]

        while index < arguments.count {
            let option = arguments[index]
            guard supported.contains(option), seen.insert(option).inserted, index + 1 < arguments.count else {
                throw ReminderError.invalidInput("reminders query accepts --status, --due-start, --due-end, --list, --title, --limit, and --cursor")
            }
            let value = arguments[index + 1]
            switch option {
            case "--status":
                guard let parsed = ReminderQueryStatus(rawValue: value) else {
                    throw ReminderError.invalidInput("--status requires incomplete, completed, or all")
                }
                status = parsed
            case "--due-start": dueStart = try parseReminderDate(value, option: option)
            case "--due-end": dueEnd = try parseReminderDate(value, option: option)
            case "--list": listID = value
            case "--title": title = value
            case "--limit":
                guard let parsed = Int(value) else { throw ReminderError.invalidInput("--limit requires an integer") }
                limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }

        return try ReminderQuery(
            status: status,
            dueStart: dueStart,
            dueEnd: dueEnd,
            listID: listID,
            title: title,
            limit: limit,
            cursor: cursor
        )
    }

    private struct ReminderCreateArguments {
        let data: Data
        let mode: String
        let idempotent: Bool
    }

    private static func parseReminderCreateArguments(_ arguments: [String]) throws -> ReminderCreateArguments {
        var inputSource: String?
        var mode: String?
        var idempotent = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--input":
                guard inputSource == nil, index + 1 < arguments.count else {
                    throw ReminderError.invalidInput("create accepts exactly one JSON source")
                }
                inputSource = arguments[index + 1]
                index += 2
            case "--stdin":
                guard inputSource == nil else {
                    throw ReminderError.invalidInput("create accepts exactly one JSON source")
                }
                inputSource = "-"
                index += 1
            case "--dry-run", "--apply":
                guard mode == nil else {
                    throw ReminderError.invalidInput("create accepts exactly one of --dry-run or --apply")
                }
                mode = arguments[index]
                index += 1
            case "--idempotent":
                guard !idempotent else { throw ReminderError.invalidInput("--idempotent may be specified once") }
                idempotent = true
                index += 1
            default:
                throw ReminderError.invalidInput("unsupported create option")
            }
        }
        guard let inputSource, let mode else {
            throw ReminderError.invalidInput("create requires JSON input (--input <file> or --stdin) and --dry-run or --apply")
        }
        let data = inputSource == "-"
            ? FileHandle.standardInput.readDataToEndOfFile()
            : try Data(contentsOf: URL(fileURLWithPath: inputSource))
        guard !data.isEmpty else { throw ReminderError.invalidInput("create JSON input is empty") }
        return ReminderCreateArguments(data: data, mode: mode, idempotent: idempotent)
    }

    private static func decodeReminder<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(T.self, from: data) }
        catch { throw ReminderError.invalidInput("JSON does not match the Reminders contract") }
    }

    private struct ReminderEditArguments {
        let data: Data
        let mode: String
    }

    private static func parseReminderEditArguments(_ arguments: [String]) throws -> ReminderEditArguments {
        var inputSource: String?
        var mode: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--input":
                guard inputSource == nil, index + 1 < arguments.count else {
                    throw ReminderError.invalidInput("edit accepts exactly one JSON source")
                }
                inputSource = arguments[index + 1]
                index += 2
            case "--stdin":
                guard inputSource == nil else {
                    throw ReminderError.invalidInput("edit accepts exactly one JSON source")
                }
                inputSource = "-"
                index += 1
            case "--dry-run", "--apply":
                guard mode == nil else {
                    throw ReminderError.invalidInput("edit accepts exactly one of --dry-run or --apply")
                }
                mode = arguments[index]
                index += 1
            default:
                throw ReminderError.invalidInput("unsupported edit option")
            }
        }
        guard let inputSource, let mode else {
            throw ReminderError.invalidInput("edit requires JSON input (--input <file> or --stdin) and --dry-run or --apply")
        }
        let data = inputSource == "-"
            ? FileHandle.standardInput.readDataToEndOfFile()
            : try Data(contentsOf: URL(fileURLWithPath: inputSource))
        guard !data.isEmpty else { throw ReminderError.invalidInput("edit JSON input is empty") }
        return ReminderEditArguments(data: data, mode: mode)
    }

    private static func parseReminderDeleteArguments(_ arguments: [String]) throws -> Bool {
        if arguments == ["--dry-run"] { return false }
        if arguments == ["--apply", "--confirm", "DELETE REMINDER"] { return true }
        throw ReminderError.invalidInput("delete requires --dry-run or --apply --confirm \"DELETE REMINDER\"")
    }

    private static func parseReminderStateArguments(_ arguments: [String], command: String) throws -> Bool {
        if arguments == ["--dry-run"] { return false }
        if arguments == ["--apply"] { return true }
        throw ReminderError.invalidInput("\(command) requires exactly one of --dry-run or --apply")
    }

    private static func parseReminderDate(_ value: String, option: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw ReminderError.invalidInput("\(option) requires an ISO 8601 timestamp with an explicit offset")
        }
        return date
    }

    private static func parseQuerySet(_ arguments: [String]) throws -> ContactQuerySet {
        var conditions: [ContactQuery] = []
        var fields = Set<String>()
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--format" {
                guard index + 1 < arguments.count, arguments[index + 1] == "json" else { throw ContactQuerySetError.invalidConditionCount }
                index += 2
                continue
            }
            guard index + 1 < arguments.count else { throw ContactQuerySetError.invalidConditionCount }
            let field = arguments[index]
            guard fields.insert(field).inserted else { throw ContactQuerySetError.duplicateField }
            let value = arguments[index + 1]
            switch field {
            case "--kind":
                guard let kind = ContactKind(rawValue: value.lowercased()) else { throw ContactQuerySetError.invalidConditionCount }
                conditions.append(.kind(kind))
            case "--name": conditions.append(.name(value))
            case "--phone": conditions.append(.phone(value))
            case "--email": conditions.append(.email(value))
            case "--url": conditions.append(.url(value))
            case "--organization": conditions.append(.organization(value))
            case "--postal-code": conditions.append(.postalCode(value))
            default: throw ContactQuerySetError.invalidConditionCount
            }
            index += 2
        }
        return try ContactQuerySet(conditions)
    }

    private struct ContactPaginationArguments {
        let conditions: [String]
        let limit: Int
        let cursor: String?
    }

    private static func parseContactPagination(_ arguments: [String]) throws -> ContactPaginationArguments {
        var conditions: [String] = []
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seenLimit = false
        var seenCursor = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--limit":
                guard !seenLimit, index + 1 < arguments.count, let parsed = Int(arguments[index + 1]) else {
                    throw ContactsQueryError.invalidLimit
                }
                limit = parsed
                seenLimit = true
                index += 2
            case "--cursor":
                guard !seenCursor, index + 1 < arguments.count else {
                    throw ContactsQueryError.invalidCursor
                }
                cursor = arguments[index + 1]
                seenCursor = true
                index += 2
            default:
                conditions.append(arguments[index])
                index += 1
            }
        }

        guard (1...Pagination.maximumLimit).contains(limit) else {
            throw ContactsQueryError.invalidLimit
        }
        return ContactPaginationArguments(conditions: conditions, limit: limit, cursor: cursor)
    }

    private enum ValidatedMailStore {
        case sqlite(SQLiteMailStore)
        case mailApp(MailAppMetadataStore)

        func accounts() throws -> MailAccountListResult {
            switch self {
            case .sqlite(let store): MailAccountListResult(accounts: try store.accounts())
            case .mailApp(let store): try store.accounts()
            }
        }

        func mailboxes(accountID: String? = nil) throws -> MailboxListResult {
            switch self {
            case .sqlite(let store): MailboxListResult(mailboxes: try store.mailboxes(accountID: accountID))
            case .mailApp(let store): try store.mailboxes(accountID: accountID)
            }
        }

        func threads(limit: Int) throws -> MailThreadListResult {
            switch self {
            case .sqlite(let store): try store.threads(limit: limit)
            case .mailApp: throw MailStoreError.invalidArgument("Mail threads require the recognized SQLite fast path.")
            }
        }

        func query(_ query: MailQuery) throws -> MailQueryResult {
            switch self {
            case .sqlite(let store): try store.query(query)
            case .mailApp(let store): try store.query(query)
            }
        }

        func searchText(_ text: String, query: MailQuery, resultLimit: Int) throws -> MailTextSearchResult {
            switch self {
            case .sqlite(let store): try store.searchText(text, query: query, resultLimit: resultLimit)
            case .mailApp: throw MailStoreError.invalidArgument("Mail text search requires the recognized SQLite/EMLX fast path; it never falls back to Mail.app.")
            }
        }

        func get(id: String, projection: MailContentProjection) throws -> MailGetResult {
            switch self {
            case .sqlite(let store): try store.get(id: id, projection: projection)
            case .mailApp(let store): try store.get(id: id, projection: projection)
            }
        }

        func rawMessage(id: String) throws -> MailRawMessage {
            switch self {
            case .sqlite(let store): try store.rawMessage(id: id)
            case .mailApp: throw MailStoreError.contentNotCached
            }
        }

        func reveal(id: String) throws -> MailRevealResult {
            switch self {
            case .sqlite(let store): try store.reveal(id: id)
            case .mailApp(let store): try store.reveal(id: id)
            }
        }

        func verifyAttachments(id: String) throws -> MailAttachmentVerificationResult {
            switch self {
            case .sqlite(let store): try store.verifyAttachments(id: id)
            case .mailApp:
                throw MailStoreError.invalidArgument("Attachment verification requires the recognized SQLite/EMLX fast path.")
            }
        }

        func exportAttachments(id: String, directory: URL) throws -> MailAttachmentExportResult {
            switch self {
            case .sqlite(let store): try store.exportAttachments(id: id, to: directory)
            case .mailApp: throw MailStoreError.invalidArgument("Attachment export requires the recognized SQLite/EMLX fast path.")
            }
        }
    }

    private static func makeValidatedMailStore() throws -> ValidatedMailStore {
        let report = MailDoctor(databaseProbe: SQLiteMailDatabaseProbe(performQuickCheck: false)).run()
        let forceMailApp = ProcessInfo.processInfo.environment["MPIA_MAIL_FORCE_APP_FALLBACK"] == "1"
        switch MailBackendSelector.select(report: report, forceMailAppFallback: forceMailApp) {
        case .sqlite:
            return .sqlite(SQLiteMailStore(databaseURL: try MailStoreLocator().locate().databaseURL))
        case .mailApp(let reason):
            return .mailApp(MailAppMetadataStore(fallbackReason: reason))
        case .unavailable(let error):
            throw error
        }
    }

    private static func makeResourcesResult(
        permission: ContactsPermission,
        store: ContactsStore,
        calendarPermission: CalendarPermission,
        calendarStore: CalendarStore,
        remindersPermission: RemindersPermission,
        remindersStore: RemindersStore,
        photosPermission: PhotosPermission,
        notesPermission: NotesPermissionService,
        notesStore: NotesStore,
        shortcutsPermission: ShortcutsPermissionService,
        safariPermission: SafariPermissionService
    ) -> DataResourcesResult {
        var resources: [DataResource] = []
        var limitations: [String] = []

        switch permission.status {
        case .authorized, .limited:
            do {
                let containers = try store.containerDescriptions()
                let selectedID = try store.selectedContainerDescription().identifier
                resources.append(contentsOf: containers.map { container in
                    ContactsResourceMapper.map(container, selected: container.identifier == selectedID)
                })
            } catch {
                limitations.append("contacts_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("contacts_permission_not_determined")
        case .denied:
            limitations.append("contacts_permission_denied")
        case .restricted:
            limitations.append("contacts_permission_restricted")
        }

        do {
            let mailAccounts = try makeValidatedMailStore().accounts()
            resources.append(contentsOf: mailAccounts.accounts.map { account in
                MailResourceMapper.map(account, selected: false)
            })
            limitations.append(contentsOf: mailAccounts.limitations)
            if !mailAccounts.accounts.isEmpty {
                limitations.append("mail_preferred_aim_tech_account_requires_explicit_verification")
            }
        } catch {
            limitations.append("mail_resource_discovery_unavailable")
        }

        switch calendarPermission.status {
        case .fullAccess:
            do {
                let result = try calendarStore.sourceDescriptions()
                resources.append(contentsOf: result.sources.map {
                    CalendarResourceMapper.map($0, selected: $0.identifier == result.selectedSourceID, permission: .available)
                })
            } catch {
                limitations.append("calendar_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("calendar_permission_not_determined")
        case .denied:
            limitations.append("calendar_permission_denied")
        case .restricted:
            limitations.append("calendar_permission_restricted")
        case .writeOnly:
            limitations.append("calendar_full_access_required")
        }

        switch remindersPermission.status {
        case .fullAccess:
            do {
                let result = try remindersStore.sourceDescriptions()
                resources.append(contentsOf: result.sources.map {
                    RemindersResourceMapper.map($0, selected: $0.identifier == result.selectedSourceID, permission: .available)
                })
            } catch {
                limitations.append("reminders_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("reminders_permission_not_determined")
        case .denied:
            limitations.append("reminders_permission_denied")
        case .restricted:
            limitations.append("reminders_permission_restricted")
        case .writeOnly:
            limitations.append("reminders_full_access_required")
        }
        resources.append(PhotosResourceMapper.map(status: photosPermission.status))
        switch photosPermission.status {
        case .authorized:
            break
        case .limited:
            limitations.append("photos_access_limited")
        case .notDetermined:
            limitations.append("photos_permission_not_determined")
        case .denied:
            limitations.append("photos_permission_denied")
        case .restricted:
            limitations.append("photos_permission_restricted")
        }
        let notesResult = notesPermission.check(requestConsent: false)
        let notesWriteStatus = notesStore.writeAccountStatus()
        resources.append(NotesResourceMapper.map(status: notesResult.access, writable: notesWriteStatus.valid))
        switch notesResult.access {
        case .available:
            if !notesWriteStatus.bound { limitations.append("notes_icloud_write_account_not_bound") }
            else if !notesWriteStatus.valid { limitations.append("notes_icloud_write_account_stale") }
        case .requiresConsent:
            limitations.append("notes_automation_requires_consent")
        case .denied:
            limitations.append("notes_automation_denied")
        case .targetNotRunning:
            limitations.append("notes_app_not_running")
        case .targetUnavailable:
            limitations.append("notes_app_unavailable")
        case .unknown:
            limitations.append("notes_automation_unknown")
        }
        let shortcutsResult = shortcutsPermission.check(requestConsent: false)
        resources.append(ShortcutsResourceMapper.map(status: shortcutsResult.access))
        switch shortcutsResult.access {
        case .available: break
        case .requiresConsent: limitations.append("shortcuts_automation_requires_consent")
        case .denied: limitations.append("shortcuts_automation_denied")
        case .targetNotRunning: limitations.append("shortcuts_events_not_running")
        case .targetUnavailable: limitations.append("shortcuts_events_unavailable")
        case .unknown: limitations.append("shortcuts_automation_unknown")
        }
        let safariResult = safariPermission.check(requestConsent: false)
        resources.append(SafariResourceMapper.map(permission: safariResult))
        if !safariResult.bookmarksReadable { limitations.append("safari_bookmarks_full_disk_access_required") }
        switch safariResult.automation {
        case .available: break
        case .requiresConsent: limitations.append("safari_automation_requires_consent")
        case .denied: limitations.append("safari_automation_denied")
        case .targetNotRunning: limitations.append("safari_not_running")
        case .targetUnavailable: limitations.append("safari_unavailable")
        case .unknown: limitations.append("safari_automation_unknown")
        }
        limitations.append("safari_bookmark_mutation_local_only_requires_safari_quit")
        limitations.append("safari_bookmark_mutation_does_not_sync_to_icloud")
        return DataResourcesResult(resources: resources, limitations: limitations)
    }

    private static func parseMailQuery(_ arguments: [String]) throws -> MailQuery {
        var query = MailQuery()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else {
                throw MailStoreError.invalidArgument("Duplicate Mail query option: \(option)")
            }
            switch option {
            case "--unread": query.unread = true; index += 1
            case "--flagged": query.flagged = true; index += 1
            case "--has-attachment": query.hasAttachment = true; index += 1
            case "--account-id", "--mailbox-id", "--from", "--to", "--subject", "--received-after", "--received-before", "--limit", "--cursor":
                guard index + 1 < arguments.count else {
                    throw MailStoreError.invalidArgument("Mail query option requires a value: \(option)")
                }
                let value = arguments[index + 1]
                switch option {
                case "--account-id": query.accountID = value
                case "--mailbox-id": query.mailboxID = value
                case "--from": query.from = value
                case "--to": query.to = value
                case "--subject": query.subject = value
                case "--received-after": query.receivedAfter = try parseMailDate(value, option: option)
                case "--received-before": query.receivedBefore = try parseMailDate(value, option: option)
                case "--limit":
                    guard let limit = Int(value) else { throw MailStoreError.invalidArgument("--limit requires an integer") }
                    query.limit = limit
                case "--cursor": query.cursor = value
                default: break
                }
                index += 2
            default:
                throw MailStoreError.invalidArgument("Unsupported Mail query option: \(option)")
            }
        }
        return query
    }

    private static func parseMailTextSearch(_ arguments: [String]) throws -> (text: String, query: MailQuery, limit: Int) {
        var text: String?
        var limit = 50
        var queryArguments: [String] = []
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--text":
                guard text == nil, index + 1 < arguments.count else { throw MailStoreError.invalidArgument("Mail text search accepts one --text value.") }
                text = arguments[index + 1]
                index += 2
            case "--limit":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else { throw MailStoreError.invalidLimit }
                limit = value
                index += 2
            default:
                queryArguments.append(arguments[index])
                index += 1
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MailStoreError.invalidArgument("Mail text search requires --text <value>.")
        }
        guard (1...200).contains(limit) else { throw MailStoreError.invalidLimit }
        return (text, try parseMailQuery(queryArguments), limit)
    }

    private static func parseSimpleLimit(_ arguments: [String]) throws -> Int {
        guard arguments.count == 0 || (arguments.count == 2 && arguments[0] == "--limit"),
              let value = arguments.isEmpty ? 50 : Int(arguments[1]),
              (1...200).contains(value) else { throw MailStoreError.invalidLimit }
        return value
    }

    private static func parseMailDate(_ value: String, option: String) throws -> Date {
        let timestampFormatter = ISO8601DateFormatter()
        if let date = timestampFormatter.date(from: value) { return date }
        let dayFormatter = ISO8601DateFormatter()
        dayFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = dayFormatter.date(from: value) { return date }
        throw MailStoreError.invalidArgument("\(option) requires ISO 8601, for example 2026-07-23 or 2026-07-23T00:00:00Z")
    }

    private struct MailGetArguments {
        let id: String
        let projection: MailContentProjection
        let output: String?
    }

    private static func parseMailGet(_ arguments: [String], jsonRequested: Bool) throws -> MailGetArguments {
        var id: String?
        var projection = MailContentProjection.metadata
        var output: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--content", "--output"].contains(option), seen.insert(option).inserted,
                  index + 1 < arguments.count else {
                throw MailStoreError.invalidArgument("mail get accepts --id, --content metadata|text|raw, and --output <file|->.")
            }
            let value = arguments[index + 1]
            switch option {
            case "--id": id = value
            case "--content":
                guard let parsed = MailContentProjection(rawValue: value) else {
                    throw MailStoreError.invalidArgument("--content requires metadata, text, or raw.")
                }
                projection = parsed
            case "--output": output = value
            default: break
            }
            index += 2
        }
        guard let id, !id.isEmpty else { throw MailStoreError.invalidArgument("mail get requires --id <opaque-local-id>.") }
        if projection == .raw, output == nil {
            throw MailStoreError.invalidArgument("Raw content requires --output <file|->.")
        }
        if projection != .raw, output != nil {
            throw MailStoreError.invalidArgument("--output is valid only with --content raw.")
        }
        if projection == .raw, output == "-", jsonRequested {
            throw MailStoreError.invalidArgument("--output - cannot be combined with --format json.")
        }
        return MailGetArguments(id: id, projection: projection, output: output)
    }

    private struct ShortcutsPageArguments {
        let limit: Int
        let cursor: String?
        let folderID: String?
    }

    private static func parseShortcutsPageArguments(_ arguments: [String], allowsFolder: Bool) throws -> ShortcutsPageArguments {
        var limit = Pagination.defaultLimit
        var cursor: String?
        var folderID: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            let allowed = allowsFolder ? ["--limit", "--cursor", "--folder-id"] : ["--limit", "--cursor"]
            guard allowed.contains(option), seen.insert(option).inserted, index + 1 < arguments.count else {
                throw ShortcutsError.invalidIdentifier
            }
            let value = arguments[index + 1]
            switch option {
            case "--limit":
                guard let parsed = Int(value), (1...Pagination.maximumLimit).contains(parsed) else { throw ShortcutsError.invalidLimit }
                limit = parsed
            case "--cursor": cursor = value
            case "--folder-id": folderID = value
            default: break
            }
            index += 2
        }
        return ShortcutsPageArguments(limit: limit, cursor: cursor, folderID: folderID)
    }

    private struct ShortcutMoveArguments {
        let id: String
        let destinationFolderID: String
        let apply: Bool
    }

    private struct ShortcutRunArguments {
        let id: String
        let inputPaths: [URL]
        let outputPath: URL?
        let outputType: String
        let timeoutSeconds: Int
    }

    private struct ShortcutAuthorArguments {
        let sourceURL: URL
        let outputURL: URL?
        let signingMode: ShortcutSigningMode
    }

    private static func parseShortcutAcquisitionArguments(_ arguments: [String]) throws -> URL {
        guard arguments.count == 2,
              arguments[0] == "--input",
              !arguments[1].contains("://") else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        let inputURL = URL(fileURLWithPath: arguments[1])
        guard ["cherri", "shortcut"].contains(inputURL.pathExtension.lowercased()) else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        return inputURL
    }

    private struct ShortcutEditPlanArguments {
        let inputURL: URL
        let patchURL: URL?
    }

    private static func parseShortcutEditPlanArguments(_ arguments: [String]) throws -> ShortcutEditPlanArguments {
        var inputURL: URL?
        var patchURL: URL?
        var usesStdin = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--input", "--patch", "--stdin"].contains(option), seen.insert(option).inserted else {
                throw ShortcutsError.editPlanInvalid
            }
            if option == "--stdin" {
                usesStdin = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw ShortcutsError.editPlanInvalid }
            let url = URL(fileURLWithPath: arguments[index + 1])
            if option == "--input" { inputURL = url }
            else { patchURL = url }
            index += 2
        }
        guard let inputURL,
              inputURL.pathExtension.lowercased() == "shortcut",
              usesStdin != (patchURL != nil),
              patchURL?.pathExtension.lowercased() == "json" || patchURL == nil else {
            throw ShortcutsError.editPlanInvalid
        }
        return ShortcutEditPlanArguments(inputURL: inputURL, patchURL: patchURL)
    }

    private struct ShortcutSemanticEditArguments {
        let inputURL: URL
        let patchURL: URL?
        let expectedEditorNameSHA256: String
        let apply: Bool
        let confirmation: String?
    }

    private static func parseShortcutSemanticEditArguments(_ arguments: [String]) throws -> ShortcutSemanticEditArguments {
        var inputURL: URL?
        var patchURL: URL?
        var usesStdin = false
        var expectedEditorNameSHA256: String?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--input", "--patch", "--stdin", "--expected-editor-name-sha256", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else {
                throw ShortcutsError.editPlanInvalid
            }
            switch option {
            case "--stdin":
                usesStdin = true
                index += 1
            case "--dry-run":
                dryRun = true
                index += 1
            case "--apply":
                apply = true
                index += 1
            default:
                guard index + 1 < arguments.count else { throw ShortcutsError.editPlanInvalid }
                let value = arguments[index + 1]
                if option == "--input" { inputURL = URL(fileURLWithPath: value) }
                else if option == "--patch" { patchURL = URL(fileURLWithPath: value) }
                else if option == "--expected-editor-name-sha256" { expectedEditorNameSHA256 = value }
                else { confirmation = value }
                index += 2
            }
        }
        guard let inputURL,
              inputURL.pathExtension.lowercased() == "shortcut",
              let expectedEditorNameSHA256,
              expectedEditorNameSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              usesStdin != (patchURL != nil),
              patchURL?.pathExtension.lowercased() == "json" || patchURL == nil,
              apply != dryRun,
              apply || confirmation == nil else {
            throw ShortcutsError.editPlanInvalid
        }
        return ShortcutSemanticEditArguments(
            inputURL: inputURL,
            patchURL: patchURL,
            expectedEditorNameSHA256: expectedEditorNameSHA256,
            apply: apply,
            confirmation: confirmation
        )
    }

    private struct ShortcutCreateArguments {
        let sourceURL: URL
        let signingMode: ShortcutSigningMode
        let apply: Bool
        let idempotent: Bool
    }

    private static func parseShortcutCreateArguments(_ arguments: [String]) throws -> ShortcutCreateArguments {
        var sourceURL: URL?
        var signingMode = ShortcutSigningMode.peopleWhoKnowMe
        var apply = false
        var dryRun = false
        var idempotent = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--source", "--signing-mode", "--dry-run", "--apply", "--idempotent", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw ShortcutsError.authorSourceInvalid }
            switch option {
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            case "--idempotent": idempotent = true; index += 1
            default:
                guard index + 1 < arguments.count else { throw ShortcutsError.authorSourceInvalid }
                let value = arguments[index + 1]
                if option == "--source" { sourceURL = URL(fileURLWithPath: value) }
                else if option == "--signing-mode" {
                    guard let parsed = ShortcutSigningMode(rawValue: value) else { throw ShortcutsError.authorSourceInvalid }
                    signingMode = parsed
                } else { confirmation = value }
                index += 2
            }
        }
        guard let sourceURL, sourceURL.pathExtension.lowercased() == "cherri", !(apply && dryRun) else {
            throw ShortcutsError.authorSourceInvalid
        }
        if apply {
            guard confirmation == "CREATE MANAGED SHORTCUT" else { throw ShortcutsError.authorCreateConfirmationRequired }
        } else if confirmation != nil {
            throw ShortcutsError.authorSourceInvalid
        }
        return ShortcutCreateArguments(sourceURL: sourceURL, signingMode: signingMode, apply: apply, idempotent: idempotent)
    }

    private struct ShortcutUpdateArguments {
        let id: String
        let sourceURL: URL
        let expectedSourceSHA256: String
        let strategy: ShortcutUpdateStrategy
        let signingMode: ShortcutSigningMode
        let apply: Bool
    }

    private static func parseShortcutUpdateArguments(_ arguments: [String]) throws -> ShortcutUpdateArguments {
        var id: String?
        var sourceURL: URL?
        var expectedSourceSHA256: String?
        var strategy: ShortcutUpdateStrategy?
        var signingMode = ShortcutSigningMode.peopleWhoKnowMe
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--source", "--expected-source-sha256", "--strategy", "--signing-mode", "--dry-run", "--apply", "--confirm"].contains(option), seen.insert(option).inserted else {
                throw ShortcutsError.authorSourceInvalid
            }
            if option == "--dry-run" { dryRun = true; index += 1; continue }
            if option == "--apply" { apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw ShortcutsError.authorSourceInvalid }
            let value = arguments[index + 1]
            switch option {
            case "--id": id = value
            case "--source": sourceURL = URL(fileURLWithPath: value)
            case "--expected-source-sha256": expectedSourceSHA256 = value
            case "--strategy": strategy = ShortcutUpdateStrategy(rawValue: value)
            case "--signing-mode": signingMode = ShortcutSigningMode(rawValue: value) ?? signingMode
            case "--confirm": confirmation = value
            default: break
            }
            if option == "--strategy" && strategy == nil { throw ShortcutsError.authorSourceInvalid }
            if option == "--signing-mode" && ShortcutSigningMode(rawValue: value) == nil { throw ShortcutsError.authorSourceInvalid }
            index += 2
        }
        guard let id, ShortcutsOpaqueID.isShortcut(id), let sourceURL, sourceURL.pathExtension.lowercased() == "cherri",
              let expectedSourceSHA256, expectedSourceSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let strategy, !(apply && dryRun) else { throw ShortcutsError.authorSourceInvalid }
        if apply {
            guard confirmation == "UPDATE MANAGED SHORTCUT" else { throw ShortcutsError.authorUpdateConfirmationRequired }
        } else if confirmation != nil { throw ShortcutsError.authorSourceInvalid }
        return ShortcutUpdateArguments(id: id, sourceURL: sourceURL, expectedSourceSHA256: expectedSourceSHA256, strategy: strategy, signingMode: signingMode, apply: apply)
    }

    private struct ShortcutManagedForgetArguments { let id: String; let apply: Bool }

    private static func parseShortcutManagedForgetArguments(_ arguments: [String]) throws -> ShortcutManagedForgetArguments {
        var id: String?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--dry-run", "--apply", "--confirm"].contains(option), seen.insert(option).inserted else {
                throw ShortcutsError.authorSourceInvalid
            }
            if option == "--dry-run" { dryRun = true; index += 1; continue }
            if option == "--apply" { apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw ShortcutsError.authorSourceInvalid }
            if option == "--id" { id = arguments[index + 1] } else { confirmation = arguments[index + 1] }
            index += 2
        }
        guard let id, ShortcutsOpaqueID.isShortcut(id), !(apply && dryRun) else { throw ShortcutsError.authorSourceInvalid }
        if apply {
            guard confirmation == "FORGET MANAGED SHORTCUT" else { throw ShortcutsError.authorForgetConfirmationRequired }
        } else if confirmation != nil { throw ShortcutsError.authorSourceInvalid }
        return ShortcutManagedForgetArguments(id: id, apply: apply)
    }

    private static func parseShortcutAuthorArguments(_ arguments: [String], build: Bool) throws -> ShortcutAuthorArguments {
        var sourceURL: URL?
        var outputURL: URL?
        var signingMode = ShortcutSigningMode.peopleWhoKnowMe
        var seen = Set<String>()
        var index = 0
        let allowed = build ? ["--source", "--output", "--signing-mode"] : ["--source"]
        while index < arguments.count {
            let option = arguments[index]
            guard allowed.contains(option), seen.insert(option).inserted, index + 1 < arguments.count else {
                throw ShortcutsError.authorSourceInvalid
            }
            let value = arguments[index + 1]
            switch option {
            case "--source": sourceURL = URL(fileURLWithPath: value)
            case "--output": outputURL = URL(fileURLWithPath: value)
            case "--signing-mode":
                guard let parsed = ShortcutSigningMode(rawValue: value) else { throw ShortcutsError.authorSourceInvalid }
                signingMode = parsed
            default: break
            }
            index += 2
        }
        guard let sourceURL, sourceURL.pathExtension.lowercased() == "cherri",
              !build || outputURL != nil else { throw ShortcutsError.authorSourceInvalid }
        return ShortcutAuthorArguments(sourceURL: sourceURL, outputURL: outputURL, signingMode: signingMode)
    }

    private static func parseShortcutRunArguments(_ arguments: [String]) throws -> ShortcutRunArguments {
        var id: String?
        var inputPaths: [URL] = []
        var outputPath: URL?
        var outputType = "public.utf8-plain-text"
        var timeoutSeconds = 30
        var apply = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--input-path", "--output-path", "--output-type", "--timeout", "--apply", "--confirm"].contains(option) else {
                throw ShortcutsError.invalidRunInput
            }
            if option != "--input-path" && !seen.insert(option).inserted { throw ShortcutsError.invalidRunInput }
            if option == "--apply" { apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw ShortcutsError.invalidRunInput }
            let value = arguments[index + 1]
            switch option {
            case "--id": id = value
            case "--input-path": inputPaths.append(URL(fileURLWithPath: value))
            case "--output-path": outputPath = URL(fileURLWithPath: value)
            case "--output-type": outputType = value
            case "--timeout":
                guard let parsed = Int(value) else { throw ShortcutsError.invalidRunInput }
                timeoutSeconds = parsed
            case "--confirm": confirmation = value
            default: break
            }
            index += 2
        }
        guard apply, confirmation == "RUN SHORTCUT" else { throw ShortcutsError.confirmationRequired }
        guard let id else { throw ShortcutsError.invalidRunInput }
        return ShortcutRunArguments(id: id, inputPaths: inputPaths, outputPath: outputPath, outputType: outputType, timeoutSeconds: timeoutSeconds)
    }

    private static func parseShortcutMoveArguments(_ arguments: [String]) throws -> ShortcutMoveArguments {
        var id: String?
        var destinationFolderID: String?
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--id", "--destination-folder-id", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw ShortcutsError.invalidIdentifier }
            switch option {
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            default:
                guard index + 1 < arguments.count else { throw ShortcutsError.invalidIdentifier }
                let value = arguments[index + 1]
                if option == "--id" { id = value }
                else if option == "--destination-folder-id" { destinationFolderID = value }
                else { confirmation = value }
                index += 2
            }
        }
        guard let id, let destinationFolderID, !(apply && dryRun), !(!apply && confirmation != nil) else {
            throw ShortcutsError.invalidIdentifier
        }
        if apply && confirmation != "MOVE SHORTCUT" { throw ShortcutsError.confirmationRequired }
        return ShortcutMoveArguments(id: id, destinationFolderID: destinationFolderID, apply: apply)
    }

    private static func parseSafariBookmarkPageArguments(_ arguments: [String]) throws -> SafariBookmarkPageArguments {
        var query = SafariBookmarkQuery()
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--text", "--url", "--folder-id", "--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else { throw SafariError.invalidInput }
            let value = arguments[index + 1]
            switch option {
            case "--text": guard !value.isEmpty && value.count <= 500 else { throw SafariError.invalidInput }; query.text = value
            case "--url": guard validSafariHTTPURL(value) else { throw SafariError.invalidInput }; query.url = value
            case "--folder-id": query.folderID = value
            case "--limit": guard let parsed = Int(value) else { throw SafariError.invalidInput }; limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }
        return .init(query: query, limit: limit, cursor: cursor)
    }

    private static func parseSafariReadingListPageArguments(_ arguments: [String]) throws -> SafariReadingListPageArguments {
        var query = SafariReadingListQuery()
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--text", "--url", "--read", "--limit", "--cursor"].contains(option),
                  seen.insert(option).inserted, index + 1 < arguments.count else { throw SafariError.invalidInput }
            let value = arguments[index + 1]
            switch option {
            case "--text": guard !value.isEmpty && value.count <= 500 else { throw SafariError.invalidInput }; query.text = value
            case "--url": guard validSafariHTTPURL(value) else { throw SafariError.invalidInput }; query.url = value
            case "--read":
                guard let parsed = ["true": true, "false": false][value] else { throw SafariError.invalidInput }
                query.read = parsed
            case "--limit": guard let parsed = Int(value) else { throw SafariError.invalidInput }; limit = parsed
            case "--cursor": cursor = value
            default: break
            }
            index += 2
        }
        return .init(query: query, limit: limit, cursor: cursor)
    }

    private static func parseSafariReadingListAddArguments(_ arguments: [String]) throws -> SafariReadingListAddArguments {
        var inputURL: URL?
        var useStdin = false
        var apply = false
        var dryRun = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--input", "--stdin", "--dry-run", "--apply"].contains(option), seen.insert(option).inserted else {
                throw SafariError.invalidInput
            }
            switch option {
            case "--stdin": useStdin = true; index += 1
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            case "--input":
                guard index + 1 < arguments.count else { throw SafariError.invalidInput }
                inputURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            default: throw SafariError.invalidInput
            }
        }
        guard useStdin != (inputURL != nil), apply != dryRun else { throw SafariError.invalidInput }
        let data: Data
        if useStdin {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else if let inputURL {
            guard let values = try? inputURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? SafariReadingListAddInput.maximumInputBytes + 1) <= SafariReadingListAddInput.maximumInputBytes,
                  let value = try? Data(contentsOf: inputURL) else { throw SafariError.invalidInput }
            data = value
        } else { throw SafariError.invalidInput }
        guard !data.isEmpty, data.count <= SafariReadingListAddInput.maximumInputBytes else { throw SafariError.invalidInput }
        return .init(data: data, apply: apply)
    }

    private static func safariLocalMutationCommand(collection: String, action: String) throws -> SafariLocalMutationCommand {
        switch (collection, action) {
        case ("bookmarks", "create"): .bookmarkCreate
        case ("bookmarks", "edit"): .bookmarkEdit
        case ("bookmarks", "move"): .bookmarkMove
        case ("bookmarks", "delete"): .bookmarkDelete
        case ("folders", "create"): .folderCreate
        case ("folders", "rename"): .folderRename
        case ("folders", "move"): .folderMove
        case ("folders", "delete"): .folderDelete
        default: throw SafariError.invalidInput
        }
    }

    private static func parseSafariLocalMutationArguments(_ arguments: [String]) throws -> SafariLocalMutationArguments {
        var inputURL: URL?
        var useStdin = false
        var apply = false
        var dryRun = false
        var confirmation: String?
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--input", "--stdin", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw SafariError.invalidInput }
            switch option {
            case "--stdin": useStdin = true; index += 1
            case "--dry-run": dryRun = true; index += 1
            case "--apply": apply = true; index += 1
            case "--input", "--confirm":
                guard index + 1 < arguments.count else { throw SafariError.invalidInput }
                if option == "--input" { inputURL = URL(fileURLWithPath: arguments[index + 1]) }
                else { confirmation = arguments[index + 1] }
                index += 2
            default: throw SafariError.invalidInput
            }
        }
        guard useStdin != (inputURL != nil), !(apply && dryRun), !(!apply && confirmation != nil) else {
            throw SafariError.invalidInput
        }
        let data: Data
        if useStdin {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else if let inputURL {
            guard let values = try? inputURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? SafariLocalMutationInput.maximumInputBytes + 1) <= SafariLocalMutationInput.maximumInputBytes,
                  let value = try? Data(contentsOf: inputURL) else { throw SafariError.invalidInput }
            data = value
        } else { throw SafariError.invalidInput }
        guard !data.isEmpty, data.count <= SafariLocalMutationInput.maximumInputBytes else { throw SafariError.invalidInput }
        return .init(data: data, apply: apply, confirmation: confirmation)
    }

    private static func validSafariHTTPURL(_ value: String) -> Bool {
        guard value.utf8.count <= 4_096, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return false }
        return true
    }

    private static func printHelp() {
        print("""
        mpia \(CLIVersion.current) — local macOS data CLI for agents and developers

        Usage:
          mpia --version | -v
          mpia manifest --format json
          mpia resources --format json
          mpia contacts <command> [options]
          mpia mail <command> [options]
          mpia calendar <command> [options]
          mpia reminders <command> [options]
          mpia photos <command> [options]
          mpia notes <command> [options]
          mpia shortcuts <command> [options]
          mpia safari <command> [options]

        Unified resources:
          resources --format json                List Contacts, Mail, Calendar, Reminders, Photos, Notes, Shortcuts, and Safari resources
                                             with selection, permission, and limitations

        Safari 0.8 commands:
          permission --format json           Report Bookmarks.plist readability and Safari Automation status
          permission --request --format json Explicitly request Safari Automation consent
          bookmarks list [--folder-id <opaque-id>] [--limit <1...200>]
            [--cursor <cursor>] --format json List folders and bookmarks; Reading List is excluded
          bookmarks query [--text <text>] [--url <http-url>]
            [--folder-id <opaque-id>] [--limit <1...200>]
            [--cursor <cursor>] --format json Query bookmark metadata with AND filters
          bookmarks get --id <opaque-id> --format json
                                             Read one bookmark or folder
          bookmarks create|edit|move|delete --input <file>|--stdin
            [--dry-run|--apply] [--confirm <phrase>] --format json
                                             Guarded local-only bookmark CRUD
          folders create|rename|move|delete --input <file>|--stdin
            [--dry-run|--apply] [--confirm <phrase>] --format json
                                             Guarded local-only folder CRUD
          reading-list list [--read true|false] [--limit <1...200>]
            [--cursor <cursor>] --format json List Reading List metadata
          reading-list query [--text <text>] [--url <http-url>]
            [--read true|false] [--limit <1...200>]
            [--cursor <cursor>] --format json Query Reading List with AND filters
          reading-list get --id <opaque-id> --format json
                                             Read one Reading List item
          reading-list add --input <file>|--stdin --dry-run|--apply --format json
                                             Add through Safari's official Apple Event;
                                             strict JSON: url, optional title/previewText

        Safari 0.8 boundary:
          Reads parse ~/Library/Safari/Bookmarks.plist as a bounded, read-only
          snapshot and may require Full Disk Access. Reading List add is the
          only mutation and uses Safari Automation with five-second timeout and
          immediate read-back. Pending/unknown outcomes must not be retried.
          Bookmark/folder mutation is explicitly local-only: dry-run is the
          default, apply requires the returned source hash, Safari fully quit,
          private recovery, atomic swap, and read-back. It does not sync to iCloud.

        Shortcuts 0.7 commands:
          permission --format json           Report Shortcuts Events Automation status without prompting
          permission --request --format json Explicitly request Shortcuts Automation consent
          list [--folder-id <opaque-id>] [--limit <1...200>]
            [--cursor <cursor>] --format json List bounded shortcut metadata
          get --id <opaque-id> --format json  Read one shortcut's public metadata
          run --id <opaque-id> [--input-path <file> ...]
            [--output-path <file>] [--output-type <uti>] [--timeout <1...300>]
            --apply --confirm "RUN SHORTCUT" --format json
                                             Run one explicitly selected shortcut;
                                             timeout outcomes must not be retried
          folders [--limit <1...200>] [--cursor <cursor>] --format json
                                             List shortcut folders with opaque IDs
          move --id <opaque-id> --destination-folder-id <opaque-id>
            [--dry-run] --format json         Preview a folder move (default)
          move --id <opaque-id> --destination-folder-id <opaque-id>
            --apply --confirm "MOVE SHORTCUT" --format json
                                             Move and immediately verify folder identity
          author validate --source <file.cherri> --format json
                                             Validate bounded managed Cherri source and
                                             compile an unsigned artifact privately
          author build --source <file.cherri> --output <file.shortcut>
            [--signing-mode people-who-know-me|anyone] --format json
                                             Build and sign without importing; refuses
                                             overwrite and never echoes source content
          create --source <file.cherri> [--signing-mode people-who-know-me|anyone]
            [--dry-run] [--idempotent] --format json
                                             Build a private preview; dry-run is default
          create --source <file.cherri> [--signing-mode people-who-know-me|anyone]
            --apply [--idempotent] --confirm "CREATE MANAGED SHORTCUT" --format json
                                             Open a visible Shortcuts.app import and
                                             register only unique read-back confirmation
          update --id <managed-opaque-id> --source <file.cherri>
            --expected-source-sha256 <sha256> --strategy replace|retain-old
            [--dry-run] [--signing-mode people-who-know-me|anyone] --format json
                                             Preview only a registry-managed update
          update --id <managed-opaque-id> --source <file.cherri>
            --expected-source-sha256 <sha256> --strategy replace|retain-old
            --apply --confirm "UPDATE MANAGED SHORTCUT" --format json
                                             Import and verify before atomically moving
                                             registry identity; never deletes old first
          managed list --format json        List private managed identities and hashes
          managed forget --id <managed-opaque-id> [--dry-run] --format json
                                             Preview registry-only removal
          managed forget --id <managed-opaque-id> --apply
            --confirm "FORGET MANAGED SHORTCUT" --format json
                                             Remove registry/receipt only; never deletes
                                             the Shortcut from Shortcuts.app
          edit inspect --input <local.cherri|local.shortcut> --format json
                                             Classify one bounded local input without
                                             importing, opening, storing, or echoing it
          edit plan --input <local.shortcut> --patch <plan.json>|--stdin --format json
                                             Validate four bounded semantic operations
                                             against an exact input SHA-256; read-only
          edit copy --input <local.shortcut> --patch <plan.json>|--stdin
            --expected-editor-name-sha256 <sha256> --dry-run --format json
                                             Preview replace_text or append-only
                                             insert_text on a verified copy;
                                             does not read or change Accessibility state
          edit copy --input <local.shortcut> --patch <plan.json>|--stdin
            --expected-editor-name-sha256 <sha256> --apply
            --confirm "EDIT SHORTCUT COPY" --format json
                                             Duplicate the exact visible editor, change
                                             only allowlisted semantic actions, and verify
                                             every step without modifying the original
          edit ui-inspect --format json      Inspect bounded Shortcuts AX structure without
                                             prompting, activating, clicking, or typing

        Shortcuts boundary:
          Uses only the system shortcuts CLI and public Shortcuts Events
          scripting dictionary. Names are display values, never identity.
          Metadata includes action count but never claims to expose the action
          graph or parameters. Private Shortcuts databases are never accessed.
          Authoring is experimental, requires optional Cherri 2.3.x, forbids
          packages/references/file embedding/raw actions/inline secrets, and
          never uses HubSign or another remote signing service.
          Experimental 0.7.2 inspection follows no symlinks and reads no private
          database. It accepts local files only; iCloud share links and other
          URI inputs are rejected without network, redirect, clipboard, or import.
          Opaque/signed artifacts,
          unsupported actions, secrets, and device-bound references require
          manual migration. Edit planning supports insert_text, replace_text,
          delete_action, and move_action. Public apply accepts replace_text,
          append-only insert_text when the graph already contains a Text action,
          bounded all-delete plans that leave at least one action, and bounded
          all-move plans; it always edits a verified duplicate. Move uses exact
          reorder identifiers and complete visual-order read-back. Middle/no-source
          insert, mixed-operation plans, same-index moves, and equal-neighbor
          moves are rejected.
          Planning never writes.
          UI inspection returns only counts/status and never labels, titles, or
          identifiers. It cannot perform an Accessibility action.

        Calendar commands:
          permission                         Request full Calendar access
          sources --format json              List EventKit sources and selected iCloud source
          calendars --format json            List calendars in the selected iCloud source
          query --start <iso8601> --end <iso8601>
            [--calendar <id|title>] [--title <text>]
            [--limit <1...200>] [--cursor <cursor>] --format json
                                             Query a bounded event page
          conflicts --start <iso8601> --end <iso8601> [--calendar <id|title>]
                                             Detect strict event-time overlaps (max 200 events)
          get --id <event-id> --format json  Read one event
          create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
                                             Create an event in an iCloud calendar
          edit --id <event-id> --input <file>|--stdin --dry-run|--apply
            [--span this|future] --format json
                                             Update one event or future recurrence instances
          delete --id <event-id> --dry-run [--span this|future] --format json
          delete --id <event-id> --apply --confirm "DELETE EVENT"
            [--span this|future] --format json
                                             Delete one event or future recurrence instances

        Calendar selection and data:
          Add --source iCloud or --source <source-identifier> to a Calendar
          command. The default is the unique verified iCloud CalDAV source.
          Query accepts --calendar <identifier|title>. Create accepts calendarID
          in JSON; without it, the writable iCloud default calendar is used.
          Dates use ISO 8601. timeZone uses an IANA identifier such as Asia/Tokyo.
          All-day create/edit uses YYYY-MM-DD with an exclusive end date.
          alarms accepts relativeMinutes or absoluteDate; [] clears all alarms.
          Attendees are returned by reads but are read-only in 0.3.

        Reminders 0.4 commands:
          permission                         Request full Reminders access
          sources --format json              List reminder-capable EventKit sources
          lists --format json                List reminder lists in the selected iCloud source
          query [--status incomplete|completed|all]
            [--due-start <iso8601>] [--due-end <iso8601>]
            [--list <id|title>] [--title <text>]
            [--limit <1...200>] [--cursor <cursor>] --format json
                                             Query a bounded reminder page
          get --id <reminder-id> --format json
                                             Read one reminder by opaque ID
          create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
                                             Preview or create a reminder in writable iCloud list
          edit --id <reminder-id> --input <file>|--stdin --dry-run|--apply --format json
                                             Partially update one reminder
          complete --id <reminder-id> --dry-run|--apply --format json
          reopen --id <reminder-id> --dry-run|--apply --format json
                                             Change completion state; repeated apply is a safe no-op
          delete --id <reminder-id> --dry-run --format json
          delete --id <reminder-id> --apply --confirm "DELETE REMINDER" --format json
                                             Delete one reminder from its writable iCloud list

        Reminders selection:
          Add --source iCloud or --source <source-identifier>. The default is
          the unique verified iCloud CalDAV source containing reminder lists.
          Dry-run never calls EventKit save. Apply saves once and returns
          read-back verification; --idempotent adds a private 60-second receipt.
          Delete apply requires the exact confirmation phrase and reports either
          confirmed absence or accepted removal with read-back still pending.
          Edit uses patch semantics: omitted fields remain unchanged, null clears
          nullable fields, and values replace fields. Completion uses separate commands.
          Complete/reopen set or clear completionDate. Recurring completion may
          return the next visible occurrence separately as nextOccurrence.

        Photos 0.5 commands:
          permission --format json           Report Photos read authorization without prompting
          permission --request --format json Request Photos read/write authorization
          albums [--kind user|smart|all] [--limit <1...200>]
            [--cursor <cursor>] --format json
                                             List user folders/albums and smart albums
          query --start <iso8601> --end <iso8601> [--album-id <opaque-id>]
            [--media image|video|audio|unknown] [--favorite true|false]
            [--include-hidden] [--include-location] [--limit <1...200>]
            [--cursor <cursor>] --format json List bounded asset metadata
          get --id <opaque-id> [--include-location] --format json
                                             Read one asset's metadata
          export --id <opaque-id> --output <file>
            [--variant original|current|paired-video|adjustment-data]
            [--allow-network] --format json   Export one explicitly selected resource

        Photos safety:
          Album discovery preserves hierarchy and duplicate titles, using opaque
          IDs for selection. Query/get never download media; hidden assets and
          exact location require explicit options. Limited access reports
          complete=false. Asset query range is limited to 366 days. Export
          defaults to original, offline-only, no overwrite, and private output.

        Notes 0.6 read commands and guarded 0.6.1/0.6.2 writes:
          permission --format json           Report Notes.app Automation status without prompting
          permission --request --format json Explicitly request Notes.app Automation consent
          accounts --format json             List bounded Notes accounts with opaque IDs
          folders [--account-id <id>] [--parent-id <id>]
            [--limit <1...200>] [--cursor <cursor>] --format json
                                             List bounded nested-folder metadata
          folder create --input <file>|--stdin [--dry-run|--apply] [--idempotent]
            --format json                    Create under an explicit opaque parent
                                             or account root expressed as JSON null
          folder rename --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] --format json Rename with current-name hash guard
          folder move --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] --format json Preview with name-hash and parent guards;
                                             apply fails closed on Notes 4.13
          folder delete --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] [--confirm "DELETE EMPTY NOTES FOLDER"]
            --format json                    Delete only an empty, non-default,
                                             non-shared folder after fresh checks
          query [--account-id <id>] [--folder-id <id>] [--title <text>]
            [--modified-after <iso8601>] [--limit <1...200>]
            [--cursor <cursor>] --format json List metadata-only note records
          get --id <opaque-id> [--body none|plaintext|html]
            [--include-attachments] --format json
                                             Read one note; body defaults to none
          write-account status --format json  Show the bound iCloud write account
          write-account bind --account-id <id> [--dry-run|--apply]
            [--confirm "BIND ICLOUD NOTES"] --format json
                                             Bind a user-confirmed iCloud account
          write-account clear [--dry-run|--apply]
            [--confirm "CLEAR ICLOUD NOTES"] --format json
                                             Clear the local write-account binding
          create --input <file>|--stdin [--dry-run|--apply] [--idempotent]
            --format json                    Create in one explicit bound folder
          rename --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] --format json Rename with modification-date guard
          move --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] --format json Move to one explicit bound folder
          delete --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] [--confirm "DELETE NOTE"] --format json
                                             Move one note to Notes Recently Deleted;
                                             permanent deletion remains UI-only
          edit-body --id <opaque-id> --input <file>|--stdin
            [--dry-run|--apply] --format json Replace a proven-simple body with
                                             modification-date and body-hash guards

        Notes boundary:
          Notes uses the public Notes.app scripting dictionary through Apple
          Events; there is no public Notes content Framework. Discovery reads
          account/folder structure and explicitly requested note metadata.
          Body reads require explicit plaintext/html opt-in and are capped at
          256 KiB; locked notes fail closed. Query scans at most 200 note metadata records in five
          seconds and returns complete=false if that bound is reached. It
          never reads private Notes databases,
          CloudKit containers, caches, or GUI coordinates.
          Writes require a locally bound, user-confirmed iCloud account and
          explicit non-shared opaque folder IDs. Note rename and move require an
          expected modification date. Folder rename/move use current-name SHA-256
          and explicit current/destination parents because Notes exposes no folder
          modification date; default/shared/cross-account/cyclic or ambiguous
          duplicate-name operations fail closed. Body replacement additionally requires
          the current plaintext SHA-256 and rejects attachments or unsupported
          rich structures. Attachment mutation remains unsupported. Folder move
          and folder-delete apply fail closed on Notes 4.13; note deletion is
          recoverable soft deletion only, while permanent deletion remains UI-only.

        Mail commands:
          doctor --format json               Inspect Mail store, schema, and permissions
          accounts --format json             List privacy-safe local account scopes
          mailboxes [--account-id <id>] --format json
                                             List mailboxes and local counts
          threads [--limit <1...200>] --format json
                                             List stable conversation groups
          query [filters] [--limit <n>] [--cursor <cursor>] --format json
                                             Query bounded message metadata
          search --text <text> [filters] [--limit <n>] --format json
                                             Search cached local message bodies
          get --id <id> [--content metadata|text] --format json
                                             Read one message; metadata is default
          get --id <id> --content raw --output <file|->
                                             Export exact cached RFC 822 bytes
          reveal --id <id> --format json     Open one message visibly in Mail.app
          attachments verify --id <id> --format json
                                             Compare SQLite and MIME attachment counts
          attachments export --id <id> --output <directory> --format json
                                             Export cached attachments safely

        Mail query filters:
          --account-id <id> --mailbox-id <id> --from <text> --to <text>
          --subject <text> --received-after <iso8601> --received-before <iso8601>
          --unread --flagged --has-attachment --limit <1...200> --cursor <cursor>

        Mail text search:
          Reads only cached EMLX text, scans at most 200 candidates, and has a
          one-second budget. It never falls back to Mail.app or remote content.

        Contacts commands:
          permission                         Check/request Contacts permission
          containers                        List available Contacts containers
          container                          Show the required iCloud container
          count                              Count contacts
          list [--limit <1...200>] [--cursor <cursor>] --format json
                                             List a bounded page of contacts
          get --external-id <id> [--format json]
                                             Read one contact
          avatar verify --external-id <id> [--format json]
                                             Verify avatar read-back without writing
          avatar replace --external-id <id> --image <file> --dry-run
          avatar replace --external-id <id> --image <file> --apply
            --confirm "RECREATE CONTACT"
                                             Recreate a record with a new avatar
          query [conditions] [--limit <1...200>] [--cursor <cursor>] --format json
                                             Search a bounded contact page (max 3 AND conditions)
                                             Supports --kind person|organization
          create --input <file>|--stdin --dry-run|--apply [--idempotent]
                                             Create a person or organization
          edit --external-id <id> --input <file>|--stdin --dry-run|--apply
                                             Partial update; null clears a field
          edit --external-id <id> --image <file> --dry-run|--apply
                                             Set a normalized avatar
          delete --external-id <id> --dry-run
          delete --external-id <id> --apply --confirm "DELETE CONTACT"
                                             Delete one contact
            [--ignore-not-found]             Make repeated deletion safe
          external-id migrate --from <id> --to <id> --dry-run
          external-id migrate --from <id> --to <id> --apply
            --confirm "CHANGE EXTERNAL ID"
                                             Migrate an external ID
          export --format json [--output <file>]
                                             Export a JSON snapshot

        Container selection:
          Add --container iCloud or --container <container-identifier> to a
          Contacts command. The default is the verified iCloud container.
          For create/edit JSON, use --stdin for one document from stdin, or
          --input <file> for a file.

        JSON contract:
          Version: 0.1 (independent from the CLI release version)
          Exit codes: 0 success, 1 unexpected CLI error, 2 Contacts error,
            3 ambiguous/not-found query error, 4 Mail error, 5 Calendar error,
            6 Reminders error, 7 Photos error, 8 Notes error, 9 Shortcuts error,
            10 Safari error,
            64 usage or invalid query
          Success: {"ok": true, "contractVersion": "0.1", "data": ...}
          Failure: {"ok": false, "contractVersion": "0.1", "error": {"code": ..., "message": ...}}
          Add --format json to commands that support machine-readable output.

        Safety and limits:
          Mail.app metadata fallback is limited to 25 message candidates,
            always incomplete, and has no cursor; raw remains cache-only.
          Contacts writes target only the verified iCloud container.
          Calendar reads and writes target only the verified iCloud source.
          Reminders reads target only the verified iCloud source and lists.
          Writes require --dry-run or explicit --apply.
          Recurring event edit/delete requires --span this or --span future.
          Avatar input is limited to 10 MB; output is <= 1024 px and 200 KB.
          metadata remains in JSON and is not written to Apple Contacts.
        """)
    }
}
