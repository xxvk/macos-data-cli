import Foundation
import XCTest
import Core
@testable import ShortcutsAdapter

final class ShortcutSemanticEditServiceTests: XCTestCase {
    func testDryRunReturnsRedactedPreviewWithoutConstructingApplyExecutor() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let service = ShortcutSemanticEditService(applyExecutor: { _, _, _ in
            calls.increment()
            throw TestError.unexpectedApply
        })

        let result = try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "replace_text"),
            expectedEditorNameSHA256: hash("editor"),
            apply: false,
            confirmation: nil
        )

        XCTAssertEqual(result.status, .preview)
        XCTAssertEqual(result.operation, "semantic_edit_copy")
        XCTAssertEqual(result.operationCount, 1)
        XCTAssertEqual(calls.value, 0)
        XCTAssertFalse(try JSONEncoder().encode(result).contains(Data("replacement-secret".utf8)))
    }

    func testApplyRequiresExactConfirmationBeforeConstructingExecutor() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let service = ShortcutSemanticEditService(applyExecutor: { _, _, _ in
            calls.increment()
            throw TestError.unexpectedApply
        })

        XCTAssertThrowsError(try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "replace_text"),
            expectedEditorNameSHA256: hash("editor"),
            apply: true,
            confirmation: "EDIT SHORTCUT"
        )) { XCTAssertEqual($0 as? ShortcutsError, .editConfirmationRequired) }
        XCTAssertEqual(calls.value, 0)
    }

    func testAppendOnlyInsertDryRunIsAcceptedWithoutConstructingExecutor() throws {
        let fixture = try makeFixture(twoActions: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let service = ShortcutSemanticEditService(applyExecutor: { _, _, _ in
            calls.increment()
            throw TestError.unexpectedApply
        })
        let patch = try JSONSerialization.data(withJSONObject: [
            "expectedInputSHA256": fixture.hash,
            "operations": [["operation": "insert_text", "index": 2, "value": "appended-secret"]],
        ], options: [.sortedKeys])

        let result = try service.execute(
            inputURL: fixture.url,
            patchData: patch,
            expectedEditorNameSHA256: hash("editor"),
            apply: false,
            confirmation: nil
        )

        XCTAssertEqual(result.status, .preview)
        XCTAssertEqual(result.finalActionCount, 2)
        XCTAssertEqual(calls.value, 0)
        XCTAssertFalse(try JSONEncoder().encode(result).contains(Data("appended-secret".utf8)))
    }

    func testBoundedDeleteSupportsDryRunAndGuardedApply() throws {
        let fixture = try makeFixture(twoActions: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let service = ShortcutSemanticEditService(applyExecutor: { plan, _, _ in
            calls.increment()
            return ShortcutSemanticMutationResult(
                operation: "semantic_edit_copy",
                status: .readbackConfirmed,
                inputSHA256: plan.publicResult.inputSHA256,
                planSHA256: plan.publicResult.planSHA256,
                operationCount: 1,
                verifiedOperationCount: 1,
                originalPreserved: true,
                finalActionCount: 1,
                canRetryAutomatically: false,
                nextAction: "review"
            )
        })

        let result = try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "delete_action"),
            expectedEditorNameSHA256: hash("editor"),
            apply: false,
            confirmation: nil
        )

        XCTAssertEqual(result.status, .preview)
        XCTAssertEqual(result.operationCount, 1)
        XCTAssertEqual(calls.value, 0)

        let applied = try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "delete_action"),
            expectedEditorNameSHA256: hash("editor"),
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )
        XCTAssertEqual(applied.status, .readbackConfirmed)
        XCTAssertEqual(calls.value, 1)
    }

    func testBoundedMoveSupportsDryRunAndGuardedApplyAfterLiveGate() throws {
        let fixture = try makeFixture(twoActions: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let service = ShortcutSemanticEditService(applyExecutor: { plan, _, _ in
            calls.increment()
            return ShortcutSemanticMutationResult(
                operation: "semantic_edit_copy",
                status: .readbackConfirmed,
                inputSHA256: plan.publicResult.inputSHA256,
                planSHA256: plan.publicResult.planSHA256,
                operationCount: 1,
                verifiedOperationCount: 1,
                originalPreserved: true,
                finalActionCount: 2,
                canRetryAutomatically: false,
                nextAction: "review"
            )
        })

        let preview = try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "move_action"),
            expectedEditorNameSHA256: hash("editor"),
            apply: false,
            confirmation: nil
        )

        XCTAssertEqual(preview.status, .preview)
        XCTAssertEqual(preview.operationCount, 1)
        XCTAssertEqual(preview.finalActionCount, 2)
        XCTAssertEqual(calls.value, 0)

        let applied = try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "move_action"),
            expectedEditorNameSHA256: hash("editor"),
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )
        XCTAssertEqual(applied.status, .readbackConfirmed)
        XCTAssertEqual(calls.value, 1)
    }

    func testUnsupportedMutationsAreRejectedBeforeAccessibilityExecutor() throws {
        for operation in ["insert_text"] {
            let fixture = try makeFixture(twoActions: true)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let calls = LockedCounter()
            let service = ShortcutSemanticEditService(applyExecutor: { _, _, _ in
                calls.increment()
                throw TestError.unexpectedApply
            })

            XCTAssertThrowsError(try service.execute(
                inputURL: fixture.url,
                patchData: patch(inputHash: fixture.hash, operation: operation),
                expectedEditorNameSHA256: hash("editor"),
                apply: false,
                confirmation: nil
            )) { XCTAssertEqual($0 as? ShortcutsError, .editCapabilityUnsupported) }
            XCTAssertEqual(calls.value, 0)
        }
    }

    func testInvalidEditorHashIsRejectedBeforeAccessibilityExecutor() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let service = ShortcutSemanticEditService(applyExecutor: { _, _, _ in
            calls.increment()
            throw TestError.unexpectedApply
        })

        XCTAssertThrowsError(try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "replace_text"),
            expectedEditorNameSHA256: "bad",
            apply: false,
            confirmation: nil
        )) { XCTAssertEqual($0 as? ShortcutsError, .editPlanInvalid) }
        XCTAssertEqual(calls.value, 0)
    }

    func testValidApplyDelegatesPrivatePlanOnlyAfterGuardsPass() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let calls = LockedCounter()
        let expectedNameHash = hash("editor")
        let service = ShortcutSemanticEditService(applyExecutor: { plan, nameHash, confirmation in
            calls.increment()
            XCTAssertEqual(nameHash, expectedNameHash)
            XCTAssertEqual(confirmation, "EDIT SHORTCUT COPY")
            XCTAssertEqual(plan.operations.first?.textValue, "replacement-secret")
            return ShortcutSemanticMutationResult(
                operation: "semantic_edit_copy",
                status: .readbackConfirmed,
                inputSHA256: plan.publicResult.inputSHA256,
                planSHA256: plan.publicResult.planSHA256,
                operationCount: 1,
                verifiedOperationCount: 1,
                originalPreserved: true,
                finalActionCount: 1,
                canRetryAutomatically: false,
                nextAction: "review"
            )
        })

        let result = try service.execute(
            inputURL: fixture.url,
            patchData: patch(inputHash: fixture.hash, operation: "replace_text"),
            expectedEditorNameSHA256: expectedNameHash,
            apply: true,
            confirmation: "EDIT SHORTCUT COPY"
        )

        XCTAssertEqual(result.status, .readbackConfirmed)
        XCTAssertEqual(calls.value, 1)
    }

    private func makeFixture(twoActions: Bool = false) throws -> (directory: URL, url: URL, hash: String) {
        var actions: [[String: Any]] = [[
            "WFWorkflowActionIdentifier": "is.workflow.actions.text",
            "WFWorkflowActionParameters": ["WFTextActionText": "original"],
        ]]
        if twoActions {
            actions.append([
                "WFWorkflowActionIdentifier": "is.workflow.actions.comment",
                "WFWorkflowActionParameters": ["WFCommentActionText": "comment"],
            ])
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["WFWorkflowActions": actions, "WFWorkflowClientVersion": "fixture"],
            format: .binary,
            options: 0
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent("fixture.shortcut")
        try data.write(to: url)
        return (directory, url, CherriSourceValidator.hash(data))
    }

    private func patch(inputHash: String, operation: String) throws -> Data {
        let payload: [String: Any]
        switch operation {
        case "insert_text":
            payload = ["expectedInputSHA256": inputHash, "operations": [["operation": operation, "index": 1, "value": "replacement-secret"]]]
        case "delete_action":
            payload = ["expectedInputSHA256": inputHash, "operations": [["operation": operation, "index": 1]]]
        case "move_action":
            payload = ["expectedInputSHA256": inputHash, "operations": [["operation": operation, "fromIndex": 1, "toIndex": 0]]]
        default:
            payload = ["expectedInputSHA256": inputHash, "operations": [["operation": operation, "index": 0, "value": "replacement-secret"]]]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func hash(_ value: String) -> String { CherriSourceValidator.hash(Data(value.utf8)) }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private enum TestError: Error { case unexpectedApply }
