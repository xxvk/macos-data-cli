import Foundation

public struct ShortcutsPermissionResult: Codable, Equatable, Sendable {
    public let access: ShortcutsAutomationStatus
    public let readable: Bool
    public let complete: Bool
    public let requested: Bool

    public init(access: ShortcutsAutomationStatus, requested: Bool) {
        self.access = access
        self.readable = access.readable
        self.complete = access.complete
        self.requested = requested
    }
}

public struct ShortcutPayload: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let folderID: String?
    public let acceptsInput: Bool
    public let actionCount: Int
    public let color: [Int]
    public let iconAvailable: Bool

    public init(id: String, name: String, subtitle: String, folderID: String?, acceptsInput: Bool, actionCount: Int, color: [Int], iconAvailable: Bool) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.folderID = folderID
        self.acceptsInput = acceptsInput
        self.actionCount = actionCount
        self.color = color
        self.iconAvailable = iconAvailable
    }
}

public struct ShortcutFolderPayload: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum ShortcutWriteVerification: String, Codable, Equatable, Sendable {
    case notApplied = "not_applied"
    case readbackConfirmed = "readback_confirmed"
}

public struct ShortcutMoveResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let shortcutID: String
    public let previousFolderID: String?
    public let destinationFolderID: String
    public let verification: ShortcutWriteVerification

    public init(operation: String, dryRun: Bool, changed: Bool, shortcutID: String, previousFolderID: String?, destinationFolderID: String, verification: ShortcutWriteVerification) {
        self.operation = operation
        self.dryRun = dryRun
        self.changed = changed
        self.shortcutID = shortcutID
        self.previousFolderID = previousFolderID
        self.destinationFolderID = destinationFolderID
        self.verification = verification
    }
}

public enum ShortcutRunVerification: String, Codable, Equatable, Sendable {
    case completed
}

public struct ShortcutRunResult: Codable, Equatable, Sendable {
    public let shortcutID: String
    public let verification: ShortcutRunVerification
    public let output: String?
    public let outputPath: String?
    public let outputBytes: Int
    public let outputSHA256: String

    public init(shortcutID: String, verification: ShortcutRunVerification, output: String?, outputPath: String?, outputBytes: Int, outputSHA256: String) {
        self.shortcutID = shortcutID
        self.verification = verification
        self.output = output
        self.outputPath = outputPath
        self.outputBytes = outputBytes
        self.outputSHA256 = outputSHA256
    }
}
