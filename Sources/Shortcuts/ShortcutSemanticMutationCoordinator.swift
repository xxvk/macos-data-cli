import Core
import Foundation

public enum ShortcutSemanticActionKind: String, Codable, Equatable, Sendable {
    case text
    case comment
    case nothing
}

public struct ShortcutSemanticActionState: Codable, Equatable, Sendable {
    public let kind: ShortcutSemanticActionKind
    public let valueSHA256: String?

    public init(kind: ShortcutSemanticActionKind, valueSHA256: String?) {
        self.kind = kind
        self.valueSHA256 = valueSHA256
    }
}

public struct ShortcutSemanticEditorState: Equatable, Sendable {
    public let editorNameSHA256: String
    public let actions: [ShortcutSemanticActionState]
    public let candidateCount: Int
    public let bounded: Bool
    public let isRecoveryCandidate: Bool

    public init(
        editorNameSHA256: String,
        actions: [ShortcutSemanticActionState],
        candidateCount: Int,
        bounded: Bool,
        isRecoveryCandidate: Bool
    ) {
        self.editorNameSHA256 = editorNameSHA256
        self.actions = actions
        self.candidateCount = candidateCount
        self.bounded = bounded
        self.isRecoveryCandidate = isRecoveryCandidate
    }
}

public protocol ShortcutSemanticMutationBridging: Sendable {
    func inspectEditor() throws -> ShortcutSemanticEditorState
    func createRecoveryCandidate() throws -> ShortcutSemanticEditorState
    func perform(_ operation: ShortcutEditExecutionOperation) throws
}

public enum ShortcutSemanticMutationStatus: String, Codable, Equatable, Sendable {
    case preview
    case readbackConfirmed = "readback_confirmed"
    case outcomeUnknown = "outcome_unknown"
}

public struct ShortcutSemanticMutationResult: Codable, Equatable, Sendable {
    public let operation: String
    public let status: ShortcutSemanticMutationStatus
    public let inputSHA256: String
    public let planSHA256: String
    public let operationCount: Int
    public let verifiedOperationCount: Int
    public let originalPreserved: Bool
    public let finalActionCount: Int?
    public let canRetryAutomatically: Bool
    public let nextAction: String
}

public struct ShortcutSemanticMutationCoordinator<Bridge: ShortcutSemanticMutationBridging>: Sendable {
    public static var confirmationPhrase: String { "EDIT SHORTCUT COPY" }

    private let bridge: Bridge

    public init(bridge: Bridge) {
        self.bridge = bridge
    }

    public func mutate(
        plan: ShortcutEditExecutionPlan,
        expectedEditorNameSHA256: String,
        apply: Bool,
        confirmation: String?
    ) throws -> ShortcutSemanticMutationResult {
        let publicPlan = plan.publicResult
        try validatePlan(publicPlan, expectedEditorNameSHA256: expectedEditorNameSHA256)
        guard executionValuesMatch(plan) else { throw ShortcutsError.editSourceConflict }

        guard apply else {
            return result(
                plan: publicPlan,
                status: .preview,
                verifiedOperationCount: 0,
                originalPreserved: true,
                finalActionCount: publicPlan.initialActionCount,
                nextAction: "Review the redacted plan. No Accessibility state was read or changed."
            )
        }
        guard confirmation == Self.confirmationPhrase else {
            throw ShortcutsError.editConfirmationRequired
        }

        let original: ShortcutSemanticEditorState
        do {
            original = try bridge.inspectEditor()
        } catch let error as ShortcutsError {
            switch error {
            case .permissionRequired, .permissionDenied, .targetUnavailable, .targetNotRunning:
                throw error
            default:
                throw ShortcutsError.editEditorConflict
            }
        } catch {
            throw ShortcutsError.editEditorConflict
        }
        guard isUniqueBounded(original),
              !original.isRecoveryCandidate,
              original.editorNameSHA256 == expectedEditorNameSHA256,
              original.actions.count == publicPlan.initialActionCount else {
            throw ShortcutsError.editEditorConflict
        }
        var preflightActions = original.actions
        guard plan.operations.allSatisfy({ applyOperation($0.summary, to: &preflightActions) }),
              preflightActions.count == publicPlan.finalActionCount else {
            throw ShortcutsError.editEditorConflict
        }

        let recovery: ShortcutSemanticEditorState
        do {
            recovery = try bridge.createRecoveryCandidate()
        } catch {
            throw ShortcutsError.editRecoveryFailed
        }
        guard isUniqueBounded(recovery),
              recovery.isRecoveryCandidate,
              recovery.editorNameSHA256 != original.editorNameSHA256,
              recovery.actions == original.actions else {
            throw ShortcutsError.editRecoveryFailed
        }

        var expectedActions = recovery.actions
        var verified = 0
        for operation in plan.operations {
            guard applyOperation(operation.summary, to: &expectedActions) else {
                throw ShortcutsError.editEditorConflict
            }
            do {
                try bridge.perform(operation)
                let readback = try bridge.inspectEditor()
                guard isUniqueBounded(readback),
                      readback.isRecoveryCandidate,
                      readback.editorNameSHA256 == recovery.editorNameSHA256,
                      readback.actions == expectedActions else {
                    return unknown(plan: publicPlan, verified: verified)
                }
                verified += 1
            } catch {
                return unknown(plan: publicPlan, verified: verified)
            }
        }

        guard expectedActions.count == publicPlan.finalActionCount else {
            return unknown(plan: publicPlan, verified: verified)
        }
        return result(
            plan: publicPlan,
            status: .readbackConfirmed,
            verifiedOperationCount: verified,
            originalPreserved: true,
            finalActionCount: expectedActions.count,
            nextAction: "The recovery copy was verified after every operation. Keep the original until the copy is reviewed manually."
        )
    }

    private func validatePlan(_ plan: ShortcutEditPlanResult, expectedEditorNameSHA256: String) throws {
        guard isSHA256(expectedEditorNameSHA256),
              isSHA256(plan.inputSHA256),
              isSHA256(plan.planSHA256),
              plan.operation == "edit_plan",
              plan.experimental,
              plan.operationCount == plan.operations.count,
              (1...ShortcutEditPlanService.maximumOperationCount).contains(plan.operationCount),
              plan.initialActionCount > 0,
              plan.finalActionCount > 0,
              plan.operations.enumerated().allSatisfy({ validShape($0.element, sequence: $0.offset) }) else {
            throw ShortcutsError.editPlanInvalid
        }
    }

    private func executionValuesMatch(_ plan: ShortcutEditExecutionPlan) -> Bool {
        guard plan.operations.count == plan.publicResult.operations.count else { return false }
        return zip(plan.operations, plan.publicResult.operations).allSatisfy { execution, summary in
            guard execution.summary == summary else { return false }
            switch summary.operation {
            case .insertText, .replaceText:
                guard let value = execution.textValue else { return false }
                let data = Data(value.utf8)
                return summary.valueBytes == data.count
                    && summary.valueSHA256 == CherriSourceValidator.hash(data)
            case .deleteAction, .moveAction:
                return execution.textValue == nil
            }
        }
    }

    private func validShape(_ operation: ShortcutEditOperationSummary, sequence: Int) -> Bool {
        guard operation.sequence == sequence else { return false }
        switch operation.operation {
        case .insertText, .replaceText:
            return operation.index != nil
                && operation.fromIndex == nil
                && operation.toIndex == nil
                && operation.valueBytes.map { (0...ShortcutEditPlanService.maximumValueBytes).contains($0) } == true
                && operation.valueSHA256.map(isSHA256) == true
        case .deleteAction:
            return operation.index != nil
                && operation.fromIndex == nil
                && operation.toIndex == nil
                && operation.valueBytes == nil
                && operation.valueSHA256 == nil
        case .moveAction:
            return operation.index == nil
                && operation.fromIndex != nil
                && operation.toIndex != nil
                && operation.valueBytes == nil
                && operation.valueSHA256 == nil
        }
    }

    private func isUniqueBounded(_ state: ShortcutSemanticEditorState) -> Bool {
        state.bounded && state.candidateCount == 1 && isSHA256(state.editorNameSHA256) && !state.actions.isEmpty
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private func applyOperation(_ operation: ShortcutEditOperationSummary, to actions: inout [ShortcutSemanticActionState]) -> Bool {
        switch operation.operation {
        case .insertText:
            guard let index = operation.index,
                  (0...actions.count).contains(index),
                  let hash = operation.valueSHA256,
                  isSHA256(hash) else { return false }
            actions.insert(.init(kind: .text, valueSHA256: hash), at: index)
        case .replaceText:
            guard let index = operation.index,
                  actions.indices.contains(index),
                  actions[index].kind == .text,
                  let hash = operation.valueSHA256,
                  isSHA256(hash) else { return false }
            actions[index] = .init(kind: .text, valueSHA256: hash)
        case .deleteAction:
            guard let index = operation.index,
                  actions.indices.contains(index),
                  actions.count > 1 else { return false }
            actions.remove(at: index)
        case .moveAction:
            guard let from = operation.fromIndex,
                  let to = operation.toIndex,
                  actions.indices.contains(from),
                  actions.indices.contains(to) else { return false }
            let action = actions.remove(at: from)
            actions.insert(action, at: min(to, actions.count))
        }
        return true
    }

    private func unknown(plan: ShortcutEditPlanResult, verified: Int) -> ShortcutSemanticMutationResult {
        result(
            plan: plan,
            status: .outcomeUnknown,
            verifiedOperationCount: verified,
            originalPreserved: true,
            finalActionCount: nil,
            nextAction: "Do not retry automatically. Inspect the recovery copy and original in Shortcuts.app before choosing any next step."
        )
    }

    private func result(
        plan: ShortcutEditPlanResult,
        status: ShortcutSemanticMutationStatus,
        verifiedOperationCount: Int,
        originalPreserved: Bool,
        finalActionCount: Int?,
        nextAction: String
    ) -> ShortcutSemanticMutationResult {
        ShortcutSemanticMutationResult(
            operation: "semantic_edit_copy",
            status: status,
            inputSHA256: plan.inputSHA256,
            planSHA256: plan.planSHA256,
            operationCount: plan.operationCount,
            verifiedOperationCount: verifiedOperationCount,
            originalPreserved: originalPreserved,
            finalActionCount: finalActionCount,
            canRetryAutomatically: false,
            nextAction: nextAction
        )
    }
}
