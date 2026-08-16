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
import MessagesAdapter
import PhoneAdapter

extension MpiaCLI {
    static func handleShortcuts(_ arguments: [String]) throws -> Bool {
        let shortcutsPermission = ShortcutsPermissionService()
        let shortcutsStore = ShortcutsStore(permission: shortcutsPermission)
        let shortcutsAuthoring = CherriAuthoringBridge()
        let shortcutsAuthoringService = ShortcutsAuthoringService(builder: shortcutsAuthoring)
        let shortcutsAcquisition = ShortcutAcquisitionClassifier()
        let shortcutsEditPlan = ShortcutEditPlanService()
        let shortcutsSemanticEdit = ShortcutSemanticEditService()
        let shortcutsAccessibilityDiscovery = ShortcutAccessibilityDiscoveryService()
        switch arguments {
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
        default: return false
        }
        return true
    }
}
