import Core
import Foundation
import XCTest
@testable import ShortcutsAdapter

final class SystemShortcutAccessibilityMutationSessionTests: XCTestCase {
    func testCopyFirstReplaceUsesOnlyResolvedTextPath() throws {
        let original = resolution(name: "original", text: "before", recovery: false, path: [0, 1, 2])
        let copy = resolution(name: "copy", text: "before", recovery: true, path: [1, 3, 4])
        let changed = resolution(name: "copy", text: "after", recovery: true, path: [1, 3, 4])
        let driver = MockSystemMutationDriver(resolutions: [original, copy, changed])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1)

        XCTAssertEqual(try session.inspectEditor(), original.state)
        try session.duplicateEditor()
        XCTAssertEqual(try session.inspectEditor(), copy.state)
        try session.replaceText(at: 0, value: "after")
        XCTAssertEqual(try session.inspectEditor(), changed.state)

        XCTAssertEqual(driver.duplicateCalls, 1)
        XCTAssertEqual(driver.setCalls, [.init(path: [1, 3, 4], value: "after")])
    }

    func testCopyFirstInsertDuplicatesKnownTextAtEndThenSetsOnlyAppendedValue() throws {
        let original = resolution(name: "original", actions: [.text("before"), .comment("note")], recovery: false, paths: [[0, 1], [0, 2]])
        let copy = resolution(name: "copy", actions: [.text("before"), .comment("note")], recovery: true, paths: [[1, 1], [1, 2]])
        let duplicated = resolution(name: "copy", actions: [.text("before"), .comment("note"), .text("before")], recovery: true, paths: [[2, 1], [2, 2], [2, 3]])
        let changed = resolution(name: "copy", actions: [.text("before"), .comment("note"), .text("inserted")], recovery: true, paths: [[3, 1], [3, 2], [3, 3]])
        let driver = MockSystemMutationDriver(resolutions: [original, copy, duplicated, changed])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1, pollInterval: 0)

        _ = try session.inspectEditor()
        try session.duplicateEditor()
        _ = try session.inspectEditor()
        try session.insertText(at: 2, value: "inserted")
        XCTAssertEqual(try session.inspectEditor(), changed.state)

        XCTAssertEqual(driver.duplicateActionCalls, [[1, 1]])
        XCTAssertEqual(driver.setCalls, [.init(path: [2, 3], value: "inserted")])
    }

    func testInsertRejectsNonAppendIndexOrGraphWithoutTextBeforeDriverMutation() throws {
        let original = resolution(name: "original", actions: [.text("before"), .comment("note")], recovery: false, paths: [[0], [1]])
        let copy = resolution(name: "copy", actions: [.text("before"), .comment("note")], recovery: true, paths: [[2], [3]])
        let driver = MockSystemMutationDriver(resolutions: [original, copy])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1)
        _ = try session.inspectEditor()
        try session.duplicateEditor()
        _ = try session.inspectEditor()

        XCTAssertThrowsError(try session.insertText(at: 1, value: "x")) {
            XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported)
        }
        XCTAssertTrue(driver.duplicateActionCalls.isEmpty)

        let commentOriginal = resolution(name: "comment-original", actions: [.comment("note")], recovery: false, paths: [[0]])
        let commentCopy = resolution(name: "comment-copy", actions: [.comment("note")], recovery: true, paths: [[1]])
        let commentDriver = MockSystemMutationDriver(resolutions: [commentOriginal, commentCopy])
        let commentSession = SystemShortcutAccessibilityMutationSession(driver: commentDriver, deadline: 0.1)
        _ = try commentSession.inspectEditor()
        try commentSession.duplicateEditor()
        _ = try commentSession.inspectEditor()
        XCTAssertThrowsError(try commentSession.insertText(at: 1, value: "x")) {
            XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported)
        }
        XCTAssertTrue(commentDriver.duplicateActionCalls.isEmpty)
    }

    func testCopyFirstDeletePressesOnlyResolvedCloseButton() throws {
        let original = resolution(name: "original", actions: [.text("before"), .comment("note")], recovery: false, paths: [[0, 1], [0, 2]], closePaths: [[0, 3], [0, 4]])
        let copy = resolution(name: "copy", actions: [.text("before"), .comment("note")], recovery: true, paths: [[1, 1], [1, 2]], closePaths: [[1, 3], [1, 4]])
        let stale = resolution(name: "copy", actions: [.text("before"), .comment("note")], recovery: true, paths: [[1, 1], [1, 2]], closePaths: [[1, 3], [1, 4]])
        let deleted = resolution(name: "copy", actions: [.text("before")], recovery: true, paths: [[2, 1]], closePaths: [[2, 3]])
        let driver = MockSystemMutationDriver(resolutions: [original, copy, stale, deleted, deleted])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1, pollInterval: 0)

        _ = try session.inspectEditor()
        try session.duplicateEditor()
        _ = try session.inspectEditor()
        try session.deleteAction(at: 1)
        XCTAssertEqual(try session.inspectEditor(), deleted.state)

        XCTAssertEqual(driver.deleteActionCalls, [[1, 4]])
    }

    func testCopyFirstMoveVerifiesEachAdjacentSemanticStep() throws {
        let original = resolution(
            name: "original",
            actions: [.text("first"), .comment("second"), .text("third")],
            recovery: false,
            paths: [[0, 1], [0, 2], [0, 3]]
        )
        let copy = resolution(
            name: "copy",
            actions: [.text("first"), .comment("second"), .text("third")],
            recovery: true,
            paths: [[1, 1], [1, 2], [1, 3]]
        )
        let firstStep = resolution(
            name: "copy",
            actions: [.comment("second"), .text("first"), .text("third")],
            recovery: true,
            paths: [[2, 1], [2, 2], [2, 3]]
        )
        let final = resolution(
            name: "copy",
            actions: [.comment("second"), .text("third"), .text("first")],
            recovery: true,
            paths: [[3, 1], [3, 2], [3, 3]]
        )
        let driver = MockSystemMutationDriver(resolutions: [original, copy, firstStep, final, final])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1, pollInterval: 0)

        _ = try session.inspectEditor()
        try session.duplicateEditor()
        _ = try session.inspectEditor()
        try session.moveAction(from: 0, to: 2)
        XCTAssertEqual(try session.inspectEditor(), final.state)
        XCTAssertEqual(driver.moveActionCalls, [
            .init(path: [1, 1], direction: .down),
            .init(path: [2, 2], direction: .down),
        ])
    }

    func testMoveRejectsNoOpAndIndistinguishableAdjacentActionsBeforeDriverMutation() throws {
        let original = resolution(
            name: "original",
            actions: [.text("same"), .text("same")],
            recovery: false,
            paths: [[0, 1], [0, 2]]
        )
        let copy = resolution(
            name: "copy",
            actions: [.text("same"), .text("same")],
            recovery: true,
            paths: [[1, 1], [1, 2]]
        )
        let driver = MockSystemMutationDriver(resolutions: [original, copy])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1, pollInterval: 0)

        _ = try session.inspectEditor()
        try session.duplicateEditor()
        _ = try session.inspectEditor()
        XCTAssertThrowsError(try session.moveAction(from: 0, to: 0)) {
            XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported)
        }
        XCTAssertThrowsError(try session.moveAction(from: 0, to: 1)) {
            XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported)
        }
        XCTAssertTrue(driver.moveActionCalls.isEmpty)
    }

    func testDuplicateRequiresAnInspectedOriginalAndCanRunOnlyOnce() {
        let driver = MockSystemMutationDriver(resolutions: [])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1)

        XCTAssertThrowsError(try session.duplicateEditor()) { error in
            XCTAssertEqual(error as? ShortcutsError, .editRecoveryFailed)
        }
        XCTAssertEqual(driver.duplicateCalls, 0)

        let readyDriver = MockSystemMutationDriver(resolutions: [resolution(name: "original", text: "before", recovery: false, path: [0])])
        let ready = SystemShortcutAccessibilityMutationSession(driver: readyDriver, deadline: 0.1)
        XCTAssertNoThrow(try ready.inspectEditor())
        XCTAssertNoThrow(try ready.duplicateEditor())
        XCTAssertThrowsError(try ready.duplicateEditor()) { error in
            XCTAssertEqual(error as? ShortcutsError, .editRecoveryFailed)
        }
        XCTAssertEqual(readyDriver.duplicateCalls, 1)
    }

    func testConcreteSessionRejectsInsertDeleteMoveAndNonTextReplacement() throws {
        let comment = ShortcutAXSemanticResolution(
            state: ShortcutSemanticEditorState(
                editorNameSHA256: hash("copy"),
                actions: [.init(kind: .comment, valueSHA256: hash("comment"))],
                candidateCount: 1,
                bounded: true,
                isRecoveryCandidate: true
            ),
            editorNamePath: [0],
            actionValuePaths: [[1]]
        )
        let driver = MockSystemMutationDriver(resolutions: [resolution(name: "original", text: "before", recovery: false, path: [0]), comment])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.1)
        _ = try session.inspectEditor()
        try session.duplicateEditor()
        _ = try session.inspectEditor()

        XCTAssertThrowsError(try session.insertText(at: 0, value: "x")) { XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported) }
        XCTAssertThrowsError(try session.deleteAction(at: 0)) { XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported) }
        XCTAssertThrowsError(try session.moveAction(from: 0, to: 0)) { XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported) }
        XCTAssertThrowsError(try session.replaceText(at: 0, value: "x")) { XCTAssertEqual($0 as? ShortcutsError, .editEditorConflict) }
        XCTAssertTrue(driver.setCalls.isEmpty)
    }

    func testRecoveryReadWaitsForDistinctNameAndTimesOutFailClosed() throws {
        let original = resolution(name: "same", text: "before", recovery: false, path: [0])
        let stale = resolution(name: "same", text: "before", recovery: true, path: [0])
        let driver = MockSystemMutationDriver(resolutions: [original, stale, stale, stale])
        let session = SystemShortcutAccessibilityMutationSession(driver: driver, deadline: 0.01, pollInterval: 0)

        _ = try session.inspectEditor()
        try session.duplicateEditor()
        XCTAssertThrowsError(try session.inspectEditor()) { error in
            XCTAssertEqual(error as? ShortcutsError, .editRecoveryFailed)
        }
        XCTAssertTrue(driver.setCalls.isEmpty)
    }

    func testConfirmedExistingRecoveryCopyCanResumeWithoutDuplicatingAgain() throws {
        let copy = resolution(name: "copy", text: "before", recovery: true, path: [4, 2])
        let changed = resolution(name: "copy", text: "after", recovery: true, path: [4, 2])
        let driver = MockSystemMutationDriver(resolutions: [copy, changed])
        let session = SystemShortcutAccessibilityMutationSession(
            driver: driver,
            deadline: 0.1,
            resumingRecoveryFrom: hash("original")
        )

        XCTAssertEqual(try session.inspectEditor(), copy.state)
        try session.replaceText(at: 0, value: "after")
        XCTAssertEqual(try session.inspectEditor(), changed.state)
        XCTAssertEqual(driver.duplicateCalls, 0)
        XCTAssertEqual(driver.setCalls, [.init(path: [4, 2], value: "after")])
    }

    func testConfirmedExistingRecoveryCopyCanMoveWithoutDuplicatingAgain() throws {
        let copy = resolution(
            name: "copy",
            actions: [.text("before"), .comment("note")],
            recovery: true,
            paths: [[4, 1], [4, 2]]
        )
        let moved = resolution(
            name: "copy",
            actions: [.comment("note"), .text("before")],
            recovery: true,
            paths: [[5, 1], [5, 2]]
        )
        let driver = MockSystemMutationDriver(resolutions: [copy, moved, moved])
        let session = SystemShortcutAccessibilityMutationSession(
            driver: driver,
            deadline: 0.1,
            pollInterval: 0,
            resumingRecoveryFrom: hash("original")
        )

        XCTAssertEqual(try session.inspectEditor(), copy.state)
        try session.moveAction(from: 1, to: 0)
        XCTAssertEqual(try session.inspectEditor(), moved.state)
        XCTAssertEqual(driver.duplicateCalls, 0)
        XCTAssertEqual(driver.moveActionCalls, [.init(path: [4, 2], direction: .up)])
    }

    func testConfirmedExistingDeletedCopyCanBeReadWithoutAnyMutation() throws {
        let deletedCopy = resolution(name: "copy", text: "before", recovery: true, path: [4, 2])
        let driver = MockSystemMutationDriver(resolutions: [deletedCopy])
        let session = SystemShortcutAccessibilityMutationSession(
            driver: driver,
            deadline: 0.1,
            resumingRecoveryFrom: hash("original")
        )

        XCTAssertEqual(try session.inspectEditor(), deletedCopy.state)
        XCTAssertEqual(driver.duplicateCalls, 0)
        XCTAssertTrue(driver.duplicateActionCalls.isEmpty)
        XCTAssertTrue(driver.deleteActionCalls.isEmpty)
        XCTAssertTrue(driver.setCalls.isEmpty)
    }

    private func resolution(name: String, text: String, recovery: Bool, path: [Int]) -> ShortcutAXSemanticResolution {
        ShortcutAXSemanticResolution(
            state: ShortcutSemanticEditorState(
                editorNameSHA256: hash(name),
                actions: [.init(kind: .text, valueSHA256: hash(text))],
                candidateCount: 1,
                bounded: true,
                isRecoveryCandidate: recovery
            ),
            editorNamePath: [9],
            actionValuePaths: [path]
        )
    }

    private func resolution(
        name: String,
        actions: [FixtureAction],
        recovery: Bool,
        paths: [[Int]],
        closePaths: [[Int]] = []
    ) -> ShortcutAXSemanticResolution {
        ShortcutAXSemanticResolution(
            state: ShortcutSemanticEditorState(
                editorNameSHA256: hash(name),
                actions: actions.map { action in
                    switch action {
                    case let .text(value): .init(kind: .text, valueSHA256: hash(value))
                    case let .comment(value): .init(kind: .comment, valueSHA256: hash(value))
                    }
                },
                candidateCount: 1,
                bounded: true,
                isRecoveryCandidate: recovery
            ),
            editorNamePath: [9],
            actionValuePaths: paths,
            actionClosePaths: closePaths
        )
    }

    private func hash(_ value: String) -> String { CherriSourceValidator.hash(Data(value.utf8)) }
}

private enum FixtureAction {
    case text(String)
    case comment(String)
}

private final class MockSystemMutationDriver: ShortcutAXSystemMutationDriving, @unchecked Sendable {
    struct SetCall: Equatable { let path: [Int]; let value: String }
    struct MoveCall: Equatable { let path: [Int]; let direction: ShortcutAXMoveDirection }

    private var resolutions: [ShortcutAXSemanticResolution]
    var duplicateCalls = 0
    var duplicateActionCalls: [[Int]] = []
    var deleteActionCalls: [[Int]] = []
    var moveActionCalls: [MoveCall] = []
    var setCalls: [SetCall] = []

    init(resolutions: [ShortcutAXSemanticResolution]) { self.resolutions = resolutions }

    func resolveEditor(recovery: Bool) throws -> ShortcutAXSemanticResolution {
        guard !resolutions.isEmpty else { throw ShortcutsError.editEditorConflict }
        let value = resolutions.removeFirst()
        return ShortcutAXSemanticResolution(
            state: .init(
                editorNameSHA256: value.state.editorNameSHA256,
                actions: value.state.actions,
                candidateCount: value.state.candidateCount,
                bounded: value.state.bounded,
                isRecoveryCandidate: recovery
            ),
            editorNamePath: value.editorNamePath,
            actionValuePaths: value.actionValuePaths,
            actionClosePaths: value.actionClosePaths
        )
    }

    func duplicateShortcut() throws { duplicateCalls += 1 }
    func duplicateAction(at path: [Int]) throws { duplicateActionCalls.append(path) }
    func deleteAction(at path: [Int]) throws { deleteActionCalls.append(path) }
    func moveAction(at path: [Int], direction: ShortcutAXMoveDirection) throws {
        moveActionCalls.append(.init(path: path, direction: direction))
    }
    func setTextValue(_ value: String, at path: [Int]) throws { setCalls.append(.init(path: path, value: value)) }
}
