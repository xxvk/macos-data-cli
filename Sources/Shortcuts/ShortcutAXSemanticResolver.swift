import Core
import Foundation

struct ShortcutAXSemanticNode: Equatable, Sendable {
    let role: String
    let identifier: String?
    let label: String?
    let value: String?
    let valueSettable: Bool
    let positionY: Double?
    let children: [ShortcutAXSemanticNode]
    let truncated: Bool

    init(
        role: String,
        identifier: String? = nil,
        label: String? = nil,
        value: String? = nil,
        valueSettable: Bool = false,
        positionY: Double? = nil,
        children: [ShortcutAXSemanticNode] = [],
        truncated: Bool = false
    ) {
        self.role = role
        self.identifier = identifier
        self.label = label
        self.value = value
        self.valueSettable = valueSettable
        self.positionY = positionY
        self.children = children
        self.truncated = truncated
    }
}

struct ShortcutAXSemanticResolution: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let state: ShortcutSemanticEditorState
    let editorNamePath: [Int]
    let actionValuePaths: [[Int]]
    let actionClosePaths: [[Int]]

    init(
        state: ShortcutSemanticEditorState,
        editorNamePath: [Int],
        actionValuePaths: [[Int]],
        actionClosePaths: [[Int]] = []
    ) {
        self.state = state
        self.editorNamePath = editorNamePath
        self.actionValuePaths = actionValuePaths
        self.actionClosePaths = actionClosePaths
    }

    var description: String {
        "ShortcutAXSemanticResolution(actionCount: \(state.actions.count), privateAXValues: redacted)"
    }

    var debugDescription: String { description }
}

struct ShortcutAXSemanticResolver: Sendable {
    private static let maximumNodeCount = 2_000
    private static let maximumDepth = 32

    func resolve(roots: [ShortcutAXSemanticNode], recovery: Bool) throws -> ShortcutAXSemanticResolution {
        guard !roots.isEmpty, isBounded(roots) else { throw ShortcutsError.editEditorConflict }
        var candidates: [ShortcutAXSemanticResolution] = []

        for (rootIndex, root) in roots.enumerated() where root.role == "AXWindow" {
            let prefix = [rootIndex]
            let nameFields = descendants(of: root, path: prefix).filter { item in
                item.node.role == "AXTextField"
                    && item.node.identifier == "editor.shortcutname"
                    && item.node.valueSettable
                    && item.node.value?.isEmpty == false
            }
            guard nameFields.count == 1, let name = nameFields[0].node.value else { continue }

            let canvases = descendants(of: root, path: prefix).compactMap { item -> ParsedCanvas? in
                guard item.node.role == "AXScrollArea" else { return nil }
                return parseCanvas(item.node, path: item.path)
            }
            guard canvases.count == 1, let canvas = canvases.first else { continue }
            candidates.append(ShortcutAXSemanticResolution(
                state: ShortcutSemanticEditorState(
                    editorNameSHA256: CherriSourceValidator.hash(Data(name.utf8)),
                    actions: canvas.actions,
                    candidateCount: 1,
                    bounded: true,
                    isRecoveryCandidate: recovery
                ),
                editorNamePath: nameFields[0].path,
                actionValuePaths: canvas.valuePaths,
                actionClosePaths: canvas.closePaths
            ))
        }

        guard candidates.count == 1 else { throw ShortcutsError.editEditorConflict }
        return candidates[0]
    }

    private struct ParsedCanvas {
        let actions: [ShortcutSemanticActionState]
        let valuePaths: [[Int]]
        let closePaths: [[Int]]
    }

    private struct ParsedAction {
        let state: ShortcutSemanticActionState
        let valuePath: [Int]
        let closePath: [Int]
        let positionY: Double?
    }

    private func parseCanvas(_ canvas: ShortcutAXSemanticNode, path: [Int]) -> ParsedCanvas? {
        let titleIndexes = canvas.children.indices.filter { index in
            actionKind(canvas.children[index]) != nil
        }
        guard !titleIndexes.isEmpty else { return nil }

        let directStaticTexts = canvas.children.filter { $0.role == "AXStaticText" }
        guard directStaticTexts.allSatisfy({ actionKind($0) != nil }) else { return nil }

        var parsedActions: [ParsedAction] = []
        for (offset, titleIndex) in titleIndexes.enumerated() {
            guard let kind = actionKind(canvas.children[titleIndex]) else { return nil }
            let nextTitle = offset + 1 < titleIndexes.count ? titleIndexes[offset + 1] : canvas.children.endIndex
            var fields: [(node: ShortcutAXSemanticNode, path: [Int])] = []
            var closeButtons: [(node: ShortcutAXSemanticNode, path: [Int])] = []
            var actionPositions = [canvas.children[titleIndex].positionY].compactMap { $0 }
            if titleIndex + 1 < nextTitle {
                for index in (titleIndex + 1)..<nextTitle {
                    let actionNodes = descendants(of: canvas.children[index], path: path + [index])
                    actionPositions.append(contentsOf: actionNodes.compactMap { $0.node.positionY })
                    fields.append(contentsOf: actionNodes.filter { item in
                        item.node.role == "AXTextArea"
                            && item.node.valueSettable
                            && item.node.value != nil
                    })
                    closeButtons.append(contentsOf: actionNodes.filter { item in
                        item.node.role == "AXButton" && item.node.label == "Close"
                    })
                }
            }
            guard fields.count == 1,
                  closeButtons.count == 1,
                  let value = fields[0].node.value else { return nil }
            parsedActions.append(.init(
                state: .init(kind: kind, valueSHA256: CherriSourceValidator.hash(Data(value.utf8))),
                valuePath: fields[0].path,
                closePath: closeButtons[0].path,
                positionY: actionPositions.max()
            ))
        }

        let positionedCount = parsedActions.filter { $0.positionY != nil }.count
        let ordered: [ParsedAction]
        if positionedCount == 0 {
            ordered = parsedActions
        } else {
            guard positionedCount == parsedActions.count else { return nil }
            let positions = parsedActions.compactMap(\.positionY)
            guard Set(positions).count == positions.count else { return nil }
            ordered = parsedActions.sorted { $0.positionY! < $1.positionY! }
        }
        return ParsedCanvas(
            actions: ordered.map(\.state),
            valuePaths: ordered.map(\.valuePath),
            closePaths: ordered.map(\.closePath)
        )
    }

    private func actionKind(_ node: ShortcutAXSemanticNode) -> ShortcutSemanticActionKind? {
        guard node.role == "AXStaticText" else { return nil }
        switch node.value ?? node.label {
        case "Text": return .text
        case "Comment": return .comment
        default: return nil
        }
    }

    private func descendants(of root: ShortcutAXSemanticNode, path: [Int]) -> [(node: ShortcutAXSemanticNode, path: [Int])] {
        var result = [(root, path)]
        for (index, child) in root.children.enumerated() {
            result.append(contentsOf: descendants(of: child, path: path + [index]))
        }
        return result
    }

    private func isBounded(_ roots: [ShortcutAXSemanticNode]) -> Bool {
        var count = 0
        var pending = roots.map { ($0, 0) }
        while let (node, depth) = pending.popLast() {
            count += 1
            guard count <= Self.maximumNodeCount,
                  depth <= Self.maximumDepth,
                  !node.truncated else { return false }
            pending.append(contentsOf: node.children.map { ($0, depth + 1) })
        }
        return true
    }
}
