import Core
import CryptoKit
import Foundation

public struct NotesFolderIdempotencyReceipt: Codable, Equatable, Sendable {
    public let state: NotesIdempotencyState
    public let folderID: String?
    public let createdAt: Date
    public init(state: NotesIdempotencyState, folderID: String?, createdAt: Date) {
        self.state = state; self.folderID = folderID; self.createdAt = createdAt
    }
}

public final class NotesFolderIdempotencyStore: @unchecked Sendable {
    private let directory: URL
    private let validity: TimeInterval
    private let now: @Sendable () -> Date
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/macos-data-cli/idempotency/notes-folders", isDirectory: true), validity: TimeInterval = 60, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory; self.validity = validity; self.now = now
    }
    public func receipt(for input: NotesFolderCreateInput) throws -> NotesFolderIdempotencyReceipt? {
        let url = try file(for: input)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(NotesFolderIdempotencyReceipt.self, from: Data(contentsOf: url)) else { return nil }
        let age = now().timeIntervalSince(value.createdAt)
        guard age >= 0, age <= validity else { try? FileManager.default.removeItem(at: url); return nil }
        return value
    }
    public func begin(_ input: NotesFolderCreateInput) throws { try save(.init(state: .inFlight, folderID: nil, createdAt: now()), for: input) }
    public func complete(_ input: NotesFolderCreateInput, folderID: String) throws { try save(.init(state: .saved, folderID: folderID, createdAt: now()), for: input) }
    private func save(_ receipt: NotesFolderIdempotencyReceipt, for input: NotesFolderCreateInput) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let url = try file(for: input); try encoder.encode(receipt).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func file(for input: NotesFolderCreateInput) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(input)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
}
