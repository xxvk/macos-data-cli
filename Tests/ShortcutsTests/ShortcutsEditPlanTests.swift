import Foundation
import XCTest
import Core
@testable import ShortcutsAdapter

final class ShortcutsEditPlanTests: XCTestCase {
    func testSequentialOperationsProduceRedactedReadOnlyPlan() throws {
        let secret = "private replacement value"
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
            action("is.workflow.actions.output"),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [
                ["operation": "insert_text", "index": 1, "value": "inserted"],
                ["operation": "replace_text", "index": 0, "value": secret],
                ["operation": "move_action", "fromIndex": 2, "toIndex": 0],
                ["operation": "delete_action", "index": 1],
            ],
        ])

        let result = try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)
        let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertEqual(result.operation, "edit_plan")
        XCTAssertEqual(result.inputSHA256, inputHash)
        XCTAssertEqual(result.operationCount, 4)
        XCTAssertEqual(result.initialActionCount, 2)
        XCTAssertEqual(result.finalActionCount, 2)
        XCTAssertEqual(result.operations.map(\.operation), [.insertText, .replaceText, .moveAction, .deleteAction])
        XCTAssertFalse(result.canApplySemanticEdit)
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.contains("is.workflow.actions"))
        XCTAssertTrue(result.operations[1].valueBytes! > 0)
        XCTAssertEqual(result.operations[1].valueSHA256?.count, 64)
    }

    func testPreparationBindsRedactedPlanToPrivateInMemoryValues() throws {
        let privateInsert = "private insert text"
        let privateReplacement = "private replacement text"
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [
                ["operation": "insert_text", "index": 1, "value": privateInsert],
                ["operation": "replace_text", "index": 0, "value": privateReplacement],
                ["operation": "move_action", "fromIndex": 2, "toIndex": 0],
            ],
        ])

        let prepared = try ShortcutEditPlanService().prepare(inputURL: fixture.url, patchData: patch)
        let publicJSON = String(data: try JSONEncoder().encode(prepared.publicResult), encoding: .utf8)!
        let reflected = String(reflecting: prepared)

        XCTAssertEqual(prepared.publicResult.planSHA256, CherriSourceValidator.hash(patch))
        XCTAssertEqual(prepared.operations.map(\.summary), prepared.publicResult.operations)
        XCTAssertEqual(prepared.operations[0].textValue, privateInsert)
        XCTAssertEqual(prepared.operations[1].textValue, privateReplacement)
        XCTAssertNil(prepared.operations[2].textValue)
        XCTAssertFalse(publicJSON.contains(privateInsert))
        XCTAssertFalse(publicJSON.contains(privateReplacement))
        XCTAssertFalse(reflected.contains(privateInsert))
        XCTAssertFalse(reflected.contains(privateReplacement))
    }

    func testReplaceOnlyPlanAdvertisesCopyApplyCapability() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [["operation": "replace_text", "index": 0, "value": "next"]],
        ])

        let result = try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)

        XCTAssertTrue(result.canApplySemanticEdit)
        XCTAssertTrue(result.nextAction.contains("edit copy"))
    }

    func testAppendOnlyTextInsertAdvertisesCopyApplyCapability() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let appendPatch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [["operation": "insert_text", "index": 2, "value": "appended"]],
        ])
        let middlePatch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [["operation": "insert_text", "index": 1, "value": "middle"]],
        ])

        XCTAssertTrue(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: appendPatch).canApplySemanticEdit)
        XCTAssertFalse(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: middlePatch).canApplySemanticEdit)
    }

    func testBoundedDeleteIsApplyCapableAndCannotEmptyGraph() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [["operation": "delete_action", "index": 1]],
        ])

        let result = try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)

        XCTAssertTrue(result.canApplySemanticEdit)
        XCTAssertEqual(result.finalActionCount, 1)
    }

    func testBoundedMoveIsApplyCapableAfterLiveGate() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [["operation": "move_action", "fromIndex": 1, "toIndex": 0]],
        ])

        let result = try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)

        XCTAssertTrue(result.canApplySemanticEdit)
        XCTAssertEqual(result.initialActionCount, 2)
        XCTAssertEqual(result.finalActionCount, 2)
        XCTAssertEqual(result.operations.first?.fromIndex, 1)
        XCTAssertEqual(result.operations.first?.toIndex, 0)
    }

    func testMoveRejectsSameIndexAsInvalidPlan() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [["operation": "move_action", "fromIndex": 1, "toIndex": 1]],
        ])

        XCTAssertThrowsError(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)) {
            XCTAssertEqual($0 as? ShortcutsError, .editPlanInvalid)
        }
    }

    func testMixedTextAndDeletePlanIsPreviewOnly() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"]),
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "second"]),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inputHash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": inputHash,
            "operations": [
                ["operation": "replace_text", "index": 0, "value": "next"],
                ["operation": "delete_action", "index": 1],
            ],
        ])

        let result = try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)

        XCTAssertFalse(result.canApplySemanticEdit)
        XCTAssertEqual(result.finalActionCount, 1)
    }

    func testExpectedHashMismatchIsAStableConflict() throws {
        let fixture = try makeShortcut(actions: [action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"])])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let patch = try json([
            "expectedInputSHA256": String(repeating: "0", count: 64),
            "operations": [["operation": "replace_text", "index": 0, "value": "next"]],
        ])

        XCTAssertThrowsError(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)) { error in
            XCTAssertEqual(error as? ShortcutsError, .editSourceConflict)
        }
    }

    func testStrictJSONRejectsUnknownFieldsAndWrongShapes() throws {
        let fixture = try makeShortcut(actions: [action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"])])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let hash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let unknownTop = try json(["expectedInputSHA256": hash, "operations": [], "title": "leak"])
        let unknownOperation = try json([
            "expectedInputSHA256": hash,
            "operations": [["operation": "delete_action", "index": 0, "extra": true]],
        ])

        for patch in [unknownTop, unknownOperation, Data("[]".utf8)] {
            XCTAssertThrowsError(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)) { error in
                XCTAssertEqual(error as? ShortcutsError, .editPlanInvalid)
            }
        }
    }

    func testBoundsTypeAndEmptyGraphFailuresAreClosed() throws {
        let fixture = try makeShortcut(actions: [
            action("is.workflow.actions.comment", parameters: ["WFCommentActionText": "comment"]),
            action("is.workflow.actions.output"),
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let hash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patches: [[String: Any]] = [
            ["expectedInputSHA256": hash, "operations": [["operation": "replace_text", "index": 0, "value": "no"]]],
            ["expectedInputSHA256": hash, "operations": [["operation": "move_action", "fromIndex": 0, "toIndex": 2]]],
            ["expectedInputSHA256": hash, "operations": [["operation": "delete_action", "index": 0]]],
        ]

        for value in patches {
            XCTAssertThrowsError(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: try json(value))) { error in
                XCTAssertEqual(error as? ShortcutsError, .editPlanInvalid)
            }
        }
    }

    func testManualMigrationArtifactCannotProducePlan() throws {
        let fixture = try makeShortcut(actions: [action("com.example.unsupported")])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let hash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let patch = try json([
            "expectedInputSHA256": hash,
            "operations": [["operation": "insert_text", "index": 0, "value": "safe"]],
        ])

        XCTAssertThrowsError(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)) { error in
            XCTAssertEqual(error as? ShortcutsError, .editCapabilityUnsupported)
        }
    }

    func testOperationAndValueLimitsAreEnforced() throws {
        let fixture = try makeShortcut(actions: [action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"])])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let hash = CherriSourceValidator.hash(try Data(contentsOf: fixture.url))
        let tooMany = (0...ShortcutEditPlanService.maximumOperationCount).map { _ in
            ["operation": "replace_text", "index": 0, "value": "x"] as [String: Any]
        }
        let oversizedValue = String(repeating: "x", count: ShortcutEditPlanService.maximumValueBytes + 1)

        for value in [
            ["expectedInputSHA256": hash, "operations": tooMany] as [String: Any],
            ["expectedInputSHA256": hash, "operations": [["operation": "replace_text", "index": 0, "value": oversizedValue]]],
        ] {
            XCTAssertThrowsError(try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: try json(value))) { error in
                XCTAssertEqual(error as? ShortcutsError, .editPlanInvalid)
            }
        }
    }

    func testPlanningDoesNotMutateInput() throws {
        let fixture = try makeShortcut(actions: [action("is.workflow.actions.text", parameters: ["WFTextActionText": "first"])])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let before = try Data(contentsOf: fixture.url)
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
        let hash = CherriSourceValidator.hash(before)
        let patch = try json([
            "expectedInputSHA256": hash,
            "operations": [["operation": "replace_text", "index": 0, "value": "next"]],
        ])

        _ = try ShortcutEditPlanService().plan(inputURL: fixture.url, patchData: patch)

        XCTAssertEqual(try Data(contentsOf: fixture.url), before)
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
        XCTAssertEqual(beforeAttributes[.modificationDate] as? Date, afterAttributes[.modificationDate] as? Date)
    }

    func testEditErrorsHaveStablePrivacySafeContracts() {
        XCTAssertEqual(ShortcutsError.editPlanInvalid.machineCode, "SHORTCUTS_EDIT_PLAN_INVALID")
        XCTAssertEqual(ShortcutsError.editSourceConflict.machineCode, "SHORTCUTS_EDIT_SOURCE_CONFLICT")
        XCTAssertEqual(ShortcutsError.editCapabilityUnsupported.machineCode, "SHORTCUTS_EDIT_CAPABILITY_UNSUPPORTED")
        XCTAssertFalse(ShortcutsError.editPlanInvalid.description.localizedCaseInsensitiveContains("value"))
    }

    private func action(_ identifier: String, parameters: [String: Any] = [:]) -> [String: Any] {
        ["WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": parameters]
    }

    private func makeShortcut(actions: [[String: Any]]) throws -> (directory: URL, url: URL) {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["WFWorkflowActions": actions, "WFWorkflowClientVersion": "fixture"],
            format: .binary,
            options: 0
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent("fixture.shortcut")
        try data.write(to: url)
        return (directory, url)
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
