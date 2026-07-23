import Foundation

public enum PaginationError: Error, Equatable, Sendable {
    case invalidLimit
    case invalidCursor
}

public struct PagedResult<Item: Codable & Sendable>: Codable, Equatable, Sendable where Item: Equatable {
    public let items: [Item]
    public let limit: Int
    public let nextCursor: String?
    public let truncated: Bool
    public let complete: Bool

    public init(
        items: [Item],
        limit: Int,
        nextCursor: String? = nil,
        truncated: Bool,
        complete: Bool
    ) {
        self.items = items
        self.limit = limit
        self.nextCursor = nextCursor
        self.truncated = truncated
        self.complete = complete
    }
}

public enum Pagination {
    public static let defaultLimit = 50
    public static let maximumLimit = 200

    public static func page<Item: Codable & Sendable & Equatable>(
        items: [Item],
        limit: Int = defaultLimit,
        cursor: String? = nil,
        prefix: String
    ) throws -> PagedResult<Item> {
        guard (1...maximumLimit).contains(limit) else { throw PaginationError.invalidLimit }
        let offset = try decodeOffset(cursor, prefix: prefix)
        guard offset <= items.count else { throw PaginationError.invalidCursor }

        let end = min(offset + limit, items.count)
        let selected = Array(items[offset..<end])
        let truncated = end < items.count
        let nextCursor = truncated ? encodeOffset(end, prefix: prefix) : nil
        return PagedResult(items: selected, limit: limit, nextCursor: nextCursor, truncated: truncated, complete: true)
    }

    private static func encodeOffset(_ offset: Int, prefix: String) -> String {
        let token = Data("pagination-v1:\(offset)".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(prefix)\(token)"
    }

    private static func decodeOffset(_ cursor: String?, prefix: String) throws -> Int {
        guard let cursor else { return 0 }
        guard cursor.hasPrefix(prefix) else { throw PaginationError.invalidCursor }
        var encoded = String(cursor.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let value = String(data: data, encoding: .utf8),
              value.hasPrefix("pagination-v1:"),
              let offset = Int(value.dropFirst("pagination-v1:".count)),
              offset >= 0 else {
            throw PaginationError.invalidCursor
        }
        return offset
    }
}
