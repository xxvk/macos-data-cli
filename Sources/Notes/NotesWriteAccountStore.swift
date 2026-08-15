import Core
import Foundation

public final class NotesWriteAccountStore: @unchecked Sendable {
    private let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("notes-write-account.json") }

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/mpia-cli/config", isDirectory: true)) {
        self.directory = directory
    }

    public func load() throws -> NotesWriteAccountBinding? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(NotesWriteAccountBinding.self, from: Data(contentsOf: fileURL)), value.version == 1 else {
            throw NotesError.writeAccountStale
        }
        return value
    }

    public func save(_ value: NotesWriteAccountBinding) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func clear() throws { if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) } }
}
