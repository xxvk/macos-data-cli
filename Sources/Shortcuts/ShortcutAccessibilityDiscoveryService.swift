import Foundation

public enum ShortcutAccessibilityDiscoveryStatus: String, Codable, Equatable, Sendable {
    case permissionRequired = "permission_required"
    case targetNotRunning = "target_not_running"
    case noCandidate = "no_candidate"
    case candidateFound = "candidate_found"
    case ambiguous
    case unbounded
}

struct ShortcutAccessibilityNode: Equatable, Sendable {
    let role: String
    let identifier: String?
    let label: String?
    let children: [ShortcutAccessibilityNode]
    let truncated: Bool

    init(role: String, identifier: String? = nil, label: String? = nil, children: [ShortcutAccessibilityNode] = [], truncated: Bool = false) {
        self.role = role
        self.identifier = identifier
        self.label = label
        self.children = children
        self.truncated = truncated
    }
}

protocol ShortcutAccessibilityReading: Sendable {
    func isTrusted() -> Bool
    func applicationSnapshot() -> [ShortcutAccessibilityNode]?
}

public struct ShortcutAccessibilityInspectionResult: Codable, Equatable, Sendable {
    let operation: String
    let experimental: Bool
    let status: ShortcutAccessibilityDiscoveryStatus
    let accessibilityTrusted: Bool
    let targetRunning: Bool
    let bounded: Bool
    let nodeCount: Int
    let windowCount: Int
    let editorCandidateCount: Int
    let semanticIdentifierCount: Int
    let ambiguous: Bool
    let canApplySemanticEdit: Bool
    let nextAction: String
}

public struct ShortcutAccessibilityDiscoveryService: @unchecked Sendable {
    static let maximumNodeCount = 2_000
    static let maximumDepth = 32

    private let reader: any ShortcutAccessibilityReading

    public init() {
        self.reader = SystemShortcutAccessibilityReader()
    }

    init(reader: any ShortcutAccessibilityReading) {
        self.reader = reader
    }

    public func inspect() -> ShortcutAccessibilityInspectionResult {
        guard reader.isTrusted() else {
            return result(status: .permissionRequired, trusted: false, running: false, bounded: true, nodes: 0, windows: 0, candidates: 0, identifiers: 0)
        }
        guard let roots = reader.applicationSnapshot() else {
            return result(status: .targetNotRunning, trusted: true, running: false, bounded: true, nodes: 0, windows: 0, candidates: 0, identifiers: 0)
        }

        var totalNodes = 0
        var windowCount = 0
        var candidateCount = 0
        var semanticIdentifierCount = 0
        var bounded = true
        var pending = roots.map { ($0, 0, false) }
        var windowTokens: [ShortcutAccessibilityNode] = []

        while let (node, depth, inheritedWindow) = pending.popLast() {
            totalNodes += 1
            if totalNodes > Self.maximumNodeCount || depth > Self.maximumDepth || node.truncated {
                bounded = false
                break
            }
            let isWindow = node.role == "AXWindow"
            if isWindow {
                windowCount += 1
                windowTokens.append(node)
            }
            let belongsToWindow = inheritedWindow || isWindow
            if belongsToWindow, node.identifier?.isEmpty == false { semanticIdentifierCount += 1 }
            pending.append(contentsOf: node.children.map { ($0, depth + 1, belongsToWindow) })
        }

        if bounded {
            candidateCount = windowTokens.filter(Self.isEditorCandidate).count
        }
        let status: ShortcutAccessibilityDiscoveryStatus
        if !bounded { status = .unbounded }
        else if candidateCount == 0 { status = .noCandidate }
        else if candidateCount == 1 { status = .candidateFound }
        else { status = .ambiguous }
        return result(status: status, trusted: true, running: true, bounded: bounded, nodes: min(totalNodes, Self.maximumNodeCount), windows: windowCount, candidates: candidateCount, identifiers: semanticIdentifierCount)
    }

    private struct Signals {
        var toolbar = false
        var scrollArea = false
        var group = false
        var semanticMarker = false
    }

    private static func isEditorCandidate(_ window: ShortcutAccessibilityNode) -> Bool {
        var signals = Signals()
        var pending = [window]
        while let node = pending.popLast() {
            signals.toolbar = signals.toolbar || node.role == "AXToolbar"
            signals.scrollArea = signals.scrollArea || node.role == "AXScrollArea"
            signals.group = signals.group || node.role == "AXGroup"
            signals.semanticMarker = signals.semanticMarker || isEditorMarker(node.identifier) || isEditorMarker(node.label)
            pending.append(contentsOf: node.children)
        }
        return signals.toolbar && signals.scrollArea && signals.group && signals.semanticMarker
    }

    private static func isEditorMarker(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return ["shortcuteditor", "workfloweditor", "actioneditor", "editorshortcutname"].contains { normalized.contains($0) }
    }

    private func result(status: ShortcutAccessibilityDiscoveryStatus, trusted: Bool, running: Bool, bounded: Bool, nodes: Int, windows: Int, candidates: Int, identifiers: Int) -> ShortcutAccessibilityInspectionResult {
        let nextAction: String
        switch status {
        case .permissionRequired:
            nextAction = "Grant Accessibility to the stable mpia app only if you intend to run the future disposable UI fixture gate. This command does not prompt."
        case .targetNotRunning:
            nextAction = "Open Shortcuts.app manually with a disposable test shortcut before repeating read-only discovery."
        case .candidateFound:
            nextAction = "A structural candidate was found, but this is not action-graph proof or apply authorization. Run only the separately authorized disposable fixture gate next."
        case .ambiguous:
            nextAction = "Close unrelated Shortcuts windows and use one disposable editor window. Do not choose a candidate automatically."
        case .unbounded:
            nextAction = "The Accessibility tree exceeded safety bounds. Stop; do not retry automatically or relax limits."
        case .noCandidate:
            nextAction = "Open one disposable Shortcut editor window. Generic role structure alone is intentionally insufficient."
        }
        return ShortcutAccessibilityInspectionResult(
            operation: "ui_inspect",
            experimental: true,
            status: status,
            accessibilityTrusted: trusted,
            targetRunning: running,
            bounded: bounded,
            nodeCount: nodes,
            windowCount: windows,
            editorCandidateCount: candidates,
            semanticIdentifierCount: identifiers,
            ambiguous: status == .ambiguous,
            canApplySemanticEdit: false,
            nextAction: nextAction
        )
    }
}
