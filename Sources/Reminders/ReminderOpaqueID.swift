import Core
import Foundation

public struct ReminderLocator: Codable, Equatable, Sendable {
    public let localIdentifier: String
    public let externalIdentifier: String?

    public init(localIdentifier: String, externalIdentifier: String?) {
        self.localIdentifier = localIdentifier
        self.externalIdentifier = externalIdentifier
    }
}

public enum ReminderOpaqueID {
    private static let prefix = "reminder_"

    public static func encode(localIdentifier: String, externalIdentifier: String?) -> String {
        let locator = ReminderLocator(localIdentifier: localIdentifier, externalIdentifier: externalIdentifier)
        let data = (try? JSONEncoder().encode(locator)) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ value: String) throws -> ReminderLocator {
        guard value.hasPrefix(prefix) else { throw ReminderError.reminderNotFound(value) }
        var encoded = String(value.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let locator = try? JSONDecoder().decode(ReminderLocator.self, from: data),
              !locator.localIdentifier.isEmpty else {
            throw ReminderError.reminderNotFound(value)
        }
        return locator
    }
}
