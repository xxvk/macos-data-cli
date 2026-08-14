import AppKit
import ApplicationServices
import Foundation

struct SystemShortcutAccessibilityReader: ShortcutAccessibilityReading, @unchecked Sendable {
    private static let bundleIdentifier = "com.apple.shortcuts"
    private static let maximumChildrenPerNode = 256

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func applicationSnapshot() -> [ShortcutAccessibilityNode]? {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            return nil
        }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        guard let windows = attribute(element, kAXWindowsAttribute as CFString) as? [AXUIElement] else { return [] }
        return windows.map { snapshot($0, depth: 0) }
    }

    private func snapshot(_ element: AXUIElement, depth: Int) -> ShortcutAccessibilityNode {
        let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? "AXUnknown"
        let identifier = attribute(element, kAXIdentifierAttribute as CFString) as? String
        let label = (attribute(element, kAXDescriptionAttribute as CFString) as? String) ?? (attribute(element, kAXTitleAttribute as CFString) as? String)
        guard let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return ShortcutAccessibilityNode(role: role, identifier: identifier, label: label)
        }
        guard depth < ShortcutAccessibilityDiscoveryService.maximumDepth else {
            return ShortcutAccessibilityNode(role: role, identifier: identifier, label: label, truncated: !children.isEmpty)
        }
        let truncated = children.count > Self.maximumChildrenPerNode
        return ShortcutAccessibilityNode(
            role: role,
            identifier: identifier,
            label: label,
            children: children.prefix(Self.maximumChildrenPerNode).map { snapshot($0, depth: depth + 1) },
            truncated: truncated
        )
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }
}
