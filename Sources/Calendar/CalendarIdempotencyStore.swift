import Core
import CryptoKit
import Foundation

public struct CalendarIdempotencyReceipt: Codable, Equatable, Sendable {
    public let eventID: String?
    public let calendarID: String?
    public let createdAt: Date
}

public final class CalendarIdempotencyStore: @unchecked Sendable {
    private let directory: URL
    private let now: @Sendable () -> Date
    private let validity: TimeInterval

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/macos-data-cli/idempotency/calendar", isDirectory: true),
        validity: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.validity = validity
        self.now = now
    }

    public func fingerprint(for input: CalendarEventInput) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let digest = SHA256.hash(data: try encoder.encode(input))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func receipt(for input: CalendarEventInput) throws -> CalendarIdempotencyReceipt? {
        let url = directory.appendingPathComponent(try fingerprint(for: input) + ".json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let receipt = try? decoder.decode(CalendarIdempotencyReceipt.self, from: data) else { return nil }
        let age = now().timeIntervalSince(receipt.createdAt)
        guard age >= 0, age <= validity else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return receipt
    }

    public func save(_ receipt: CalendarIdempotencyReceipt, for input: CalendarEventInput) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(try fingerprint(for: input) + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func invalidate(eventID: String?) {
        guard let eventID,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let receipt = try? decoder.decode(CalendarIdempotencyReceipt.self, from: data),
                  receipt.eventID == eventID else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
