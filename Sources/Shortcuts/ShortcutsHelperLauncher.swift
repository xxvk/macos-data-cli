import AppKit
import Foundation

enum ShortcutsHelperLauncher {
    static let bundleIdentifier = "com.apple.shortcuts.events"

    static func launch() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return true
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in }
        return true
    }
}
