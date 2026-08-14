import Core
import Foundation

protocol ShortcutAccessibilityMutationSession: Sendable {
    func inspectEditor() throws -> ShortcutSemanticEditorState
    func duplicateEditor() throws
    func insertText(at index: Int, value: String) throws
    func replaceText(at index: Int, value: String) throws
    func deleteAction(at index: Int) throws
    func moveAction(from: Int, to: Int) throws
}

final class GuardedShortcutAccessibilityMutationBridge: ShortcutSemanticMutationBridging, @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let plan: ShortcutEditExecutionPlan
    private let session: any ShortcutAccessibilityMutationSession
    private let lock = NSLock()
    private var nextOperationIndex = 0
    private var recoveryAttempted = false
    private var poisoned = false

    init(plan: ShortcutEditExecutionPlan, session: any ShortcutAccessibilityMutationSession) {
        self.plan = plan
        self.session = session
    }

    var description: String {
        "GuardedShortcutAccessibilityMutationBridge(planSHA256: \(plan.publicResult.planSHA256), privateValues: redacted)"
    }

    var debugDescription: String { description }

    func inspectEditor() throws -> ShortcutSemanticEditorState {
        try locked {
            guard !poisoned else { throw ShortcutsError.editSourceConflict }
            return try session.inspectEditor()
        }
    }

    func createRecoveryCandidate() throws -> ShortcutSemanticEditorState {
        try locked {
            guard !poisoned, !recoveryAttempted else { throw ShortcutsError.editRecoveryFailed }
            recoveryAttempted = true
            do {
                try session.duplicateEditor()
                return try session.inspectEditor()
            } catch {
                poisoned = true
                throw error
            }
        }
    }

    func perform(_ operation: ShortcutEditExecutionOperation) throws {
        try locked {
            guard !poisoned,
                  recoveryAttempted,
                  plan.operations.indices.contains(nextOperationIndex),
                  plan.operations[nextOperationIndex] == operation else {
                throw ShortcutsError.editSourceConflict
            }
            do {
                try dispatch(operation)
                nextOperationIndex += 1
            } catch {
                poisoned = true
                throw error
            }
        }
    }

    private func dispatch(_ operation: ShortcutEditExecutionOperation) throws {
        let summary = operation.summary
        switch summary.operation {
        case .insertText:
            guard let index = summary.index, let value = operation.textValue else { throw ShortcutsError.editSourceConflict }
            try session.insertText(at: index, value: value)
        case .replaceText:
            guard let index = summary.index, let value = operation.textValue else { throw ShortcutsError.editSourceConflict }
            try session.replaceText(at: index, value: value)
        case .deleteAction:
            guard let index = summary.index, operation.textValue == nil else { throw ShortcutsError.editSourceConflict }
            try session.deleteAction(at: index)
        case .moveAction:
            guard let from = summary.fromIndex, let to = summary.toIndex, operation.textValue == nil else { throw ShortcutsError.editSourceConflict }
            try session.moveAction(from: from, to: to)
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
