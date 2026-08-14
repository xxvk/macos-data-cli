import Core
import Foundation

public struct ShortcutSemanticEditService: Sendable {
    public static let confirmationPhrase = "EDIT SHORTCUT COPY"

    typealias ApplyExecutor = @Sendable (
        ShortcutEditExecutionPlan,
        String,
        String?
    ) throws -> ShortcutSemanticMutationResult

    private let planService: ShortcutEditPlanService
    private let applyExecutor: ApplyExecutor

    public init() {
        self.planService = ShortcutEditPlanService()
        self.applyExecutor = { plan, expectedEditorNameSHA256, confirmation in
            let session = SystemShortcutAccessibilityMutationSession()
            let bridge = GuardedShortcutAccessibilityMutationBridge(plan: plan, session: session)
            return try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
                plan: plan,
                expectedEditorNameSHA256: expectedEditorNameSHA256,
                apply: true,
                confirmation: confirmation
            )
        }
    }

    init(
        planService: ShortcutEditPlanService = ShortcutEditPlanService(),
        applyExecutor: @escaping ApplyExecutor
    ) {
        self.planService = planService
        self.applyExecutor = applyExecutor
    }

    public func execute(
        inputURL: URL,
        patchURL: URL,
        expectedEditorNameSHA256: String,
        apply: Bool,
        confirmation: String?
    ) throws -> ShortcutSemanticMutationResult {
        let patchData = try ShortcutLocalInputReader.read(
            patchURL,
            allowedExtensions: ["json"],
            maximumBytes: ShortcutEditPlanService.maximumPatchBytes
        )
        return try execute(
            inputURL: inputURL,
            patchData: patchData,
            expectedEditorNameSHA256: expectedEditorNameSHA256,
            apply: apply,
            confirmation: confirmation
        )
    }

    public func execute(
        inputURL: URL,
        patchData: Data,
        expectedEditorNameSHA256: String,
        apply: Bool,
        confirmation: String?
    ) throws -> ShortcutSemanticMutationResult {
        guard Self.isSHA256(expectedEditorNameSHA256) else {
            throw ShortcutsError.editPlanInvalid
        }
        let plan = try planService.prepare(inputURL: inputURL, patchData: patchData)
        let provenPublicOperations = plan.operations.allSatisfy { operation in
            operation.summary.operation == .replaceText || operation.summary.operation == .insertText
        }
        let provenDeleteOperations = plan.operations.allSatisfy { $0.summary.operation == .deleteAction }
        let provenMoveOperations = plan.operations.allSatisfy { $0.summary.operation == .moveAction }

        if apply {
            guard plan.publicResult.canApplySemanticEdit
                    && (provenPublicOperations || provenDeleteOperations || provenMoveOperations) else {
                throw ShortcutsError.editCapabilityUnsupported
            }
            guard confirmation == Self.confirmationPhrase else {
                throw ShortcutsError.editConfirmationRequired
            }
            return try applyExecutor(plan, expectedEditorNameSHA256, confirmation)
        }

        guard plan.publicResult.canApplySemanticEdit
                && (provenPublicOperations || provenDeleteOperations || provenMoveOperations) else {
            throw ShortcutsError.editCapabilityUnsupported
        }
        guard confirmation == nil else { throw ShortcutsError.editPlanInvalid }
        return ShortcutSemanticMutationResult(
            operation: "semantic_edit_copy",
            status: .preview,
            inputSHA256: plan.publicResult.inputSHA256,
            planSHA256: plan.publicResult.planSHA256,
            operationCount: plan.publicResult.operationCount,
            verifiedOperationCount: 0,
            originalPreserved: true,
            finalActionCount: plan.publicResult.initialActionCount,
            canRetryAutomatically: false,
            nextAction: "Review the redacted plan. No Accessibility state was read or changed. Apply only with an exact editor-name SHA-256 and confirmation."
        )
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}
