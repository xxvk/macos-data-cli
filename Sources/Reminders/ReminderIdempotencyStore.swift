import Core
import CryptoKit
import Foundation

public struct ReminderIdempotencyReceipt: Codable, Equatable, Sendable {
    public let reminderID: String
    public let listID: String
    public let createdAt: Date

    public init(reminderID: String, listID: String, createdAt: Date) {
        self.reminderID = reminderID
        self.listID = listID
        self.createdAt = createdAt
    }
}

public final class ReminderIdempotencyStore: @unchecked Sendable {
    private let directory: URL
    private let validity: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/macos-data-cli/idempotency/reminders", isDirectory: true),
        validity: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.validity = validity
        self.now = now
    }

    public func fingerprint(for input: ReminderInput) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return SHA256.hash(data: try encoder.encode(input)).map { String(format: "%02x", $0) }.joined()
    }

    public func receipt(for input: ReminderInput) throws -> ReminderIdempotencyReceipt? {
        let url = directory.appendingPathComponent(try fingerprint(for: input) + ".json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let receipt = try? decoder.decode(ReminderIdempotencyReceipt.self, from: data) else { return nil }
        let age = now().timeIntervalSince(receipt.createdAt)
        guard age >= 0, age <= validity else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return receipt
    }

    public func save(_ receipt: ReminderIdempotencyReceipt, for input: ReminderInput) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent(try fingerprint(for: input) + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
