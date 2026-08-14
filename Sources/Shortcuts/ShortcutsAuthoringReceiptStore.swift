import Core
import Foundation

public enum ShortcutsAuthoringReceiptState: String, Codable, Equatable, Sendable {
    case inFlight = "in_flight"
    case saved
}

public struct ShortcutsAuthoringReceipt: Codable, Equatable, Sendable {
    public let version: Int
    public let state: ShortcutsAuthoringReceiptState
    public let sourceSHA256: String
    public let compiledSHA256: String
    public let actionCount: Int
    public let shortcutID: String?
    public let createdAt: Date
}

public final class ShortcutsAuthoringReceiptStore: @unchecked Sendable {
    private let directory: URL
    private let now: () -> Date
    private let lifetime: TimeInterval

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/macos-data-cli/shortcuts/receipts", isDirectory: true),
        now: @escaping () -> Date = Date.init,
        lifetime: TimeInterval = 60
    ) {
        self.directory = directory
        self.now = now
        self.lifetime = lifetime
    }

    public func receipt(sourceSHA256: String) throws -> ShortcutsAuthoringReceipt? {
        guard isSHA256(sourceSHA256) else { throw ShortcutsError.authorRegistryInvalid }
        let url = fileURL(sourceSHA256: sourceSHA256)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let value = try? decoder.decode(ShortcutsAuthoringReceipt.self, from: data),
              value.version == 1, value.sourceSHA256 == sourceSHA256,
              isSHA256(value.compiledSHA256),
              (1...CherriAuthoringBridge.maximumActionCount).contains(value.actionCount),
              value.shortcutID == nil || ShortcutsOpaqueID.isShortcut(value.shortcutID!) else {
            throw ShortcutsError.authorRegistryInvalid
        }
        guard now().timeIntervalSince(value.createdAt) <= lifetime else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return value
    }

    public func saveInFlight(build: ShortcutAuthorBuildResult) throws {
        try save(ShortcutsAuthoringReceipt(version: 1, state: .inFlight, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, shortcutID: nil, createdAt: now()))
    }

    public func saveCompleted(build: ShortcutAuthorBuildResult, shortcutID: String) throws {
        guard ShortcutsOpaqueID.isShortcut(shortcutID) else { throw ShortcutsError.authorRegistryInvalid }
        try save(ShortcutsAuthoringReceipt(version: 1, state: .saved, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, shortcutID: shortcutID, createdAt: now()))
    }

    public func remove(sourceSHA256: String) throws {
        guard isSHA256(sourceSHA256) else { throw ShortcutsError.authorRegistryInvalid }
        let url = fileURL(sourceSHA256: sourceSHA256)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func save(_ value: ShortcutsAuthoringReceipt) throws {
        guard isSHA256(value.sourceSHA256), isSHA256(value.compiledSHA256),
              (1...CherriAuthoringBridge.maximumActionCount).contains(value.actionCount) else {
            throw ShortcutsError.authorRegistryInvalid
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let url = fileURL(sourceSHA256: value.sourceSHA256)
        try encoder.encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func fileURL(sourceSHA256: String) -> URL { directory.appendingPathComponent("\(sourceSHA256).json") }
    private func isSHA256(_ value: String) -> Bool { value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil }
}
