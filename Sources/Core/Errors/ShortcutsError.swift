public enum ShortcutsError: Error, Equatable, CustomStringConvertible, Sendable {
    case permissionRequired
    case permissionDenied
    case targetUnavailable
    case targetNotRunning
    case automationUnknown
    case invalidIdentifier
    case invalidLimit
    case timedOut
    case executionFailed
    case incompleteMetadata
    case moveVerificationFailed
    case confirmationRequired
    case invalidRunInput
    case outputExists
    case outputTooLarge
    case runFailed
    case runOutcomeUnknown
    case authorSourceInvalid
    case authorSourceTooLarge
    case authorSourceForbidden
    case cherriUnavailable
    case cherriUnsupported
    case authorCompilationFailed
    case authorArtifactInvalid
    case authorSigningFailed
    case authorOutputExists
    case authorTimedOut
    case authorRegistryInvalid
    case authorManagedOnly
    case authorSourceConflict
    case authorNameConflict
    case authorImportFailed
    case authorImportOutcomeUnknown
    case authorCreateConfirmationRequired
    case authorUpdateConfirmationRequired
    case authorUpdateUnverifiable
    case authorForgetConfirmationRequired
    case acquisitionInputInvalid
    case acquisitionInputTooLarge
    case editPlanInvalid
    case editSourceConflict
    case editCapabilityUnsupported
    case editConfirmationRequired
    case editEditorConflict
    case editRecoveryFailed

    public var machineCode: String {
        switch self {
        case .permissionRequired: "SHORTCUTS_PERMISSION_REQUIRED"
        case .permissionDenied: "SHORTCUTS_PERMISSION_DENIED"
        case .targetUnavailable: "SHORTCUTS_TARGET_UNAVAILABLE"
        case .targetNotRunning: "SHORTCUTS_TARGET_NOT_RUNNING"
        case .automationUnknown: "SHORTCUTS_AUTOMATION_UNKNOWN"
        case .invalidIdentifier: "SHORTCUTS_INVALID_IDENTIFIER"
        case .invalidLimit: "SHORTCUTS_INVALID_LIMIT"
        case .timedOut: "SHORTCUTS_TIMEOUT"
        case .executionFailed: "SHORTCUTS_EXECUTION_FAILED"
        case .incompleteMetadata: "SHORTCUTS_INCOMPLETE_METADATA"
        case .moveVerificationFailed: "SHORTCUTS_MOVE_VERIFICATION_FAILED"
        case .confirmationRequired: "SHORTCUTS_CONFIRMATION_REQUIRED"
        case .invalidRunInput: "SHORTCUTS_INVALID_RUN_INPUT"
        case .outputExists: "SHORTCUTS_OUTPUT_EXISTS"
        case .outputTooLarge: "SHORTCUTS_OUTPUT_TOO_LARGE"
        case .runFailed: "SHORTCUTS_RUN_FAILED"
        case .runOutcomeUnknown: "SHORTCUTS_RUN_OUTCOME_UNKNOWN"
        case .authorSourceInvalid: "SHORTCUTS_AUTHOR_SOURCE_INVALID"
        case .authorSourceTooLarge: "SHORTCUTS_AUTHOR_SOURCE_TOO_LARGE"
        case .authorSourceForbidden: "SHORTCUTS_AUTHOR_SOURCE_FORBIDDEN"
        case .cherriUnavailable: "SHORTCUTS_CHERRI_UNAVAILABLE"
        case .cherriUnsupported: "SHORTCUTS_CHERRI_UNSUPPORTED"
        case .authorCompilationFailed: "SHORTCUTS_AUTHOR_COMPILATION_FAILED"
        case .authorArtifactInvalid: "SHORTCUTS_AUTHOR_ARTIFACT_INVALID"
        case .authorSigningFailed: "SHORTCUTS_AUTHOR_SIGNING_FAILED"
        case .authorOutputExists: "SHORTCUTS_AUTHOR_OUTPUT_EXISTS"
        case .authorTimedOut: "SHORTCUTS_AUTHOR_TIMEOUT"
        case .authorRegistryInvalid: "SHORTCUTS_AUTHOR_REGISTRY_INVALID"
        case .authorManagedOnly: "SHORTCUTS_AUTHOR_MANAGED_ONLY"
        case .authorSourceConflict: "SHORTCUTS_AUTHOR_SOURCE_CONFLICT"
        case .authorNameConflict: "SHORTCUTS_AUTHOR_NAME_CONFLICT"
        case .authorImportFailed: "SHORTCUTS_AUTHOR_IMPORT_FAILED"
        case .authorImportOutcomeUnknown: "SHORTCUTS_AUTHOR_IMPORT_OUTCOME_UNKNOWN"
        case .authorCreateConfirmationRequired: "SHORTCUTS_AUTHOR_CREATE_CONFIRMATION_REQUIRED"
        case .authorUpdateConfirmationRequired: "SHORTCUTS_AUTHOR_UPDATE_CONFIRMATION_REQUIRED"
        case .authorUpdateUnverifiable: "SHORTCUTS_AUTHOR_UPDATE_UNVERIFIABLE"
        case .authorForgetConfirmationRequired: "SHORTCUTS_AUTHOR_FORGET_CONFIRMATION_REQUIRED"
        case .acquisitionInputInvalid: "SHORTCUTS_ACQUISITION_INPUT_INVALID"
        case .acquisitionInputTooLarge: "SHORTCUTS_ACQUISITION_INPUT_TOO_LARGE"
        case .editPlanInvalid: "SHORTCUTS_EDIT_PLAN_INVALID"
        case .editSourceConflict: "SHORTCUTS_EDIT_SOURCE_CONFLICT"
        case .editCapabilityUnsupported: "SHORTCUTS_EDIT_CAPABILITY_UNSUPPORTED"
        case .editConfirmationRequired: "SHORTCUTS_EDIT_CONFIRMATION_REQUIRED"
        case .editEditorConflict: "SHORTCUTS_EDIT_EDITOR_CONFLICT"
        case .editRecoveryFailed: "SHORTCUTS_EDIT_RECOVERY_FAILED"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Shortcuts Automation permission requires consent. Run 'mpia shortcuts permission --request'."
        case .permissionDenied:
            "Shortcuts Automation permission was denied. Enable mpia for Shortcuts Events in System Settings > Privacy & Security > Automation."
        case .targetUnavailable:
            "Shortcuts Events is unavailable on this Mac."
        case .targetNotRunning:
            "Shortcuts Events could not be reached. Open Shortcuts.app and retry."
        case .automationUnknown:
            "Shortcuts Automation status could not be determined safely."
        case .invalidIdentifier:
            "The shortcut, folder, or cursor identifier is invalid or stale."
        case .invalidLimit:
            "Shortcuts page limit must be between 1 and 200."
        case .timedOut:
            "The bounded Shortcuts Apple Event timed out."
        case .executionFailed:
            "Shortcuts Events could not return a valid bounded response."
        case .incompleteMetadata:
            "The bounded Shortcuts metadata snapshot is incomplete; mutation is refused."
        case .moveVerificationFailed:
            "Shortcuts accepted the move but the destination folder could not be confirmed. Do not retry automatically; list and verify first."
        case .confirmationRequired:
            "Applying a shortcut move requires --confirm \"MOVE SHORTCUT\"."
        case .invalidRunInput:
            "Shortcut run input is invalid. Use at most 16 readable files, a 1...300 second timeout, and a valid output UTI."
        case .outputExists:
            "Shortcut output already exists; automatic overwrite is refused."
        case .outputTooLarge:
            "Shortcut text output exceeds the 256 KiB JSON response limit; use --output-path."
        case .runFailed:
            "The system shortcuts CLI reported that the shortcut failed."
        case .runOutcomeUnknown:
            "The shortcut exceeded its deadline. Its side effects may have occurred. Do not retry automatically; inspect the target state first."
        case .authorSourceInvalid:
            "The Cherri source must be a readable UTF-8 .cherri file with exactly one bounded #define name declaration."
        case .authorSourceTooLarge:
            "Cherri source exceeds the 256 KiB authoring limit."
        case .authorSourceForbidden:
            "Cherri source uses a forbidden include, package, reference, embedded file, raw action, custom action definition, or apparent inline secret."
        case .cherriUnavailable:
            "Cherri is not installed. Install the optional official compiler with Homebrew before using Shortcuts authoring."
        case .cherriUnsupported:
            "The installed Cherri version is outside the explicitly gated 2.3.x compatibility range."
        case .authorCompilationFailed:
            "Cherri rejected the source. Compiler output is intentionally not echoed because it may contain source data; run Cherri directly for local diagnosis."
        case .authorArtifactInvalid:
            "Cherri produced an invalid or unbounded unsigned Shortcut artifact."
        case .authorSigningFailed:
            "The system shortcuts signer rejected the generated artifact. This macOS/Shortcuts/Cherri combination is not authoring-compatible; no import was attempted."
        case .authorOutputExists:
            "The requested build output already exists; automatic overwrite is refused."
        case .authorTimedOut:
            "The bounded Cherri or system signing process exceeded its deadline and was stopped."
        case .authorRegistryInvalid:
            "The private managed-Shortcuts registry is missing, corrupt, or contains invalid opaque metadata."
        case .authorManagedOnly:
            "This operation is allowed only for a shortcut already tracked by the private mpia registry."
        case .authorSourceConflict:
            "The expected source SHA-256 does not match the managed registry. Refresh state and do not overwrite silently."
        case .authorNameConflict:
            "A shortcut with the managed source name already exists. Create refuses ambiguous replacement; use guarded managed update instead."
        case .authorImportFailed:
            "Shortcuts.app could not open the signed artifact for visible import. No successful import was confirmed."
        case .authorImportOutcomeUnknown:
            "The visible import was opened but its result could not be confirmed. Do not retry automatically; list Shortcuts and inspect the pending receipt first."
        case .authorCreateConfirmationRequired:
            "Applying managed Shortcut creation requires --confirm \"CREATE MANAGED SHORTCUT\"."
        case .authorUpdateConfirmationRequired:
            "Applying managed Shortcut update requires --confirm \"UPDATE MANAGED SHORTCUT\" and an explicit replace or retain-old strategy."
        case .authorUpdateUnverifiable:
            "The replacement cannot be distinguished safely through public Shortcuts metadata. Use retain-old or change the action count before applying."
        case .authorForgetConfirmationRequired:
            "Removing a managed registry entry requires --confirm \"FORGET MANAGED SHORTCUT\". This does not delete the Shortcut itself."
        case .acquisitionInputInvalid:
            "Shortcut acquisition requires one readable, non-symlink local .cherri or .shortcut regular file."
        case .acquisitionInputTooLarge:
            "Shortcut acquisition input exceeds the 10 MiB local inspection limit."
        case .editPlanInvalid:
            "The Shortcut edit plan is invalid, unbounded, or incompatible with the current semantic action graph."
        case .editSourceConflict:
            "The expected input SHA-256 does not match the inspected Shortcut artifact. Refresh the input and do not apply a stale plan."
        case .editCapabilityUnsupported:
            "This Shortcut artifact is not eligible for semantic editing. Use the reported manual migration route."
        case .editConfirmationRequired:
            "Applying a semantic Shortcut edit requires --confirm \"EDIT SHORTCUT COPY\"."
        case .editEditorConflict:
            "The visible Shortcut editor is ambiguous, unbounded, or no longer matches the reviewed edit plan. Refresh state and do not mutate it."
        case .editRecoveryFailed:
            "A distinct recovery copy preserving the original semantic action graph could not be confirmed. No edit was started."
        }
    }
}
