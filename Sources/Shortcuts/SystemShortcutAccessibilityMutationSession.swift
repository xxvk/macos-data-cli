import AppKit
import ApplicationServices
import Core
import Foundation

enum ShortcutAXMoveDirection: Equatable, Sendable {
    case up
    case down
}

protocol ShortcutAXSystemMutationDriving: Sendable {
    func resolveEditor(recovery: Bool) throws -> ShortcutAXSemanticResolution
    func duplicateShortcut() throws
    func duplicateAction(at path: [Int]) throws
    func deleteAction(at path: [Int]) throws
    func moveAction(at path: [Int], direction: ShortcutAXMoveDirection) throws
    func setTextValue(_ value: String, at path: [Int]) throws
}

final class SystemShortcutAccessibilityMutationSession: ShortcutAccessibilityMutationSession, @unchecked Sendable {
    private let driver: any ShortcutAXSystemMutationDriving
    private let deadline: TimeInterval
    private let pollInterval: TimeInterval
    private var originalNameSHA256: String?
    private var lastResolution: ShortcutAXSemanticResolution?
    private var duplicated = false

    init(
        driver: any ShortcutAXSystemMutationDriving = SystemShortcutAXMutationDriver(),
        deadline: TimeInterval = 5,
        pollInterval: TimeInterval = 0.05,
        resumingRecoveryFrom originalNameSHA256: String? = nil
    ) {
        self.driver = driver
        self.deadline = deadline
        self.pollInterval = pollInterval
        self.originalNameSHA256 = originalNameSHA256
        self.duplicated = originalNameSHA256 != nil
    }

    func inspectEditor() throws -> ShortcutSemanticEditorState {
        if !duplicated {
            let resolution = try driver.resolveEditor(recovery: false)
            originalNameSHA256 = resolution.state.editorNameSHA256
            lastResolution = resolution
            return resolution.state
        }

        guard let originalNameSHA256 else { throw ShortcutsError.editRecoveryFailed }
        let end = Date().addingTimeInterval(deadline)
        repeat {
            if let resolution = try? driver.resolveEditor(recovery: true),
               resolution.state.editorNameSHA256 != originalNameSHA256 {
                lastResolution = resolution
                return resolution.state
            }
            if pollInterval > 0 { Thread.sleep(forTimeInterval: pollInterval) }
        } while Date() < end
        throw ShortcutsError.editRecoveryFailed
    }

    func duplicateEditor() throws {
        guard !duplicated, originalNameSHA256 != nil, lastResolution != nil else {
            throw ShortcutsError.editRecoveryFailed
        }
        try driver.duplicateShortcut()
        duplicated = true
        lastResolution = nil
    }

    func replaceText(at index: Int, value: String) throws {
        guard duplicated,
              let resolution = lastResolution,
              resolution.state.isRecoveryCandidate,
              resolution.state.actions.indices.contains(index),
              resolution.actionValuePaths.indices.contains(index),
              resolution.state.actions[index].kind == .text else {
            throw ShortcutsError.editEditorConflict
        }
        try driver.setTextValue(value, at: resolution.actionValuePaths[index])
        lastResolution = nil
    }

    func insertText(at index: Int, value: String) throws {
        guard duplicated,
              let resolution = lastResolution,
              resolution.state.isRecoveryCandidate,
              index == resolution.state.actions.count,
              let sourceIndex = resolution.state.actions.firstIndex(where: { $0.kind == .text }),
              resolution.actionValuePaths.indices.contains(sourceIndex),
              let sourceHash = resolution.state.actions[sourceIndex].valueSHA256 else {
            throw ShortcutsError.editCapabilityUnsupported
        }
        let originalActions = resolution.state.actions
        let copyNameSHA256 = resolution.state.editorNameSHA256
        try driver.duplicateAction(at: resolution.actionValuePaths[sourceIndex])
        lastResolution = nil

        let end = Date().addingTimeInterval(deadline)
        repeat {
            if let duplicatedResolution = try? driver.resolveEditor(recovery: true),
               duplicatedResolution.state.editorNameSHA256 == copyNameSHA256,
               duplicatedResolution.state.actions.count == originalActions.count + 1,
               Array(duplicatedResolution.state.actions.dropLast()) == originalActions,
               duplicatedResolution.state.actions.last == .init(kind: .text, valueSHA256: sourceHash),
               duplicatedResolution.actionValuePaths.indices.contains(index) {
                try driver.setTextValue(value, at: duplicatedResolution.actionValuePaths[index])
                return
            }
            if pollInterval > 0 { Thread.sleep(forTimeInterval: pollInterval) }
        } while Date() < end
        throw ShortcutsError.editEditorConflict
    }

    func deleteAction(at index: Int) throws {
        guard duplicated,
              let resolution = lastResolution,
              resolution.state.isRecoveryCandidate,
              resolution.state.actions.count > 1,
              resolution.state.actions.indices.contains(index),
              resolution.actionClosePaths.indices.contains(index) else {
            throw ShortcutsError.editCapabilityUnsupported
        }
        let copyNameSHA256 = resolution.state.editorNameSHA256
        var expectedActions = resolution.state.actions
        expectedActions.remove(at: index)
        try driver.deleteAction(at: resolution.actionClosePaths[index])
        lastResolution = nil

        let end = Date().addingTimeInterval(deadline)
        repeat {
            if let changed = try? driver.resolveEditor(recovery: true),
               changed.state.editorNameSHA256 == copyNameSHA256,
               changed.state.actions == expectedActions {
                lastResolution = changed
                return
            }
            if pollInterval > 0 { Thread.sleep(forTimeInterval: pollInterval) }
        } while Date() < end
        throw ShortcutsError.editEditorConflict
    }

    func moveAction(from: Int, to: Int) throws {
        guard duplicated,
              from != to,
              let initial = lastResolution,
              initial.state.isRecoveryCandidate,
              initial.state.actions.indices.contains(from),
              initial.state.actions.indices.contains(to),
              initial.actionValuePaths.count == initial.state.actions.count else {
            throw ShortcutsError.editCapabilityUnsupported
        }

        let copyNameSHA256 = initial.state.editorNameSHA256
        var currentResolution = initial
        var currentIndex = from
        while currentIndex != to {
            let direction: ShortcutAXMoveDirection = currentIndex < to ? .down : .up
            let nextIndex = direction == .down ? currentIndex + 1 : currentIndex - 1
            guard currentResolution.state.actions.indices.contains(nextIndex),
                  currentResolution.actionValuePaths.indices.contains(currentIndex),
                  currentResolution.state.actions[currentIndex] != currentResolution.state.actions[nextIndex] else {
                throw ShortcutsError.editCapabilityUnsupported
            }

            var expectedActions = currentResolution.state.actions
            let action = expectedActions.remove(at: currentIndex)
            expectedActions.insert(action, at: nextIndex)
            try driver.moveAction(
                at: currentResolution.actionValuePaths[currentIndex],
                direction: direction
            )
            lastResolution = nil

            let end = Date().addingTimeInterval(deadline)
            var verifiedResolution: ShortcutAXSemanticResolution?
            repeat {
                if let changed = try? driver.resolveEditor(recovery: true),
                   changed.state.editorNameSHA256 == copyNameSHA256,
                   changed.state.actions == expectedActions,
                   changed.actionValuePaths.count == expectedActions.count {
                    verifiedResolution = changed
                    break
                }
                if pollInterval > 0 { Thread.sleep(forTimeInterval: pollInterval) }
            } while Date() < end
            guard let verifiedResolution else { throw ShortcutsError.editEditorConflict }
            currentResolution = verifiedResolution
            currentIndex = nextIndex
        }
        lastResolution = currentResolution
    }
}

final class SystemShortcutAXMutationDriver: ShortcutAXSystemMutationDriving, @unchecked Sendable {
    private static let bundleIdentifier = "com.apple.shortcuts"
    private static let shortcutNameIdentifier = "editor.shortcutname"
    private static let duplicateMenuIdentifier = "duplicateShortcut:"
    private static let duplicateActionMenuIdentifier = "duplicateAction:"
    private static let moveActionUpMenuIdentifier = "rearrangeItemUp:"
    private static let moveActionDownMenuIdentifier = "rearrangeItemDown:"
    private static let maximumChildrenPerNode = 256
    private static let maximumMenuNodes = 512
    private static let maximumMenuDepth = 8

    private var elementByPath: [[Int]: AXUIElement] = [:]

    func resolveEditor(recovery: Bool) throws -> ShortcutAXSemanticResolution {
        guard AXIsProcessTrusted() else { throw ShortcutsError.permissionDenied }
        let application = try shortcutsApplication()
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 5)
        guard let windows = attribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
            throw ShortcutsError.editEditorConflict
        }
        let primaryWindows = windows.filter { window in
            (attribute(window, kAXMainAttribute as CFString) as? Bool) == true
                || (attribute(window, kAXFocusedAttribute as CFString) as? Bool) == true
        }
        guard primaryWindows.count == 1 else {
            DiagnosticLogger.record(
                code: "SHORTCUTS_AX_PRIMARY_WINDOW_CONFLICT",
                message: "windowCount=\(windows.count) primaryWindowCount=\(primaryWindows.count)"
            )
            throw ShortcutsError.editEditorConflict
        }

        var elements: [[Int]: AXUIElement] = [:]
        var roots: [ShortcutAXSemanticNode] = []
        var diagnostics: [String] = []
        for (index, window) in primaryWindows.enumerated() {
            elements[[index]] = window
            let windowChildren = children(of: window)
            let toolbars = windowChildren.filter { role(of: $0) == "AXToolbar" }
            let splitGroups = windowChildren.filter { role(of: $0) == "AXSplitGroup" }
            guard toolbars.count == 1,
                  splitGroups.count == 1,
                  let toolbar = toolbars.first,
                  let nameField = exactNameField(in: toolbar),
                  let splitGroup = splitGroups.first else {
                diagnostics.append("window=\(index) directRoles=\(windowChildren.map { role(of: $0) }.sorted().joined(separator: ",")) toolbarCount=\(toolbars.count) splitCount=\(splitGroups.count) nameField=false")
                roots.append(.init(role: "AXWindow"))
                continue
            }
            let canvasCandidates = children(of: splitGroup).filter { element in
                guard role(of: element) == "AXScrollArea" else { return false }
                return children(of: element).contains { child in
                    guard role(of: child) == "AXStaticText" else { return false }
                    let title = (attribute(child, kAXValueAttribute as CFString) as? String)
                        ?? (attribute(child, kAXDescriptionAttribute as CFString) as? String)
                        ?? (attribute(child, kAXTitleAttribute as CFString) as? String)
                    return title == "Text" || title == "Comment"
                }
            }
            guard canvasCandidates.count == 1, let canvas = canvasCandidates.first else {
                diagnostics.append("window=\(index) directRoles=\(windowChildren.map { role(of: $0) }.sorted().joined(separator: ",")) toolbarCount=1 splitCount=1 nameField=true canvasCount=\(canvasCandidates.count)")
                roots.append(.init(role: "AXWindow"))
                continue
            }
            diagnostics.append("window=\(index) toolbarCount=1 splitCount=1 nameField=true canvasCount=1")
            let canvasNode = snapshot(canvas, path: [index, 0], depth: 0, elements: &elements, preferNavigationOrder: true)
            let nameNode = snapshot(nameField, path: [index, 1], depth: 0, elements: &elements)
            roots.append(.init(role: "AXWindow", children: [canvasNode, nameNode]))
        }
        let resolution: ShortcutAXSemanticResolution
        do {
            resolution = try ShortcutAXSemanticResolver().resolve(roots: roots, recovery: recovery)
        } catch {
            DiagnosticLogger.record(code: "SHORTCUTS_AX_RESOLVE_FAILED", message: "windowCount=\(windows.count) primaryWindowCount=\(primaryWindows.count) \(diagnostics.joined(separator: " | "))")
            throw error
        }
        elementByPath = elements
        return resolution
    }

    func duplicateShortcut() throws {
        guard AXIsProcessTrusted() else { throw ShortcutsError.permissionDenied }
        let application = try shortcutsApplication()
        application.activate(options: [.activateAllWindows])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 5)
        guard let menuBarValue = attribute(appElement, kAXMenuBarAttribute as CFString),
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            throw ShortcutsError.editRecoveryFailed
        }
        let menuBar = menuBarValue as! AXUIElement
        guard let fileItem = directMenuBarItem(menuBar, title: "File"),
              AXUIElementPerformAction(fileItem, kAXPressAction as CFString) == .success else {
            throw ShortcutsError.editRecoveryFailed
        }

        let end = Date().addingTimeInterval(2)
        repeat {
            if let item = exactMenuItem(in: menuBar, identifier: Self.duplicateMenuIdentifier),
               isEnabled(item),
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                elementByPath.removeAll(keepingCapacity: false)
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < end
        _ = AXUIElementPerformAction(fileItem, kAXPressAction as CFString)
        throw ShortcutsError.editRecoveryFailed
    }

    func duplicateAction(at path: [Int]) throws {
        guard AXIsProcessTrusted() else { throw ShortcutsError.permissionDenied }
        guard let element = elementByPath[path],
              role(of: element) == "AXTextArea",
              AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw ShortcutsError.editEditorConflict
        }
        let application = try shortcutsApplication()
        application.activate(options: [.activateAllWindows])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 5)
        guard let menuBarValue = attribute(appElement, kAXMenuBarAttribute as CFString),
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            throw ShortcutsError.editEditorConflict
        }
        let menuBar = menuBarValue as! AXUIElement
        guard let editItem = directMenuBarItem(menuBar, title: "Edit"),
              AXUIElementPerformAction(editItem, kAXPressAction as CFString) == .success else {
            throw ShortcutsError.editEditorConflict
        }

        let end = Date().addingTimeInterval(2)
        repeat {
            if let item = exactMenuItem(in: menuBar, identifier: Self.duplicateActionMenuIdentifier),
               isEnabled(item),
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                elementByPath.removeAll(keepingCapacity: false)
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < end
        _ = AXUIElementPerformAction(editItem, kAXPressAction as CFString)
        throw ShortcutsError.editEditorConflict
    }

    func setTextValue(_ value: String, at path: [Int]) throws {
        guard Data(value.utf8).count <= ShortcutEditPlanService.maximumValueBytes,
              let element = elementByPath[path],
              attribute(element, kAXRoleAttribute as CFString) as? String == "AXTextArea",
              isSettable(element, kAXValueAttribute as CFString),
              AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success else {
            throw ShortcutsError.editEditorConflict
        }
        elementByPath.removeAll(keepingCapacity: false)
    }

    func deleteAction(at path: [Int]) throws {
        guard AXIsProcessTrusted() else { throw ShortcutsError.permissionDenied }
        guard let element = elementByPath[path],
              role(of: element) == "AXButton",
              (attribute(element, kAXDescriptionAttribute as CFString) as? String
                ?? attribute(element, kAXTitleAttribute as CFString) as? String) == "Close",
              AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw ShortcutsError.editEditorConflict
        }
        elementByPath.removeAll(keepingCapacity: false)
    }

    func moveAction(at path: [Int], direction: ShortcutAXMoveDirection) throws {
        guard AXIsProcessTrusted() else { throw ShortcutsError.permissionDenied }
        guard let element = elementByPath[path],
              role(of: element) == "AXTextArea",
              AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw ShortcutsError.editEditorConflict
        }
        let application = try shortcutsApplication()
        application.activate(options: [.activateAllWindows])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 5)
        guard let menuBarValue = attribute(appElement, kAXMenuBarAttribute as CFString),
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            throw ShortcutsError.editEditorConflict
        }
        let menuBar = menuBarValue as! AXUIElement
        guard let editItem = directMenuBarItem(menuBar, title: "Edit"),
              AXUIElementPerformAction(editItem, kAXPressAction as CFString) == .success else {
            throw ShortcutsError.editEditorConflict
        }
        let identifier = direction == .up
            ? Self.moveActionUpMenuIdentifier
            : Self.moveActionDownMenuIdentifier
        let end = Date().addingTimeInterval(2)
        repeat {
            if let item = exactMenuItem(in: menuBar, identifier: identifier),
               isEnabled(item),
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                elementByPath.removeAll(keepingCapacity: false)
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < end
        _ = AXUIElementPerformAction(editItem, kAXPressAction as CFString)
        throw ShortcutsError.editEditorConflict
    }

    private func shortcutsApplication() throws -> NSRunningApplication {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            throw ShortcutsError.targetNotRunning
        }
        return application
    }

    private func snapshot(
        _ element: AXUIElement,
        path: [Int],
        depth: Int,
        elements: inout [[Int]: AXUIElement],
        preferNavigationOrder: Bool = false
    ) -> ShortcutAXSemanticNode {
        elements[path] = element
        let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? "AXUnknown"
        let identifier = attribute(element, kAXIdentifierAttribute as CFString) as? String
        let label = (attribute(element, kAXDescriptionAttribute as CFString) as? String)
            ?? (attribute(element, kAXTitleAttribute as CFString) as? String)
        let value: String?
        if role == "AXStaticText" || role == "AXTextArea" || (role == "AXTextField" && identifier == Self.shortcutNameIdentifier) {
            value = attribute(element, kAXValueAttribute as CFString) as? String
        } else {
            value = nil
        }
        let valueSettable = (role == "AXTextArea" || (role == "AXTextField" && identifier == Self.shortcutNameIdentifier))
            && isSettable(element, kAXValueAttribute as CFString)
        let positionY = positionY(of: element)
        let children = semanticChildren(of: element, preferNavigationOrder: preferNavigationOrder)
        guard depth < ShortcutAccessibilityDiscoveryService.maximumDepth else {
            return .init(role: role, identifier: identifier, label: label, value: value, valueSettable: valueSettable, positionY: positionY, truncated: !children.isEmpty)
        }
        let truncated = children.count > Self.maximumChildrenPerNode
        let nodes = children.prefix(Self.maximumChildrenPerNode).enumerated().map { index, child in
            snapshot(child, path: path + [index], depth: depth + 1, elements: &elements)
        }
        return .init(role: role, identifier: identifier, label: label, value: value, valueSettable: valueSettable, positionY: positionY, children: nodes, truncated: truncated)
    }

    private func semanticChildren(of element: AXUIElement, preferNavigationOrder: Bool) -> [AXUIElement] {
        let ordinary = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
        guard preferNavigationOrder,
              let navigation = attribute(element, "AXChildrenInNavigationOrder" as CFString) as? [AXUIElement] else { return ordinary }
        guard navigation.count == ordinary.count else { return ordinary }
        let ordinaryKinds = ordinary.compactMap(semanticNavigationActionKind).sorted()
        let navigationKinds = navigation.compactMap(semanticNavigationActionKind).sorted()
        let navigationStaticCount = navigation.filter { role(of: $0) == "AXStaticText" }.count
        guard !ordinaryKinds.isEmpty,
              ordinaryKinds == navigationKinds,
              navigationStaticCount == navigationKinds.count else { return ordinary }
        return navigation
    }

    private func semanticNavigationActionKind(_ element: AXUIElement) -> String? {
        guard role(of: element) == "AXStaticText" else { return nil }
        let title = (attribute(element, kAXValueAttribute as CFString) as? String)
            ?? (attribute(element, kAXDescriptionAttribute as CFString) as? String)
            ?? (attribute(element, kAXTitleAttribute as CFString) as? String)
        return title == "Text" || title == "Comment" ? title : nil
    }

    private func positionY(of element: AXUIElement) -> Double? {
        guard let raw = attribute(element, kAXPositionAttribute as CFString),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let position = raw as! AXValue
        guard AXValueGetType(position) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(position, .cgPoint, &point), point.y.isFinite else { return nil }
        return Double(point.y)
    }

    private func directMenuBarItem(_ menuBar: AXUIElement, title: String) -> AXUIElement? {
        let children = attribute(menuBar, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
        return children.first { item in
            attribute(item, kAXRoleAttribute as CFString) as? String == "AXMenuBarItem"
                && attribute(item, kAXTitleAttribute as CFString) as? String == title
        }
    }

    private func exactNameField(in toolbar: AXUIElement) -> AXUIElement? {
        var pending: [(AXUIElement, Int)] = [(toolbar, 0)]
        var matches: [AXUIElement] = []
        var visited = 0
        while let (element, depth) = pending.popLast() {
            visited += 1
            guard visited <= 64, depth <= 4 else { return nil }
            if role(of: element) == "AXTextField",
               attribute(element, kAXIdentifierAttribute as CFString) as? String == Self.shortcutNameIdentifier,
               isSettable(element, kAXValueAttribute as CFString) {
                matches.append(element)
            }
            pending.append(contentsOf: children(of: element).map { ($0, depth + 1) })
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func exactMenuItem(in root: AXUIElement, identifier: String) -> AXUIElement? {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while let (element, depth) = pending.popLast() {
            visited += 1
            guard visited <= Self.maximumMenuNodes, depth <= Self.maximumMenuDepth else { return nil }
            if attribute(element, kAXRoleAttribute as CFString) as? String == "AXMenuItem",
               attribute(element, kAXIdentifierAttribute as CFString) as? String == identifier {
                return element
            }
            let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
            pending.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return nil
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXEnabledAttribute as CFString) as? Bool) == true
    }

    private func role(of element: AXUIElement) -> String {
        attribute(element, kAXRoleAttribute as CFString) as? String ?? "AXUnknown"
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    private func isSettable(_ element: AXUIElement, _ name: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name, &settable) == .success && settable.boolValue
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }
}

@_spi(ShortcutsFixtureGate)
public struct ShortcutAXFixtureGateResult: Codable, Equatable, Sendable {
    public let operation: String
    public let status: String
    public let actionCount: Int
    public let copyIdentityChanged: Bool
    public let originalVerificationPending: Bool
    public let canRetryAutomatically: Bool
}

@_spi(ShortcutsFixtureGate)
public struct ShortcutAXReplaceTextFixtureGate: Sendable {
    public static let confirmationPhrase = "RUN SHORTCUT AX FIXTURE GATE"

    public init() {}

    public func mutateCopy(
        expectedNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String,
        replacement: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        guard confirmation == Self.confirmationPhrase,
              Data(replacement.utf8).count <= ShortcutEditPlanService.maximumValueBytes else {
            throw ShortcutsError.editConfirmationRequired
        }

        let session = SystemShortcutAccessibilityMutationSession()
        let original = try session.inspectEditor()
        guard matches(
            original,
            nameSHA256: expectedNameSHA256,
            textSHA256: expectedTextSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: false
        ) else { throw ShortcutsError.editEditorConflict }

        try session.duplicateEditor()
        let copy = try session.inspectEditor()
        guard copy.editorNameSHA256 != original.editorNameSHA256,
              copy.actions == original.actions,
              copy.isRecoveryCandidate else {
            throw ShortcutsError.editRecoveryFailed
        }

        try session.replaceText(at: 0, value: replacement)
        let changed = try session.inspectEditor()
        let replacementSHA256 = CherriSourceValidator.hash(Data(replacement.utf8))
        guard matches(
            changed,
            nameSHA256: copy.editorNameSHA256,
            textSHA256: replacementSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: true
        ) else { throw ShortcutsError.editEditorConflict }

        return .init(
            operation: "shortcuts_ax_fixture_copy_replace",
            status: "copy_readback_confirmed",
            actionCount: changed.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    public func deleteCommentFromCopy(
        expectedNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        guard confirmation == Self.confirmationPhrase else {
            throw ShortcutsError.editConfirmationRequired
        }

        let session = SystemShortcutAccessibilityMutationSession()
        let original = try session.inspectEditor()
        guard matches(
            original,
            nameSHA256: expectedNameSHA256,
            textSHA256: expectedTextSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: false
        ) else { throw ShortcutsError.editEditorConflict }

        try session.duplicateEditor()
        let copy = try session.inspectEditor()
        guard copy.editorNameSHA256 != original.editorNameSHA256,
              copy.actions == original.actions,
              copy.isRecoveryCandidate else {
            throw ShortcutsError.editRecoveryFailed
        }

        try session.deleteAction(at: 1)
        let changed = try session.inspectEditor()
        guard changed.bounded,
              changed.candidateCount == 1,
              changed.isRecoveryCandidate,
              changed.editorNameSHA256 == copy.editorNameSHA256,
              changed.actions == [.init(kind: .text, valueSHA256: expectedTextSHA256)] else {
            throw ShortcutsError.editEditorConflict
        }

        return .init(
            operation: "shortcuts_ax_fixture_copy_delete",
            status: "copy_readback_confirmed",
            actionCount: changed.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    public func moveCommentBeforeTextFromCopy(
        expectedNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        guard confirmation == Self.confirmationPhrase else {
            throw ShortcutsError.editConfirmationRequired
        }

        let session = SystemShortcutAccessibilityMutationSession()
        let original = try session.inspectEditor()
        guard matches(
            original,
            nameSHA256: expectedNameSHA256,
            textSHA256: expectedTextSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: false
        ) else { throw ShortcutsError.editEditorConflict }

        try session.duplicateEditor()
        let copy = try session.inspectEditor()
        guard copy.editorNameSHA256 != original.editorNameSHA256,
              copy.actions == original.actions,
              copy.isRecoveryCandidate else {
            throw ShortcutsError.editRecoveryFailed
        }

        try session.moveAction(from: 1, to: 0)
        let changed = try session.inspectEditor()
        guard changed.bounded,
              changed.candidateCount == 1,
              changed.isRecoveryCandidate,
              changed.editorNameSHA256 == copy.editorNameSHA256,
              changed.actions == [
                .init(kind: .comment, valueSHA256: expectedCommentSHA256),
                .init(kind: .text, valueSHA256: expectedTextSHA256),
              ] else {
            throw ShortcutsError.editEditorConflict
        }

        return .init(
            operation: "shortcuts_ax_fixture_copy_move",
            status: "copy_readback_confirmed",
            actionCount: changed.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    public func verifyOriginal(
        expectedNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        let state = try SystemShortcutAccessibilityMutationSession().inspectEditor()
        guard matches(
            state,
            nameSHA256: expectedNameSHA256,
            textSHA256: expectedTextSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: false
        ) else { throw ShortcutsError.editEditorConflict }
        return .init(
            operation: "shortcuts_ax_fixture_verify_original",
            status: "original_readback_confirmed",
            actionCount: state.actions.count,
            copyIdentityChanged: false,
            originalVerificationPending: false,
            canRetryAutomatically: false
        )
    }

    public func verifyExistingDeletedCopy(
        expectedOriginalNameSHA256: String,
        expectedCopyNameSHA256: String,
        expectedTextSHA256: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedOriginalNameSHA256)
        try validateHash(expectedCopyNameSHA256)
        try validateHash(expectedTextSHA256)
        guard expectedCopyNameSHA256 != expectedOriginalNameSHA256,
              confirmation == Self.confirmationPhrase else {
            throw ShortcutsError.editConfirmationRequired
        }

        let state = try SystemShortcutAccessibilityMutationSession(
            resumingRecoveryFrom: expectedOriginalNameSHA256
        ).inspectEditor()
        guard state.bounded,
              state.candidateCount == 1,
              state.isRecoveryCandidate,
              state.editorNameSHA256 == expectedCopyNameSHA256,
              state.actions == [.init(kind: .text, valueSHA256: expectedTextSHA256)] else {
            throw ShortcutsError.editRecoveryFailed
        }
        return .init(
            operation: "shortcuts_ax_fixture_copy_delete_readback",
            status: "copy_readback_confirmed",
            actionCount: state.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    public func verifyExistingMovedCopy(
        expectedOriginalNameSHA256: String,
        expectedCopyNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedOriginalNameSHA256)
        try validateHash(expectedCopyNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        guard expectedCopyNameSHA256 != expectedOriginalNameSHA256,
              confirmation == Self.confirmationPhrase else {
            throw ShortcutsError.editConfirmationRequired
        }

        let state = try SystemShortcutAccessibilityMutationSession(
            resumingRecoveryFrom: expectedOriginalNameSHA256
        ).inspectEditor()
        guard state.bounded,
              state.candidateCount == 1,
              state.isRecoveryCandidate,
              state.editorNameSHA256 == expectedCopyNameSHA256,
              state.actions == [
                .init(kind: .comment, valueSHA256: expectedCommentSHA256),
                .init(kind: .text, valueSHA256: expectedTextSHA256),
              ] else {
            throw ShortcutsError.editRecoveryFailed
        }
        return .init(
            operation: "shortcuts_ax_fixture_copy_move_readback",
            status: "copy_readback_confirmed",
            actionCount: state.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    public func resumeExistingCopy(
        expectedOriginalNameSHA256: String,
        expectedCopyNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String,
        replacement: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedOriginalNameSHA256)
        try validateHash(expectedCopyNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        guard expectedCopyNameSHA256 != expectedOriginalNameSHA256,
              confirmation == Self.confirmationPhrase,
              Data(replacement.utf8).count <= ShortcutEditPlanService.maximumValueBytes else {
            throw ShortcutsError.editConfirmationRequired
        }

        let session = SystemShortcutAccessibilityMutationSession(
            resumingRecoveryFrom: expectedOriginalNameSHA256
        )
        let copy = try session.inspectEditor()
        guard matches(
            copy,
            nameSHA256: expectedCopyNameSHA256,
            textSHA256: expectedTextSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: true
        ) else { throw ShortcutsError.editRecoveryFailed }

        try session.replaceText(at: 0, value: replacement)
        let changed = try session.inspectEditor()
        guard matches(
            changed,
            nameSHA256: expectedCopyNameSHA256,
            textSHA256: CherriSourceValidator.hash(Data(replacement.utf8)),
            commentSHA256: expectedCommentSHA256,
            recovery: true
        ) else { throw ShortcutsError.editEditorConflict }

        return .init(
            operation: "shortcuts_ax_fixture_resume_copy_replace",
            status: "copy_readback_confirmed",
            actionCount: changed.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    public func resumeExistingCopyMove(
        expectedOriginalNameSHA256: String,
        expectedCopyNameSHA256: String,
        expectedTextSHA256: String,
        expectedCommentSHA256: String,
        confirmation: String
    ) throws -> ShortcutAXFixtureGateResult {
        try validateHash(expectedOriginalNameSHA256)
        try validateHash(expectedCopyNameSHA256)
        try validateHash(expectedTextSHA256)
        try validateHash(expectedCommentSHA256)
        guard expectedCopyNameSHA256 != expectedOriginalNameSHA256,
              confirmation == Self.confirmationPhrase else {
            throw ShortcutsError.editConfirmationRequired
        }

        let session = SystemShortcutAccessibilityMutationSession(
            resumingRecoveryFrom: expectedOriginalNameSHA256
        )
        let copy = try session.inspectEditor()
        guard matches(
            copy,
            nameSHA256: expectedCopyNameSHA256,
            textSHA256: expectedTextSHA256,
            commentSHA256: expectedCommentSHA256,
            recovery: true
        ) else { throw ShortcutsError.editRecoveryFailed }

        try session.moveAction(from: 1, to: 0)
        let changed = try session.inspectEditor()
        guard changed.bounded,
              changed.candidateCount == 1,
              changed.isRecoveryCandidate,
              changed.editorNameSHA256 == expectedCopyNameSHA256,
              changed.actions == [
                .init(kind: .comment, valueSHA256: expectedCommentSHA256),
                .init(kind: .text, valueSHA256: expectedTextSHA256),
              ] else {
            throw ShortcutsError.editEditorConflict
        }

        return .init(
            operation: "shortcuts_ax_fixture_resume_copy_move",
            status: "copy_readback_confirmed",
            actionCount: changed.actions.count,
            copyIdentityChanged: true,
            originalVerificationPending: true,
            canRetryAutomatically: false
        )
    }

    private func matches(
        _ state: ShortcutSemanticEditorState,
        nameSHA256: String,
        textSHA256: String,
        commentSHA256: String,
        recovery: Bool
    ) -> Bool {
        state.bounded
            && state.candidateCount == 1
            && state.isRecoveryCandidate == recovery
            && state.editorNameSHA256 == nameSHA256
            && state.actions == [
                .init(kind: .text, valueSHA256: textSHA256),
                .init(kind: .comment, valueSHA256: commentSHA256),
            ]
    }

    private func validateHash(_ value: String) throws {
        guard value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw ShortcutsError.editPlanInvalid
        }
    }
}
