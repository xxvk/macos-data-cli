import Core
import CryptoKit
import Foundation

public enum NotesIdempotencyState: String, Codable, Equatable, Sendable { case inFlight, saved }
public struct NotesIdempotencyReceipt: Codable, Equatable, Sendable {
    public let state: NotesIdempotencyState
    public let noteID: String?
    public let createdAt: Date
    public init(state: NotesIdempotencyState, noteID: String?, createdAt: Date) { self.state = state; self.noteID = noteID; self.createdAt = createdAt }
}

public final class NotesIdempotencyStore: @unchecked Sendable {
    private let directory: URL
    private let validity: TimeInterval
    private let now: @Sendable () -> Date
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/mpia-cli/idempotency/notes", isDirectory: true), validity: TimeInterval = 60, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory; self.validity = validity; self.now = now
    }
    public func receipt(for input: NotesCreateInput) throws -> NotesIdempotencyReceipt? {
        let url = try file(for: input)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(NotesIdempotencyReceipt.self, from: Data(contentsOf: url)) else { return nil }
        let age = now().timeIntervalSince(value.createdAt)
        guard age >= 0, age <= validity else { try? FileManager.default.removeItem(at: url); return nil }
        return value
    }
    public func begin(_ input: NotesCreateInput) throws { try save(.init(state: .inFlight, noteID: nil, createdAt: now()), for: input) }
    public func complete(_ input: NotesCreateInput, noteID: String) throws { try save(.init(state: .saved, noteID: noteID, createdAt: now()), for: input) }
    private func save(_ receipt: NotesIdempotencyReceipt, for input: NotesCreateInput) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let url = try file(for: input); try encoder.encode(receipt).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func file(for input: NotesCreateInput) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(input)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
}
