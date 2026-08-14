import CryptoKit
import Foundation

public enum ReminderPagination {
    private static let prefix = "rempage_"

    public static func page(
        items: [ReminderPayload],
        query: ReminderQuery,
        selectedListIDs: [String]
    ) throws -> PagedResult<ReminderPayload> {
        let fingerprint = queryFingerprint(query, selectedListIDs: selectedListIDs)
        let start = try startIndex(query.cursor, items: items, expectedFingerprint: fingerprint)
        let end = min(start + query.limit, items.count)
        let selected = Array(items[start..<end])
        let truncated = end < items.count
        return PagedResult(
            items: selected,
            limit: query.limit,
            nextCursor: truncated ? selected.last.map { encodeAnchor($0, fingerprint: fingerprint) } : nil,
            truncated: truncated,
            complete: true
        )
    }

    private static func queryFingerprint(_ query: ReminderQuery, selectedListIDs: [String]) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        let canonical = [
            "reminder-query-v1",
            query.status.rawValue,
            query.dueStart.map { String($0.timeIntervalSince1970) } ?? "",
            query.dueEnd.map { String($0.timeIntervalSince1970) } ?? "",
            query.listID ?? "",
            query.title?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale).lowercased(with: locale) ?? "",
            selectedListIDs.sorted().joined(separator: "\u{1e}"),
            "ordering-v1"
        ].joined(separator: "\u{1f}")
        return digest(canonical)
    }

    private static func encodeAnchor(_ item: ReminderPayload, fingerprint: String) -> String {
        let value = Data("reminder-pagination-v2:\(fingerprint):\(anchorFingerprint(item))".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + value
    }

    private static func startIndex(
        _ cursor: String?,
        items: [ReminderPayload],
        expectedFingerprint: String
    ) throws -> Int {
        guard let cursor else { return 0 }
        guard cursor.hasPrefix(prefix) else { throw PaginationError.invalidCursor }
        var encoded = String(cursor.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let decoded = String(data: data, encoding: .utf8) else { throw PaginationError.invalidCursor }
        let parts = decoded.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "reminder-pagination-v2",
              parts[1] == Substring(expectedFingerprint),
              let anchorIndex = items.firstIndex(where: { anchorFingerprint($0) == parts[2] }) else {
            throw PaginationError.invalidCursor
        }
        return items.index(after: anchorIndex)
    }

    private static func anchorFingerprint(_ item: ReminderPayload) -> String {
        let canonical = [
            item.completed ? "1" : "0",
            item.due?.value ?? "",
            item.due?.timeZone ?? "",
            item.due?.hasTime == true ? "1" : "0",
            item.due?.floating == true ? "1" : "0",
            item.completionDate.map { String($0.timeIntervalSince1970) } ?? "",
            item.listID,
            item.title,
            item.id
        ].joined(separator: "\u{1f}")
        return digest(canonical)
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ReminderFetchPolicy: Equatable, Sendable {
    public static let standard = ReminderFetchPolicy(maximumItems: 5_000, timeoutSeconds: 10)
    public let maximumItems: Int
    public let timeoutSeconds: TimeInterval

    public init(maximumItems: Int, timeoutSeconds: TimeInterval = 10) {
        self.maximumItems = maximumItems
        self.timeoutSeconds = timeoutSeconds
    }

    public func validate(itemCount: Int) throws {
        guard itemCount <= maximumItems else { throw ReminderError.scanLimitExceeded(maximumItems) }
    }
}
