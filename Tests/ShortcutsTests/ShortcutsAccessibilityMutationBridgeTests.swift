import Core
import Foundation
import XCTest
@testable import ShortcutsAdapter

final class ShortcutsAccessibilityMutationBridgeTests: XCTestCase {
    func testBridgeDuplicatesOnceAndReturnsOnlySessionReadback() throws {
        let original = state("original", recovery: false)
        let copy = state("copy", recovery: true)
        let session = MockMutationSession(states: [original, copy])
        let bridge = GuardedShortcutAccessibilityMutationBridge(plan: plan([operation(.replaceText, index: 0, value: "next")]), session: session)

        XCTAssertEqual(try bridge.inspectEditor(), original)
        XCTAssertEqual(try bridge.createRecoveryCandidate(), copy)
        XCTAssertEqual(session.duplicateCalls, 1)
        XCTAssertThrowsError(try bridge.createRecoveryCandidate()) { error in
            XCTAssertEqual(error as? ShortcutsError, .editRecoveryFailed)
        }
        XCTAssertEqual(session.duplicateCalls, 1)
    }

    func testBridgeDispatchesOnlyBoundOperationsInExactOrder() throws {
        let privateInsert = "private insert"
        let privateReplacement = "private replacement"
        let operations = [
            operation(.insertText, index: 1, value: privateInsert),
            operation(.replaceText, index: 0, value: privateReplacement),
            operation(.moveAction, from: 2, to: 0),
            operation(.deleteAction, index: 1),
        ]
        let session = MockMutationSession(states: [state("copy", recovery: true)])
        let prepared = plan(operations)
        let bridge = GuardedShortcutAccessibilityMutationBridge(plan: prepared, session: session)
        _ = try bridge.createRecoveryCandidate()

        for operation in prepared.operations { try bridge.perform(operation) }

        XCTAssertEqual(session.calls, [
            .insert(index: 1, value: privateInsert),
            .replace(index: 0, value: privateReplacement),
            .move(from: 2, to: 0),
            .delete(index: 1),
        ])
    }

    func testOutOfOrderAlteredOrExtraOperationFailsBeforeAXSessionCall() throws {
        let first = operation(.replaceText, index: 0, value: "first")
        let second = operation(.insertText, index: 1, value: "second")

        for attempted in [second, operation(.replaceText, index: 0, value: "altered")] {
            let session = MockMutationSession(states: [state("copy", recovery: true)])
            let bridge = GuardedShortcutAccessibilityMutationBridge(plan: plan([first, second]), session: session)
            _ = try bridge.createRecoveryCandidate()
            XCTAssertThrowsError(try bridge.perform(attempted)) { error in
                XCTAssertEqual(error as? ShortcutsError, .editSourceConflict)
            }
            XCTAssertTrue(session.calls.isEmpty)
        }

        let session = MockMutationSession(states: [state("copy", recovery: true)])
        let bridge = GuardedShortcutAccessibilityMutationBridge(plan: plan([first]), session: session)
        _ = try bridge.createRecoveryCandidate()
        try bridge.perform(first)
        XCTAssertThrowsError(try bridge.perform(first)) { error in
            XCTAssertEqual(error as? ShortcutsError, .editSourceConflict)
        }
        XCTAssertEqual(session.calls.count, 1)
    }

    func testFailedSessionOperationPoisonsBridgeAndProhibitsRetry() {
        let expected = operation(.replaceText, index: 0, value: "private")
        let session = MockMutationSession(states: [state("copy", recovery: true)], failFirstMutation: true)
        let bridge = GuardedShortcutAccessibilityMutationBridge(plan: plan([expected]), session: session)
        XCTAssertNoThrow(try bridge.createRecoveryCandidate())

        XCTAssertThrowsError(try bridge.perform(expected))
        XCTAssertThrowsError(try bridge.perform(expected)) { error in
            XCTAssertEqual(error as? ShortcutsError, .editSourceConflict)
        }
        XCTAssertEqual(session.calls.count, 1)
    }

    func testBridgeDebugOutputNeverContainsPrivateValues() {
        let privateValue = "private customer action value"
        let bridge = GuardedShortcutAccessibilityMutationBridge(
            plan: plan([operation(.replaceText, index: 0, value: privateValue)]),
            session: MockMutationSession(states: [])
        )

        XCTAssertFalse(String(describing: bridge).contains(privateValue))
        XCTAssertFalse(String(reflecting: bridge).contains(privateValue))
    }

    private func plan(_ operations: [ShortcutEditExecutionOperation]) -> ShortcutEditExecutionPlan {
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
        let result = ShortcutEditPlanResult(
            operation: "edit_plan",
            experimental: true,
            inputSHA256: hash("input"),
            inputBytes: 10,
            planSHA256: hash("plan"),
            operationCount: sequenced.count,
            initialActionCount: 2,
            finalActionCount: 2,
            operations: sequenced.map(\.summary),
            canApplySemanticEdit: false,
            nextAction: "review"
        )
        return ShortcutEditExecutionPlan(publicResult: result, operations: sequenced)
    }

    private func operation(_ kind: ShortcutEditOperationKind, index: Int? = nil, from: Int? = nil, to: Int? = nil, value: String? = nil) -> ShortcutEditExecutionOperation {
        let data = value.map { Data($0.utf8) }
        return ShortcutEditExecutionOperation(
            summary: ShortcutEditOperationSummary(
                sequence: 0,
                operation: kind,
                index: index,
                fromIndex: from,
                toIndex: to,
                valueBytes: data?.count,
                valueSHA256: data.map(CherriSourceValidator.hash)
            ),
            textValue: value
        )
    }

    private func state(_ name: String, recovery: Bool) -> ShortcutSemanticEditorState {
        ShortcutSemanticEditorState(
            editorNameSHA256: hash(name),
            actions: [.init(kind: .text, valueSHA256: hash("value"))],
            candidateCount: 1,
            bounded: true,
            isRecoveryCandidate: recovery
        )
    }

    private func hash(_ value: String) -> String { CherriSourceValidator.hash(Data(value.utf8)) }
}

private final class MockMutationSession: ShortcutAccessibilityMutationSession, @unchecked Sendable {
    enum Call: Equatable {
        case insert(index: Int, value: String)
        case replace(index: Int, value: String)
        case delete(index: Int)
        case move(from: Int, to: Int)
    }

    private var states: [ShortcutSemanticEditorState]
    private var failFirstMutation: Bool
    var duplicateCalls = 0
    var calls: [Call] = []

    init(states: [ShortcutSemanticEditorState], failFirstMutation: Bool = false) {
        self.states = states
        self.failFirstMutation = failFirstMutation
    }

    func inspectEditor() throws -> ShortcutSemanticEditorState {
        guard !states.isEmpty else { throw SessionError.failed }
        return states.removeFirst()
    }

    func duplicateEditor() throws { duplicateCalls += 1 }
    func insertText(at index: Int, value: String) throws { try record(.insert(index: index, value: value)) }
    func replaceText(at index: Int, value: String) throws { try record(.replace(index: index, value: value)) }
    func deleteAction(at index: Int) throws { try record(.delete(index: index)) }
    func moveAction(from: Int, to: Int) throws { try record(.move(from: from, to: to)) }

    private func record(_ call: Call) throws {
        calls.append(call)
        if failFirstMutation {
            failFirstMutation = false
            throw SessionError.failed
        }
    }
}

private enum SessionError: Error { case failed }
