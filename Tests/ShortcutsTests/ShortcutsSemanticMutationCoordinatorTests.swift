import Foundation
import XCTest
import Core
@testable import ShortcutsAdapter

final class ShortcutsSemanticMutationCoordinatorTests: XCTestCase {
    func testPreviewNeverReadsOrMutatesAccessibilityBridge() throws {
        let bridge = MockSemanticMutationBridge(states: [])
        let coordinator = ShortcutSemanticMutationCoordinator(bridge: bridge)

        let result = try coordinator.mutate(
            plan: plan(operations: [operation(.replaceText, index: 0, value: "next")], initial: 1, final: 1),
            expectedEditorNameSHA256: hash("fixture"),
            apply: false,
            confirmation: nil
        )

        XCTAssertEqual(result.status, .preview)
        XCTAssertEqual(bridge.inspectCalls, 0)
        XCTAssertEqual(bridge.recoveryCalls, 0)
        XCTAssertEqual(bridge.performCalls, 0)
        XCTAssertFalse(result.canRetryAutomatically)
    }

    func testApplyRequiresExactConfirmationBeforeReadingEditor() {
        let bridge = MockSemanticMutationBridge(states: [])
        let coordinator = ShortcutSemanticMutationCoordinator(bridge: bridge)

        XCTAssertThrowsError(try coordinator.mutate(
            plan: plan(operations: [operation(.deleteAction, index: 0)], initial: 2, final: 1),
            expectedEditorNameSHA256: hash("fixture"),
            apply: true,
            confirmation: "EDIT SHORTCUT"
        )) { error in
            XCTAssertEqual(error as? ShortcutsError, .editConfirmationRequired)
        }
        XCTAssertEqual(bridge.inspectCalls, 0)
    }

    func testInitialEditorIdentityAndGraphMustMatchPlan() {
        let expectedName = hash("fixture")
        let wrongName = state(nameHash: hash("other"), actions: [.text(hash("old"))])
        let wrongCount = state(nameHash: expectedName, actions: [.text(hash("old")), .comment(nil)])

        for initial in [wrongName, wrongCount] {
            let bridge = MockSemanticMutationBridge(states: [initial])
            XCTAssertThrowsError(try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
                plan: plan(operations: [operation(.replaceText, index: 0, value: "next")], initial: 1, final: 1),
                expectedEditorNameSHA256: expectedName,
                apply: true,
                confirmation: "EDIT SHORTCUT COPY"
            )) { error in
                XCTAssertEqual(error as? ShortcutsError, .editEditorConflict)
            }
            XCTAssertEqual(bridge.recoveryCalls, 0)
        }
    }

    func testInitialEditorPreservesActionablePermissionAndTargetErrors() {
        for expected in [ShortcutsError.permissionDenied, .targetNotRunning] {
            let bridge = MockSemanticMutationBridge(states: [], inspectError: expected)
            XCTAssertThrowsError(try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
                plan: plan(operations: [operation(.replaceText, index: 0, value: "next")], initial: 1, final: 1),
                expectedEditorNameSHA256: hash("fixture"),
                apply: true,
                confirmation: "EDIT SHORTCUT COPY"
            )) { error in
                XCTAssertEqual(error as? ShortcutsError, expected)
            }
            XCTAssertEqual(bridge.recoveryCalls, 0)
        }
    }

    func testRecoveryCandidateMustPreserveOriginalGraphAndUseDistinctIdentity() {
        let name = hash("fixture")
        let original = state(nameHash: name, actions: [.text(hash("old"))])
        let invalidCopies = [
            state(nameHash: name, actions: [.text(hash("old"))], recovery: true),
            state(nameHash: hash("copy"), actions: [.comment(nil)], recovery: true),
            state(nameHash: hash("copy"), actions: [.text(hash("old"))], recovery: false),
        ]

        for copy in invalidCopies {
            let bridge = MockSemanticMutationBridge(states: [original], recoveryState: copy)
            XCTAssertThrowsError(try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
                plan: plan(operations: [operation(.replaceText, index: 0, value: "next")], initial: 1, final: 1),
                expectedEditorNameSHA256: name,
                apply: true,
                confirmation: "EDIT SHORTCUT COPY"
            )) { error in
                XCTAssertEqual(error as? ShortcutsError, .editRecoveryFailed)
            }
            XCTAssertEqual(bridge.performCalls, 0)
        }
    }

    func testEveryOperationIsAppliedToCopyAndVerifiedSequentially() throws {
        let name = hash("fixture")
        let originalActions: [ShortcutSemanticActionState] = [.text(hash("a")), .comment(nil)]
        let original = state(nameHash: name, actions: originalActions)
        let copyName = hash("fixture copy")
        let copy = state(nameHash: copyName, actions: originalActions, recovery: true)
        let afterInsert = state(nameHash: copyName, actions: [.text(hash("a")), .text(hash("b")), .comment(nil)], recovery: true)
        let afterReplace = state(nameHash: copyName, actions: [.text(hash("c")), .text(hash("b")), .comment(nil)], recovery: true)
        let afterMove = state(nameHash: copyName, actions: [.comment(nil), .text(hash("c")), .text(hash("b"))], recovery: true)
        let afterDelete = state(nameHash: copyName, actions: [.comment(nil), .text(hash("b"))], recovery: true)
        let bridge = MockSemanticMutationBridge(states: [original, afterInsert, afterReplace, afterMove, afterDelete], recoveryState: copy)
        let operations = [
            operation(.insertText, index: 1, value: "b"),
            operation(.replaceText, index: 0, value: "c"),
            operation(.moveAction, from: 2, to: 0),
            operation(.deleteAction, index: 1),
        ]

        let result = try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
            plan: plan(operations: operations, initial: 2, final: 2),
            expectedEditorNameSHA256: name,
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )

        XCTAssertEqual(result.status, .readbackConfirmed)
        XCTAssertEqual(result.verifiedOperationCount, 4)
        XCTAssertTrue(result.originalPreserved)
        XCTAssertEqual(result.finalActionCount, 2)
        XCTAssertFalse(result.canRetryAutomatically)
        XCTAssertEqual(bridge.recoveryCalls, 1)
        XCTAssertEqual(bridge.performCalls, 4)
        XCTAssertEqual(bridge.performedTextValues, ["b", "c"])
    }

    func testMutationFailureOrReadbackMismatchReturnsUnknownAndStops() throws {
        let name = hash("fixture")
        let original = state(nameHash: name, actions: [.text(hash("a"))])
        let copy = state(nameHash: hash("copy"), actions: [.text(hash("a"))], recovery: true)
        let expectedOperation = operation(.replaceText, index: 0, value: "b")

        let throwing = MockSemanticMutationBridge(states: [original], recoveryState: copy, throwOnPerform: 1)
        let throwingResult = try ShortcutSemanticMutationCoordinator(bridge: throwing).mutate(
            plan: plan(operations: [expectedOperation], initial: 1, final: 1),
            expectedEditorNameSHA256: name,
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )
        XCTAssertEqual(throwingResult.status, .outcomeUnknown)
        XCTAssertEqual(throwingResult.verifiedOperationCount, 0)
        XCTAssertTrue(throwingResult.originalPreserved)
        XCTAssertNil(throwingResult.finalActionCount)
        XCTAssertFalse(throwingResult.canRetryAutomatically)

        let mismatched = state(nameHash: copy.editorNameSHA256, actions: [.text(hash("wrong"))], recovery: true)
        let mismatchBridge = MockSemanticMutationBridge(states: [original, mismatched], recoveryState: copy)
        let mismatchResult = try ShortcutSemanticMutationCoordinator(bridge: mismatchBridge).mutate(
            plan: plan(operations: [expectedOperation], initial: 1, final: 1),
            expectedEditorNameSHA256: name,
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )
        XCTAssertEqual(mismatchResult.status, .outcomeUnknown)
        XCTAssertEqual(mismatchResult.verifiedOperationCount, 0)
        XCTAssertNil(mismatchResult.finalActionCount)
        XCTAssertFalse(mismatchResult.canRetryAutomatically)
    }

    func testAmbiguousOrUnboundedEditorFailsBeforeRecovery() {
        let name = hash("fixture")
        for invalid in [
            state(nameHash: name, actions: [.text(hash("a"))], candidateCount: 2),
            state(nameHash: name, actions: [.text(hash("a"))], bounded: false),
        ] {
            let bridge = MockSemanticMutationBridge(states: [invalid])
            XCTAssertThrowsError(try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
                plan: plan(operations: [operation(.replaceText, index: 0, value: "b")], initial: 1, final: 1),
                expectedEditorNameSHA256: name,
                apply: true,
                confirmation: "EDIT SHORTCUT COPY"
            )) { error in
                XCTAssertEqual(error as? ShortcutsError, .editEditorConflict)
            }
            XCTAssertEqual(bridge.recoveryCalls, 0)
        }
    }

    func testEntirePlanIsPreflightedBeforeCreatingRecoveryCopy() {
        let name = hash("fixture")
        let original = state(nameHash: name, actions: [.text(hash("a")), .comment(nil)])
        let bridge = MockSemanticMutationBridge(states: [original])
        let invalidLaterOperation = ShortcutEditExecutionOperation(
            summary: ShortcutEditOperationSummary(
                sequence: 1,
                operation: .replaceText,
                index: 9,
                fromIndex: nil,
                toIndex: nil,
                valueBytes: Data("invalid".utf8).count,
                valueSHA256: hash("invalid")
            ),
            textValue: "invalid"
        )

        XCTAssertThrowsError(try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
            plan: plan(
                operations: [operation(.replaceText, index: 0, value: "valid"), invalidLaterOperation],
                initial: 2,
                final: 2
            ),
            expectedEditorNameSHA256: name,
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )) { error in
            XCTAssertEqual(error as? ShortcutsError, .editEditorConflict)
        }
        XCTAssertEqual(bridge.recoveryCalls, 0)
        XCTAssertEqual(bridge.performCalls, 0)
    }

    func testPrivateExecutionValueMustMatchRedactedSummaryBeforeEditorRead() {
        let bridge = MockSemanticMutationBridge(states: [])
        let valid = operation(.replaceText, index: 0, value: "reviewed value")
        let mismatched = ShortcutEditExecutionOperation(summary: valid.summary, textValue: "different value")

        XCTAssertThrowsError(try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
            plan: plan(operations: [mismatched], initial: 1, final: 1),
            expectedEditorNameSHA256: hash("fixture"),
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )) { error in
            XCTAssertEqual(error as? ShortcutsError, .editSourceConflict)
        }
        XCTAssertEqual(bridge.inspectCalls, 0)
        XCTAssertEqual(bridge.recoveryCalls, 0)
        XCTAssertEqual(bridge.performCalls, 0)
    }

    func testResultNeverContainsEditorOrActionValues() throws {
        let privateName = "private customer shortcut"
        let privateValue = "private action content"
        let original = state(nameHash: hash(privateName), actions: [.text(hash("old"))])
        let copy = state(nameHash: hash("copy"), actions: [.text(hash("old"))], recovery: true)
        let after = state(nameHash: copy.editorNameSHA256, actions: [.text(hash(privateValue))], recovery: true)
        let bridge = MockSemanticMutationBridge(states: [original, after], recoveryState: copy)

        let result = try ShortcutSemanticMutationCoordinator(bridge: bridge).mutate(
            plan: plan(operations: [operation(.replaceText, index: 0, value: privateValue)], initial: 1, final: 1),
            expectedEditorNameSHA256: hash(privateName),
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )
        let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertFalse(encoded.contains(privateName))
        XCTAssertFalse(encoded.contains(privateValue))
    }

    private func plan(operations: [ShortcutEditExecutionOperation], initial: Int, final: Int) -> ShortcutEditExecutionPlan {
        let sequenced = operations.enumerated().map { sequence, operation in
            ShortcutEditExecutionOperation(
                summary: ShortcutEditOperationSummary(
                    sequence: sequence,
                    operation: operation.summary.operation,
                    index: operation.summary.index,
                    fromIndex: operation.summary.fromIndex,
                    toIndex: operation.summary.toIndex,
                    valueBytes: operation.summary.valueBytes,
                    valueSHA256: operation.summary.valueSHA256
                ),
                textValue: operation.textValue
            )
        }
        let result = ShortcutEditPlanResult(operation: "edit_plan", experimental: true, inputSHA256: hash("input"), inputBytes: 10, planSHA256: hash("plan"), operationCount: sequenced.count, initialActionCount: initial, finalActionCount: final, operations: sequenced.map(\.summary), canApplySemanticEdit: false, nextAction: "review")
        return ShortcutEditExecutionPlan(publicResult: result, operations: sequenced)
    }

    private func operation(_ kind: ShortcutEditOperationKind, index: Int? = nil, from: Int? = nil, to: Int? = nil, value: String? = nil) -> ShortcutEditExecutionOperation {
        let data = value.map { Data($0.utf8) }
        let summary = ShortcutEditOperationSummary(sequence: 0, operation: kind, index: index, fromIndex: from, toIndex: to, valueBytes: data?.count, valueSHA256: data.map(CherriSourceValidator.hash))
        return ShortcutEditExecutionOperation(summary: summary, textValue: value)
    }

    private func state(nameHash: String, actions: [ShortcutSemanticActionState], candidateCount: Int = 1, bounded: Bool = true, recovery: Bool = false) -> ShortcutSemanticEditorState {
        ShortcutSemanticEditorState(editorNameSHA256: nameHash, actions: actions, candidateCount: candidateCount, bounded: bounded, isRecoveryCandidate: recovery)
    }

    private func hash(_ value: String) -> String { CherriSourceValidator.hash(Data(value.utf8)) }
}

private final class MockSemanticMutationBridge: ShortcutSemanticMutationBridging, @unchecked Sendable {
    private var states: [ShortcutSemanticEditorState]
    private let recoveryState: ShortcutSemanticEditorState?
    private let throwOnPerform: Int?
    private let inspectError: ShortcutsError?
    var inspectCalls = 0
    var recoveryCalls = 0
    var performCalls = 0
    var performedTextValues: [String] = []

    init(
        states: [ShortcutSemanticEditorState],
        recoveryState: ShortcutSemanticEditorState? = nil,
        throwOnPerform: Int? = nil,
        inspectError: ShortcutsError? = nil
    ) {
        self.states = states
        self.recoveryState = recoveryState
        self.throwOnPerform = throwOnPerform
        self.inspectError = inspectError
    }

    func inspectEditor() throws -> ShortcutSemanticEditorState {
        inspectCalls += 1
        if let inspectError { throw inspectError }
        guard !states.isEmpty else { throw TestBridgeError.failed }
        return states.removeFirst()
    }

    func createRecoveryCandidate() throws -> ShortcutSemanticEditorState {
        recoveryCalls += 1
        guard let recoveryState else { throw TestBridgeError.failed }
        return recoveryState
    }

    func perform(_ operation: ShortcutEditExecutionOperation) throws {
        performCalls += 1
        if let value = operation.textValue { performedTextValues.append(value) }
        if throwOnPerform == performCalls { throw TestBridgeError.failed }
    }
}

private enum TestBridgeError: Error { case failed }

private extension ShortcutSemanticActionState {
    static func text(_ hash: String?) -> Self { .init(kind: .text, valueSHA256: hash) }
    static func comment(_ hash: String?) -> Self { .init(kind: .comment, valueSHA256: hash) }
}
