import Core
import CryptoKit
import Foundation

public enum NotesFolderPagination {
    private static let prefix = "notesfolderpage_"

    public static func page(
        items: [NotesFolderPayload],
        accountID: String?,
        parentID: String?,
        limit: Int,
        cursor: String?,
        complete: Bool
    ) throws -> PagedResult<NotesFolderPayload> {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw PaginationError.invalidLimit }
        let fingerprint = digest("notes-folders-v1:\(accountID ?? "*"):\(parentID ?? "*")")
        let start = try startIndex(cursor, items: items, fingerprint: fingerprint)
        let end = min(start + limit, items.count)
        let selected = Array(items[start..<end])
        let truncated = end < items.count
        return PagedResult(
            items: selected,
            limit: limit,
            nextCursor: truncated ? selected.last.map { encode(id: $0.id, fingerprint: fingerprint) } : nil,
            truncated: truncated,
            complete: complete
        )
    }

    private static func startIndex(_ cursor: String?, items: [NotesFolderPayload], fingerprint: String) throws -> Int {
        guard let cursor else { return 0 }
        guard cursor.hasPrefix(prefix) else { throw PaginationError.invalidCursor }
        var encoded = String(cursor.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let value = String(data: data, encoding: .utf8) else { throw PaginationError.invalidCursor }
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "notes-folders-v1", parts[1] == Substring(fingerprint),
              let index = items.firstIndex(where: { digest($0.id) == parts[2] }) else {
            throw PaginationError.invalidCursor
        }
        return items.index(after: index)
    }

    private static func encode(id: String, fingerprint: String) -> String {
        prefix + Data("notes-folders-v1:\(fingerprint):\(digest(id))".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
