import Core
import Foundation
import XCTest
@testable import ShortcutsAdapter

final class ShortcutAXSemanticResolverTests: XCTestCase {
    func testCalibratedMacOS27TextCommentEditorResolvesOneSemanticGraph() throws {
        let privateName = "private fixture name"
        let privateText = "private text value"
        let privateComment = "private comment value"
        let actionCanvas = node("AXScrollArea", children: [
            node("AXStaticText", value: "Text"),
            node("AXButton", label: "Close"),
            node("AXScrollArea", children: [node("AXTextArea", value: privateText, settable: true)]),
            node("AXImage", identifier: "text.justify.leading"),
            node("AXStaticText", value: "Comment"),
            node("AXButton", label: "Close"),
            node("AXScrollArea", children: [node("AXTextArea", value: privateComment, settable: true)]),
            node("AXScrollBar"),
        ])
        let actionLibraryDecoy = node("AXScrollArea", children: [
            node("AXTable", children: [node("AXRow", children: [node("AXStaticText", value: "Comment")])]),
        ])
        let roots = [node("AXWindow", children: [
            node("AXSplitGroup", children: [actionCanvas, actionLibraryDecoy]),
            node("AXToolbar", children: [
                node("AXTextField", identifier: "editor.shortcutname", value: privateName, settable: true),
            ]),
        ])]

        let result = try ShortcutAXSemanticResolver().resolve(roots: roots, recovery: false)
        let reflected = String(reflecting: result)

        XCTAssertEqual(result.state.editorNameSHA256, hash(privateName))
        XCTAssertEqual(result.state.actions, [
            .init(kind: .text, valueSHA256: hash(privateText)),
            .init(kind: .comment, valueSHA256: hash(privateComment)),
        ])
        XCTAssertEqual(result.actionValuePaths.count, 2)
        XCTAssertEqual(Set(result.actionValuePaths).count, 2)
        XCTAssertEqual(result.actionClosePaths.count, 2)
        XCTAssertEqual(Set(result.actionClosePaths).count, 2)
        XCTAssertFalse(result.state.isRecoveryCandidate)
        XCTAssertFalse(reflected.contains(privateName))
        XCTAssertFalse(reflected.contains(privateText))
        XCTAssertFalse(reflected.contains(privateComment))
    }

    func testAmbiguousEditorWindowsFailClosed() {
        let editor = node("AXWindow", children: [
            node("AXScrollArea", children: [
                node("AXStaticText", value: "Text"),
                node("AXButton", label: "Close"),
                node("AXScrollArea", children: [node("AXTextArea", value: "value", settable: true)]),
            ]),
            node("AXTextField", identifier: "editor.shortcutname", value: "name", settable: true),
        ])

        XCTAssertThrowsError(try ShortcutAXSemanticResolver().resolve(roots: [editor, editor], recovery: false)) { error in
            XCTAssertEqual(error as? ShortcutsError, .editEditorConflict)
        }
    }

    func testMissingValueFieldUnknownActionAndTruncationFailClosed() {
        let invalidCanvases = [
            node("AXScrollArea", children: [node("AXStaticText", value: "Text"), node("AXButton", label: "Close")]),
            node("AXScrollArea", children: [node("AXStaticText", value: "Text"), node("AXScrollArea", children: [node("AXTextArea", value: "x", settable: true)])]),
            node("AXScrollArea", children: [node("AXStaticText", value: "Run Shell Script"), node("AXScrollArea")]),
            node("AXScrollArea", children: [node("AXStaticText", value: "Text"), node("AXScrollArea", children: [node("AXTextArea", value: "x", settable: true)])], truncated: true),
        ]

        for canvas in invalidCanvases {
            let root = node("AXWindow", children: [
                canvas,
                node("AXTextField", identifier: "editor.shortcutname", value: "name", settable: true),
            ])
            XCTAssertThrowsError(try ShortcutAXSemanticResolver().resolve(roots: [root], recovery: false)) { error in
                XCTAssertEqual(error as? ShortcutsError, .editEditorConflict)
            }
        }
    }

    func testRecoveryFlagIsExplicitAndDoesNotDependOnNameText() throws {
        let root = node("AXWindow", children: [
            node("AXScrollArea", children: [
                node("AXStaticText", value: "Text"),
                node("AXButton", label: "Close"),
                node("AXScrollArea", children: [node("AXTextArea", value: "value", settable: true)]),
            ]),
            node("AXTextField", identifier: "editor.shortcutname", value: "ordinary name", settable: true),
        ])

        let result = try ShortcutAXSemanticResolver().resolve(roots: [root], recovery: true)

        XCTAssertTrue(result.state.isRecoveryCandidate)
    }

    func testActionGraphUsesVisualVerticalOrderWhenAXChildOrderIsStale() throws {
        let actionCanvas = node("AXScrollArea", children: [
            node("AXStaticText", value: "Text"),
            node("AXButton", label: "Close"),
            node("AXScrollArea", positionY: 300, children: [node("AXTextArea", value: "text", settable: true)]),
            node("AXStaticText", value: "Comment"),
            node("AXButton", label: "Close"),
            node("AXScrollArea", positionY: 100, children: [node("AXTextArea", value: "comment", settable: true)]),
        ])
        let root = node("AXWindow", children: [
            actionCanvas,
            node("AXTextField", identifier: "editor.shortcutname", value: "copy", settable: true),
        ])

        let result = try ShortcutAXSemanticResolver().resolve(roots: [root], recovery: true)

        XCTAssertEqual(result.state.actions, [
            .init(kind: .comment, valueSHA256: hash("comment")),
            .init(kind: .text, valueSHA256: hash("text")),
        ])
        XCTAssertEqual(result.actionValuePaths, [[0, 0, 5, 0], [0, 0, 2, 0]])
        XCTAssertEqual(result.actionClosePaths, [[0, 0, 4], [0, 0, 1]])
    }

    func testPartialOrDuplicateActionPositionsFailClosed() {
        let canvases = [
            node("AXScrollArea", children: [
                node("AXStaticText", value: "Text", positionY: 100),
                node("AXButton", label: "Close"),
                node("AXScrollArea", children: [node("AXTextArea", value: "text", settable: true)]),
                node("AXStaticText", value: "Comment"),
                node("AXButton", label: "Close"),
                node("AXScrollArea", children: [node("AXTextArea", value: "comment", settable: true)]),
            ]),
            node("AXScrollArea", children: [
                node("AXStaticText", value: "Text", positionY: 100),
                node("AXButton", label: "Close"),
                node("AXScrollArea", children: [node("AXTextArea", value: "text", settable: true)]),
                node("AXStaticText", value: "Comment", positionY: 100),
                node("AXButton", label: "Close"),
                node("AXScrollArea", children: [node("AXTextArea", value: "comment", settable: true)]),
            ]),
        ]

        for canvas in canvases {
            let root = node("AXWindow", children: [
                canvas,
                node("AXTextField", identifier: "editor.shortcutname", value: "copy", settable: true),
            ])
            XCTAssertThrowsError(try ShortcutAXSemanticResolver().resolve(roots: [root], recovery: true)) {
                XCTAssertEqual($0 as? ShortcutsError, .editEditorConflict)
            }
        }
    }

    private func node(
        _ role: String,
        identifier: String? = nil,
        label: String? = nil,
        value: String? = nil,
        settable: Bool = false,
        positionY: Double? = nil,
        children: [ShortcutAXSemanticNode] = [],
        truncated: Bool = false
    ) -> ShortcutAXSemanticNode {
        ShortcutAXSemanticNode(role: role, identifier: identifier, label: label, value: value, valueSettable: settable, positionY: positionY, children: children, truncated: truncated)
    }

    private func hash(_ value: String) -> String { CherriSourceValidator.hash(Data(value.utf8)) }
}
