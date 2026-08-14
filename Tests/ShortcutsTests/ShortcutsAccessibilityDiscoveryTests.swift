import Foundation
import XCTest
@testable import ShortcutsAdapter

final class ShortcutsAccessibilityDiscoveryTests: XCTestCase {
    func testUntrustedStatusDoesNotReadApplicationTreeOrPrompt() {
        let reader = MockAccessibilityReader(trusted: false, nodes: [])

        let result = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()

        XCTAssertFalse(result.accessibilityTrusted)
        XCTAssertFalse(result.targetRunning)
        XCTAssertEqual(result.nodeCount, 0)
        XCTAssertEqual(reader.snapshotCalls, 0)
        XCTAssertFalse(result.canApplySemanticEdit)
        XCTAssertEqual(result.status, .permissionRequired)
    }

    func testMissingTargetReturnsStableReadOnlyStatus() {
        let reader = MockAccessibilityReader(trusted: true, nodes: nil)

        let result = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()

        XCTAssertTrue(result.accessibilityTrusted)
        XCTAssertFalse(result.targetRunning)
        XCTAssertEqual(reader.snapshotCalls, 1)
        XCTAssertEqual(result.status, .targetNotRunning)
        XCTAssertFalse(result.canApplySemanticEdit)
    }

    func testSemanticWindowIsDiscoveredWithoutReturningLabelsOrIdentifiers() throws {
        let privateTitle = "Private Customer Shortcut"
        let privateIdentifier = "workflow-editor-private-id"
        let nodes = [node("AXWindow", label: privateTitle, children: [
            node("AXToolbar"),
            node("AXGroup", identifier: privateIdentifier, label: "Shortcut Editor", children: [
                node("AXScrollArea", children: [node("AXGroup")]),
            ]),
        ])]
        let reader = MockAccessibilityReader(trusted: true, nodes: nodes)

        let result = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()
        let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8)!

        XCTAssertEqual(result.status, .candidateFound)
        XCTAssertEqual(result.windowCount, 1)
        XCTAssertEqual(result.editorCandidateCount, 1)
        XCTAssertGreaterThan(result.semanticIdentifierCount, 0)
        XCTAssertTrue(result.bounded)
        XCTAssertFalse(result.ambiguous)
        XCTAssertFalse(result.canApplySemanticEdit)
        XCTAssertFalse(encoded.contains(privateTitle))
        XCTAssertFalse(encoded.contains(privateIdentifier))
        XCTAssertFalse(encoded.contains("Shortcut Editor"))
    }

    func testAmbiguousCandidatesFailClosed() {
        let editor = node("AXWindow", children: [
            node("AXToolbar"),
            node("AXGroup", identifier: "workflow-editor", children: [node("AXScrollArea")]),
        ])
        let reader = MockAccessibilityReader(trusted: true, nodes: [editor, editor])

        let result = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()

        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.editorCandidateCount, 2)
        XCTAssertTrue(result.ambiguous)
        XCTAssertFalse(result.canApplySemanticEdit)
    }

    func testRoleOnlyGenericWindowIsNotClaimedAsEditor() {
        let reader = MockAccessibilityReader(trusted: true, nodes: [
            node("AXWindow", children: [node("AXToolbar"), node("AXScrollArea"), node("AXGroup")]),
        ])

        let result = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()

        XCTAssertEqual(result.status, .noCandidate)
        XCTAssertEqual(result.editorCandidateCount, 0)
        XCTAssertFalse(result.canApplySemanticEdit)
    }

    func testMacOS27ShortcutNameEditorIdentifierIsRecognized() {
        let reader = MockAccessibilityReader(trusted: true, nodes: [
            node("AXWindow", children: [
                node("AXToolbar", children: [node("AXTextField", identifier: "editor.shortcutname")]),
                node("AXGroup", children: [node("AXScrollArea")]),
            ]),
        ])

        let result = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()

        XCTAssertEqual(result.status, .candidateFound)
        XCTAssertEqual(result.editorCandidateCount, 1)
        XCTAssertFalse(result.canApplySemanticEdit)
    }

    func testNodeAndDepthBoundsFailClosed() {
        let wide = node("AXWindow", children: (0...ShortcutAccessibilityDiscoveryService.maximumNodeCount).map { _ in node("AXGroup") })
        var deep = node("AXGroup", identifier: "workflow-editor")
        for _ in 0...ShortcutAccessibilityDiscoveryService.maximumDepth {
            deep = node("AXGroup", children: [deep])
        }

        for root in [wide, node("AXWindow", children: [deep])] {
            let result = ShortcutAccessibilityDiscoveryService(reader: MockAccessibilityReader(trusted: true, nodes: [root])).inspect()
            XCTAssertEqual(result.status, .unbounded)
            XCTAssertFalse(result.bounded)
            XCTAssertFalse(result.canApplySemanticEdit)
        }
    }

    func testInspectionReaderHasNoActionAPIAndIsCalledAtMostOnce() {
        let reader = MockAccessibilityReader(trusted: true, nodes: [])

        _ = ShortcutAccessibilityDiscoveryService(reader: reader).inspect()

        XCTAssertEqual(reader.snapshotCalls, 1)
    }

    private func node(_ role: String, identifier: String? = nil, label: String? = nil, children: [ShortcutAccessibilityNode] = []) -> ShortcutAccessibilityNode {
        ShortcutAccessibilityNode(role: role, identifier: identifier, label: label, children: children)
    }
}

private final class MockAccessibilityReader: ShortcutAccessibilityReading, @unchecked Sendable {
    let trusted: Bool
    let nodes: [ShortcutAccessibilityNode]?
    var snapshotCalls = 0

    init(trusted: Bool, nodes: [ShortcutAccessibilityNode]?) {
        self.trusted = trusted
        self.nodes = nodes
    }

    func isTrusted() -> Bool { trusted }

    func applicationSnapshot() -> [ShortcutAccessibilityNode]? {
        snapshotCalls += 1
        return nodes
    }
}
