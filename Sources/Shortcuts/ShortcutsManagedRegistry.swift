import Core
import Foundation

public struct ManagedShortcutRecord: Codable, Equatable, Sendable {
    public let shortcutID: String
    public let sourceSHA256: String
    public let compiledSHA256: String
    public let actionCount: Int
    public let compilerVersion: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(shortcutID: String, sourceSHA256: String, compiledSHA256: String, actionCount: Int, compilerVersion: String, createdAt: Date, updatedAt: Date) {
        self.shortcutID = shortcutID
        self.sourceSHA256 = sourceSHA256
        self.compiledSHA256 = compiledSHA256
        self.actionCount = actionCount
        self.compilerVersion = compilerVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

private struct ManagedShortcutRegistryDocument: Codable {
    let version: Int
    var records: [ManagedShortcutRecord]
}

public final class ShortcutsManagedRegistry: @unchecked Sendable {
    private let directory: URL
    private let now: () -> Date
    public var fileURL: URL { directory.appendingPathComponent("managed-registry.json") }

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mpia-cli/shortcuts", isDirectory: true),
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.now = now
    }

    public func list() throws -> [ManagedShortcutRecord] {
        try load().records.sorted { $0.shortcutID < $1.shortcutID }
    }

    public func record(shortcutID: String) throws -> ManagedShortcutRecord? {
        try load().records.first { $0.shortcutID == shortcutID }
    }

    public func upsert(_ value: ManagedShortcutRecord) throws {
        try validate(value)
        var document = try load()
        let timestamp = now()
        if let index = document.records.firstIndex(where: { $0.shortcutID == value.shortcutID }) {
            let existing = document.records[index]
            document.records[index] = ManagedShortcutRecord(
                shortcutID: value.shortcutID,
                sourceSHA256: value.sourceSHA256,
                compiledSHA256: value.compiledSHA256,
                actionCount: value.actionCount,
                compilerVersion: value.compilerVersion,
                createdAt: existing.createdAt,
                updatedAt: timestamp
            )
        } else {
            document.records.append(ManagedShortcutRecord(
                shortcutID: value.shortcutID,
                sourceSHA256: value.sourceSHA256,
                compiledSHA256: value.compiledSHA256,
                actionCount: value.actionCount,
                compilerVersion: value.compilerVersion,
                createdAt: timestamp,
                updatedAt: timestamp
            ))
        }
        try save(document)
    }

    public func remove(shortcutID: String) throws {
        var document = try load()
        document.records.removeAll { $0.shortcutID == shortcutID }
        try save(document)
    }

    public func replace(previousShortcutID: String, with value: ManagedShortcutRecord) throws {
        try validate(value)
        var document = try load()
        guard let previous = document.records.first(where: { $0.shortcutID == previousShortcutID }) else {
            throw ShortcutsError.authorManagedOnly
        }
        document.records.removeAll { $0.shortcutID == previousShortcutID || $0.shortcutID == value.shortcutID }
        document.records.append(ManagedShortcutRecord(
            shortcutID: value.shortcutID,
            sourceSHA256: value.sourceSHA256,
            compiledSHA256: value.compiledSHA256,
            actionCount: value.actionCount,
            compilerVersion: value.compilerVersion,
            createdAt: previous.createdAt,
            updatedAt: now()
        ))
        try save(document)
    }

    private func load() throws -> ManagedShortcutRegistryDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ManagedShortcutRegistryDocument(version: 1, records: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? decoder.decode(ManagedShortcutRegistryDocument.self, from: data),
              document.version == 1,
              Set(document.records.map(\.shortcutID)).count == document.records.count else {
            throw ShortcutsError.authorRegistryInvalid
        }
        try document.records.forEach(validate)
        return document
    }

    private func save(_ document: ManagedShortcutRegistryDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func validate(_ value: ManagedShortcutRecord) throws {
        guard ShortcutsOpaqueID.isShortcut(value.shortcutID),
              isSHA256(value.sourceSHA256), isSHA256(value.compiledSHA256),
              (1...CherriAuthoringBridge.maximumActionCount).contains(value.actionCount),
              !value.compilerVersion.isEmpty, value.compilerVersion.count <= 64,
              value.createdAt <= value.updatedAt else {
            throw ShortcutsError.authorRegistryInvalid
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }
}
